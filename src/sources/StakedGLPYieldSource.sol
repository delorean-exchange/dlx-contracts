// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { IGLPRewardTracker } from "../interfaces/IGLPRewardTracker.sol";

/// @notice Wrapper interface for managing yield from sGLP.
contract StakedGLPYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    IERC20 public immutable override generatorToken;
    IERC20 public immutable override yieldToken;
    IGLPRewardTracker public immutable tracker;
    uint256 public deposits;
    address public owner;

    /// @notice Create a StakedGLPYieldSource.
    /// @param stglp_ Address of sGLP.
    /// @param weth_ Address fo WETH.
    /// @param tracker_ Address of the GLP rewards tracker.
    constructor(address stglp_, address weth_, address tracker_) {
        require(stglp_ != address(0), "SGYS: zero address stglp");
        require(weth_ != address(0), "SGYS: zero address weth");
        require(tracker_ != address(0), "SGYS: zero address tracker");

        owner = msg.sender;
        generatorToken = IERC20(stglp_);
        yieldToken = IERC20(weth_);
        tracker = IGLPRewardTracker(tracker_);
    }

    /// @notice Set a new owner.
    /// @param owner_ The new owner.
    function setOwner(address owner_) external override {
        require(msg.sender == owner, "only owner");
        owner = owner_;
    }

    /// @notice Deposit sGLP.
    /// @param amount Amount of sGLP to deposit.
    /// @param claim If true, harvest yield.
    function deposit(uint256 amount, bool claim) external override {
        require(msg.sender == owner, "only owner");
        generatorToken.safeTransferFrom(msg.sender, address(this), amount);

        if (claim) _harvest();
    }

    /// @notice Withdraw sGLP.
    /// @param amount Amount of sGLP to withdraw.
    /// @param claim If true, harvest yield.
    /// @param to Recipient of the withdrawal.
    function withdraw(uint256 amount, bool claim, address to) external override {
        require(msg.sender == owner, "only owner");

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
        uint256 before = yieldToken.balanceOf(address(this));
        tracker.claim(address(this));
        uint256 amount = yieldToken.balanceOf(address(this)) - before;
        yieldToken.safeTransfer(owner, amount);
    }

    function harvest() external override {
        require(msg.sender == owner, "only owner");
        _harvest();
    }

    /// @notice Amount of WETH yield pending that will be harvestable.
    /// @return Amount of WETH yield pending that will be harvestable.
    function amountPending() external override view returns (uint256) {
        return _amountPending();
    }

    /// @notice Amount of sGLP locked.
    /// @return Amount of sGLP locked.
    function amountGenerator() external override view returns (uint256) {
        return generatorToken.balanceOf(address(this));
    }
}
