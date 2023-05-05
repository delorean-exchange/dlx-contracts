// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IDiscounter } from "../interfaces/IDiscounter.sol";

/// @notice Computes net present value of future yield based on a fixed discount rate.
contract Discounter is IDiscounter, Ownable {
    uint256 public daily;
    uint256 public immutable rate;
    uint256 public maxDays;
    uint256 public immutable decimals;

    uint256 public constant DISCOUNT_PERIOD = 1 days;
    uint256 public constant RATE_PRECISION = 10**6;
    uint256 public constant PERIOD = 10;

    event Daily(uint256 daily);
    event MaxDays(uint256 maxDays);

    /// @notice Create a Discounter
    /// @param daily_ Projected daily yield rate per token.
    /// @param rate_ Daily discount rate, as fraction of `RATE_PRECISION`.
    /// @param decimals_ Decimals for the daily yield rate projection.
    constructor(uint256 daily_, uint256 rate_, uint256 maxDays_, uint256 decimals_) {
        daily = daily_;
        maxDays = maxDays_;
        decimals = decimals_;
        rate = rate_;
    }

    /// @notice Set the projected daily yield rate.
    /// @param daily_ New projected daily yield rate.
    function setDaily(uint256 daily_) external onlyOwner {
        daily = daily_;

        emit Daily(daily);
    }

    /// @notice Set the max days of projected future yield to sell.
    /// @param maxDays_ New max days of projected future yield to sell.
    function setMaxDays(uint256 maxDays_) external onlyOwner {
        maxDays = maxDays_;

        emit MaxDays(maxDays);
    }

    /// @notice Compute the net present value of stream of future yield.
    /// @param generator Amount of yield generating tokens.
    /// @param yield Amount of future yield to be locked.
    function discounted(uint256 generator, uint256 yield) external override view returns (uint256) {
        uint256 top = RATE_PRECISION - rate;
        uint256 sum = 0;
        uint256 npv = 0;
        for (uint256 i = 1; i < maxDays && sum < yield; i++) {

            uint256 nominal_ = (generator * daily) / (10**decimals);
            uint256 pv_ = (nominal_ * top) / RATE_PRECISION;
            sum += nominal_;
            npv += pv_;
            top = (top * (RATE_PRECISION - rate)) / RATE_PRECISION;
        }
        return npv;
    }


    /// @notice Compute value of nominal payment shifted forward some days, relative to a starting amount of NPV.
    /// @param numDays Number of days in the future to delay that nominal payment.
    /// @param npv Starting NPV of the nominal payment we will receive.
    /// @return NPV of that nominal payment after the delay.
    function shiftForward(uint256 numDays, uint256 npv) external override view returns (uint256) {
        uint256 acc = npv * 1e9;
        for (uint256 i = 0; i < numDays; i++) {
            acc = acc * RATE_PRECISION / (RATE_PRECISION - rate);
        }
        return acc / 1e9;
    }

    /// @notice Compute value of nominal payment shifted backward some days, relative to a starting amount of NPV.
    /// @param numDays Number of days in the future to delay that nominal payment.
    /// @param npv Starting NPV of the nominal payment we will receive.
    /// @return NPV of that nominal payment after the delay.
    function shiftBackward(uint256 numDays, uint256 npv) external override view returns (uint256) {
        uint256 acc = npv * 1e9;
        for (uint256 i = 0; i < numDays; i++) {
            acc = acc * (RATE_PRECISION - rate) / RATE_PRECISION;
        }
        return acc / 1e9;
    }
}
