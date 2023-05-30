// SPDX-License-Identifier: BSL
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { NPVToken } from "../tokens/NPVToken.sol";

contract Multiplexer {
    using SafeERC20 for IERC20;

    NPVToken public mxToken;

    struct TokenConfig {
        IERC20 token;
        uint256 limit;
    }
    mapping(address => TokenConfig) public whitelist;

    uint256 public lockedUntil;
    uint256 public unlockDelay;

    address public gov;

    modifier onlyGov() {
        require(msg.sender == gov, "MX: only gov");
        _;
    }

    modifier onlyUnlocked() {
        require(block.timestamp >= lockedUntil, "MX: locked");
        _;
    }

    constructor(string memory symbol, uint256 unlockDelay_) {
        gov = msg.sender;

        mxToken = new NPVToken(symbol, symbol);
        unlockDelay = unlockDelay_;
        lockedUntil = block.timestamp;
    }

    function addToWhitelist(address token, uint256 limit)
        external
        onlyGov
        onlyUnlocked {

        console.log("Add to whitelist");
    }

    function removeFromWhitelist(address token, uint256 limit)
        external
        onlyGov
        onlyUnlocked {
    }

    function modifyLimit(address token, uint256 limit) external onlyGov {
    }

    function setLocked(bool locked_) external onlyGov {
    }

    function mint(address tokenIn, uint256 amount) external returns (uint256) {
        return 0;
    }

    function redeem(address tokenOut, uint256 amount) external returns (uint256) {
        return 0;
    }
}
