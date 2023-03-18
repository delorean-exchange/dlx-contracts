// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IDiscounter } from "../interfaces/IDiscounter.sol";

contract Discounter is IDiscounter, Ownable {
    uint256 public daily;
    uint256 public rate;
    uint256 public maxDays;
    uint256 public immutable decimals;

    uint256 public constant RATE_PRECISION = 10**6;
    uint256 public constant PERIOD = 10;

    constructor(uint256 daily_, uint256 rate_, uint256 maxDays_, uint256 decimals_) {
        daily = daily_;
        maxDays = maxDays_;
        decimals = decimals_;
        rate = rate_;
    }

    function setRate(uint256 rate_) external onlyOwner {
        rate = rate_;
    }

    function setDaily(uint256 daily_) external onlyOwner {
        daily = daily_;
    }

    function setMaxDays(uint256 maxDays_) external onlyOwner {
        maxDays = maxDays_;
    }

    function discounted(uint256 generator, uint256 yield) external override view returns (uint256) {
        uint256 top = RATE_PRECISION - rate;
        uint256 sum = 0;
        uint256 npv = 0;
        for (uint256 i = 1; i < maxDays && sum < yield; i++) {

            uint256 nominal_ = (generator * daily) / (10**decimals);
            if (nominal_ + sum > yield) {
                nominal_ = yield - sum;
            }
            uint256 pv_ = (nominal_ * top) / RATE_PRECISION;
            sum += nominal_;
            npv += pv_;
            top = (top * (RATE_PRECISION - rate)) / RATE_PRECISION;
        }
        return npv;
    }

    function pv(uint256 numDays, uint256 nominal_) external override view returns (uint256) {
        uint256 acc = nominal_;
        for (uint256 i = 0; i < numDays; i++) {
            acc = acc * (RATE_PRECISION - rate) / RATE_PRECISION;
        }
        return acc;
    }

    function nominal(uint256 numDays, uint256 pv_) external override view returns (uint256) {
        uint256 acc = pv_;
        for (uint256 i = 0; i < numDays; i++) {
            acc = acc * RATE_PRECISION / (RATE_PRECISION - rate);
        }
        return acc;
    }
}
