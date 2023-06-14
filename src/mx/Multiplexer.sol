// SPDX-License-Identifier: BSL
pragma solidity ^0.8.13;

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

    /// @notice Add a yield slice to the whitelist for minting.
    /// @param slice The yield slice to whitelist.
    /// @param limit The mint limit, can be 0 for no limit.
    function addToWhitelist(YieldSlice slice, uint256 limit) external onlyGov {
        require(address(slice.yieldToken()) == address(yieldToken),
                "MX: incompatible yield token"); 
        address token = address(slice.npvToken());
        require(!whitelist[token].mintable, "MX: already whitelisted");

        whitelist[token].mintable = true;
        whitelist[token].redeemable = true;
        whitelist[token].limit = limit;
    }

    /// @notice Remove a yield slice from the whitelist for minting.
    /// @param token The token to remove from whitelist.
    function removeFromWhitelist(address token) external onlyGov {
        require(whitelist[token].mintable, "MX: not whitelisted");

        whitelist[token].mintable = false;
    }

    /// @notice Change the mint limit of a token.
    /// @param token The token for which we are changing the limit.
    /// @param limit The new limit.
    function modifyLimit(address token, uint256 limit) external onlyGov {
        whitelist[token].limit = limit;
    }

    /// @notice Get the remaining mint capacity for a token
    /// @param token The token for which we are checking the mint capacity.
    /// @return The remaining mint capacity.
    function remaining(address token) public view returns (uint256) {
        if (whitelist[token].limit == 0) {
            return type(uint256).max;
        } else {
            return whitelist[token].limit - whitelist[token].supply;
        }
    }

    /// @notice Preview the outcome of minting.
    /// @param tokenIn The token we are using to mint.
    /// @param amount The amount of that token we are using to mint.
    /// @return The amount of MX token minted.
    function previewMint(address tokenIn, uint256 amount) external view returns (uint256) {
        require(remaining(tokenIn) >= amount, "MX: token limit");
        return amount;
    }

    /// @notice Mint MX tokens from input NPV tokens.
    /// @param recipient Recipient of the MX tokens.
    /// @param tokenIn The token we are using to mint.
    /// @param amount The amount of that token we are using to mint.
    /// @return The amount of MX token minted.
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

    /// @notice Redeem MX tokens for NPV tokens.
    /// @param recipient Recipient of the NPV tokens.
    /// @param tokenOut The token we are redeeming for.
    /// @param amount The amount of that MX token we are redeeming.
    /// @return The amount of NPV tokens redeemed.
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
