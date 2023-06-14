// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { IGNSStaking } from "../interfaces/gns/IGNSStaking.sol";

/// @notice Wrapper interface for managing yield from GNS.
contract GNSYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    IERC20 public immutable override generatorToken;
    IERC20 public immutable override yieldToken;
    IGNSStaking public immutable staking;
    uint256 public deposits;
    address public owner;

    /// @notice Create a GNSYieldSource.
    constructor(address gns_, address dai_, address staking_) {
        require(gns_ != address(0), "GYS: zero address gns");
        require(dai_ != address(0), "GYS: zero address dai");
        require(staking_ != address(0), "GYS: zero address staking");

        owner = msg.sender;
        generatorToken = IERC20(gns_);
        yieldToken = IERC20(dai_);
        staking = IGNSStaking(staking_);
    }

    /// @notice Set a new owner.
    /// @param owner_ The new owner.
    function setOwner(address owner_) external override {
        require(msg.sender == owner, "only owner");
        owner = owner_;
    }

    /// @notice Deposit GNS.
    /// @param amount Amount of GNS to deposit.
    /// @param claim If true, harvest yield.
    function deposit(uint256 amount, bool claim) external override {
        require(msg.sender == owner, "only owner");

        generatorToken.safeTransferFrom(msg.sender, address(this), amount);
        generatorToken.safeApprove(address(staking), amount);
        staking.stakeTokens(amount);
        deposits += amount;

        if (claim) _harvest();
    }

    /// @notice Withdraw GNS.
    /// @param amount Amount of GNS to withdraw.
    /// @param claim If true, harvest yield.
    /// @param to Recipient of the withdrawal.
    function withdraw(uint256 amount, bool claim, address to) external override {
        require(msg.sender == owner, "only owner");

        staking.unstakeTokens(amount);
        generatorToken.safeTransfer(to, amount);
        deposits -= amount;

        if (claim) _harvest();
    }

    function _amountPending() internal view returns (uint256) {
        return staking.pendingRewardDai();
    }

    function _harvest() internal {
        uint256 before = yieldToken.balanceOf(address(this));
        staking.harvest();
        uint256 amount = yieldToken.balanceOf(address(this)) - before;
        yieldToken.safeTransfer(owner, amount);
    }

    function harvest() external override {
        require(msg.sender == owner, "only owner");
        _harvest();
    }

    /// @notice Amount of Dai yield pending that will be harvestable.
    /// @return Amount of Dai yield pending that will be harvestable.
    function amountPending() external override view returns (uint256) {
        return _amountPending();
    }

    /// @notice Amount of GNS locked.
    /// @return Amount of GNS locked.
    function amountGenerator() external override view returns (uint256) {
        return deposits;
    }
}
