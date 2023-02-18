// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IYieldSource.sol";
import "../interfaces/IGLPRewardTracker.sol";

contract StakedGLPYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    address public admin;
    address public owner;
    IERC20 public immutable override generatorToken;
    IERC20 public immutable override yieldToken;
    IGLPRewardTracker public immutable tracker;
    uint256 public deposits;

    constructor(address stglp_, address weth_, address tracker_) {
        require(stglp_ != address(0), "SGYS: zero address stglp");
        require(weth_ != address(0), "SGYS: zero address weth");
        require(tracker_ != address(0), "SGYS: zero address tracker");

        admin = msg.sender;
        owner = msg.sender;
        generatorToken = IERC20(stglp_);
        yieldToken = IERC20(weth_);
        tracker = IGLPRewardTracker(tracker_);
    }

    function setAdmin(address admin_) external {
        require(msg.sender == admin, "SGYS: only admin");
        require(admin_ != address(0), "SGYS: zero address");
        admin = admin_;
    }

    function setOwner(address owner_) external override {
        require(msg.sender == owner || msg.sender == admin, "SGYS: only owner/admin");
        require(owner_ != address(0), "SGYS: zero address");
        owner = owner_;
    }

    function deposit(uint256 amount, bool claim) external override {
        require(msg.sender == owner, "SGYS: only owner");
        generatorToken.safeTransferFrom(msg.sender, address(this), amount);

        if (claim) _harvest();
    }

    function withdraw(uint256 amount, bool claim, address to) external override {
        require(msg.sender == owner, "SGYS: only owner");

        uint256 balance = generatorToken.balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        generatorToken.safeTransfer(to, amount);

        if (claim) _harvest();
    }

    function _amountPending() internal view returns (uint256) {
        return tracker.claimable(address(this));
    }

    function _harvest() internal {
        tracker.claim(address(this));
    }

    function harvest() external override {
        require(msg.sender == owner, "SGYS: only owner");
        _harvest();
    }

    function amountPending() external override view returns (uint256) {
        return _amountPending();
    }

    function amountGenerator() external override view returns (uint256) {
        return generatorToken.balanceOf(address(this));
    }
}
