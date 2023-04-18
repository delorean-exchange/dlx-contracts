// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { IGLPRewardTracker } from "../interfaces/IGLPRewardTracker.sol";
import { IJonesGlpVaultRouter } from "../interfaces/jones/IJonesGlpVaultRouter.sol";

/// @notice Wrapper interface for managing yield from non-compounding jGLP.
contract JonesGLPYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    IERC20 public immutable override generatorToken;
    IERC20 public immutable override yieldToken;
    uint256 public deposits;
    address public owner;

    IERC20 public constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant glp = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    IERC20 public constant jglp = IERC20(0x7241bC8035b65865156DDb5EdEf3eB32874a3AF6);
    IJonesGlpVaultRouter public constant router = IJonesGlpVaultRouter(0x2F43c6475f1ecBD051cE486A9f3Ccc4b03F3d713);

    constructor() {
        owner = msg.sender;
        generatorToken = IERC20(jglp);
        yieldToken = IERC20(weth);
    }

    function setOwner(address owner_) external override {
        require(msg.sender == owner, "only owner");
        owner = owner_;
    }

    function deposit(uint256 amount, bool claim) external override {
        require(msg.sender == owner, "only owner");
        generatorToken.safeTransferFrom(msg.sender, address(this), amount);
        router.unCompoundGlpRewards(amount, address(this));
        deposits += amount;
        if (claim) _harvest();
    }

    function withdraw(uint256 amount, bool claim, address to) external override {
        require(msg.sender == owner, "only owner");

        router.compoundGlpRewards(amount);

        uint256 balance = generatorToken.balanceOf(address(this));

        if (amount > balance) {
            amount = balance;
        }
        deposits -= amount;
        generatorToken.safeTransfer(to, amount);

        if (claim) _harvest();
    }

    function _amountPending() internal view returns (uint256) {
        return router.glpRewardTracker().claimable(address(this));
    }

    function _harvest() internal {
        router.claimRewards();
    }

    function harvest() external override {
        require(msg.sender == owner, "only owner");
        _harvest();
    }

    function amountPending() external override view returns (uint256) {
        return _amountPending();
    }

    function amountGenerator() external override view returns (uint256) {
        return deposits;
    }
}
