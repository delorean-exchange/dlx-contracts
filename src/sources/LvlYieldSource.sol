// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { ILvlStaking } from "../interfaces/level/ILvlStaking.sol";

/// @notice Wrapper interface for managing yield from Level.finance LVL token.
contract LvlYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    address public owner;

    IERC20 public immutable override generatorToken;
    IERC20 public immutable override yieldToken;

    IERC20 public immutable lvl;
    IERC20 public immutable llp;
    IERC20 public immutable weth;

    ILvlStaking public immutable lvlStaking;
    
    constructor(address lvlStaking_) {
        lvlStaking = ILvlStaking(lvlStaking_);
        lvl = IERC20(lvlStaking.LVL());
        llp = IERC20(lvlStaking.LLP());
        weth = IERC20(lvlStaking.WETH());

        generatorToken = lvl;
        yieldToken = llp;

        owner = msg.sender;
    }

    function setOwner(address owner_) external override {
        require(msg.sender == owner, "only owner");
        owner = owner_;
    }

    function deposit(uint256 amount, bool claim) external override {
        require(msg.sender == owner, "only owner");
        generatorToken.safeTransferFrom(msg.sender, address(this), amount);
        generatorToken.safeApprove(address(lvlStaking), amount);
        lvlStaking.stake(address(this), amount);
        if (claim) _harvest();
    }

    function withdraw(uint256 amount, bool claim, address to) external override {
        require(msg.sender == owner, "only owner");
        uint256 amount_ = _amountGenerator();
        if (amount_ < amount) amount = amount_;
        lvlStaking.unstake(to, amount);
        if (claim) _harvest();
    }

    function _amountGenerator() internal view returns (uint256) {
        (uint256 amount_, ) = lvlStaking.userInfo(address(this));
        return amount_;
    }

    function _amountPending() internal view returns (uint256) {
        return lvlStaking.pendingRewards(address(this));
    }

    function _harvest() internal {
        uint256 before = yieldToken.balanceOf(address(this));
        lvlStaking.claimRewards(address(this));
        uint256 amount = yieldToken.balanceOf(address(this)) - before;
        yieldToken.safeTransfer(owner, amount);
    }

    function harvest() external override {
        require(msg.sender == owner, "only owner");
        _harvest();
    }

    function amountPending() external override view returns (uint256) {
        return _amountPending();
    }

    function amountGenerator() external override view returns (uint256) {
        return _amountGenerator();
    }
}
