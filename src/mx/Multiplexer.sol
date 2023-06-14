// SPDX-License-Identifier: BSL
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { YieldSlice } from "../core/YieldSlice.sol";
import { NPVToken } from "../tokens/NPVToken.sol";

contract Multiplexer {
    using SafeERC20 for IERC20;

    NPVToken public immutable mxToken;
    IERC20 public immutable yieldToken;

    struct TokenConfig {
        bool mintable;
        bool redeemable;
        uint256 limit;
        uint256 supply;
    }
    mapping(address => TokenConfig) public whitelist;

    address public gov;

    event Mint(address indexed recipient, address indexed tokenIn, uint256 amount);
    event Redeem(address indexed recipient, address indexed tokenOut, uint256 amount);

    modifier onlyGov() {
        require(msg.sender == gov, "MX: only gov");
        _;
    }

    constructor(string memory symbol, address yieldToken_) {
        gov = msg.sender;

        mxToken = new NPVToken(symbol, symbol);
        yieldToken = IERC20(yieldToken_);
    }

    function addToWhitelist(YieldSlice slice, uint256 limit) external onlyGov {
        require(address(slice.yieldToken()) == address(yieldToken),
                "MX: incompatible yield token"); 
        address token = address(slice.npvToken());
        require(!whitelist[token].mintable, "MX: already whitelisted");

        whitelist[token].mintable = true;
        whitelist[token].redeemable = true;
        whitelist[token].limit = limit;
    }

    function removeFromWhitelist(address token, uint256 limit) external onlyGov {
        require(whitelist[token].mintable, "MX: not whitelisted");

        whitelist[token].mintable = false;
    }

    function modifyLimit(address token, uint256 limit) external onlyGov {
        whitelist[token].limit = limit;
    }

    function remaining(address token) public view returns (uint256) {
        if (whitelist[token].limit == 0) {
            return type(uint256).max;
        } else {
            return whitelist[token].limit - whitelist[token].supply;
        }
    }

    function previewMint(address tokenIn, uint256 amount) external view returns (uint256) {
        require(remaining(tokenIn) >= amount, "MX: token limit");
        return amount;
    }

    function mint(address recipient, address tokenIn, uint256 amount)
        external
        returns (uint256) {

        require(whitelist[tokenIn].mintable, "MX: not mintable");
        require(remaining(tokenIn) >= amount, "MX: token limit");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amount);
        mxToken.mint(recipient, amount);
        whitelist[tokenIn].supply += amount;

        emit Mint(recipient, tokenIn, amount);

        return amount;
    }

    function redeem(address recipient, address tokenOut, uint256 amount)
        external
        returns (uint256) {

        require(whitelist[tokenOut].redeemable, "MX: not redeemable");
        require(whitelist[tokenOut].supply >= amount, "MX: insufficient supply");

        IERC20(mxToken).safeTransferFrom(msg.sender, address(this), amount);
        mxToken.burn(address(this), amount);
        IERC20(tokenOut).safeTransfer(msg.sender, amount);
        whitelist[tokenOut].supply -= amount;

        emit Redeem(recipient, tokenOut, amount);

        return amount;
    }
}
