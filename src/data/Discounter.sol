// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IDiscounter.sol";

contract Discounter is IDiscounter {
    uint256 public daily;
    uint256 public rate;
    uint256 public periodRate;
    uint256 public maxDays;
    uint256 public immutable decimals;

    uint256 public constant RATE_PRECISION = 10**6;
    uint256 public constant PERIOD = 10;

    constructor(uint256 daily_, uint256 rate_, uint256 maxDays_, uint256 decimals_) {
        daily = daily_;
        maxDays = maxDays_;
        decimals = decimals_;
        _setRate(rate_);
    }

    function _setRate(uint256 rate_) internal {
        rate = rate_;
        uint256 top = RATE_PRECISION - rate;
        for (uint256 i = 0; i < PERIOD - 1; i++) {
            top = (top * (RATE_PRECISION - rate)) / RATE_PRECISION;
        }
        periodRate = RATE_PRECISION - top;
    }

    function setRate(uint256 rate_) external {
        _setRate(rate_);
    }

    function setDaily(uint256 daily_) external {
        daily = daily_;
    }

    function setMaxDays(uint256 maxDays_) external {
        maxDays = maxDays_;
    }

    // TODO: decide if it is worth it to use periodized functions
    function unused_periodized_discounted(uint256 generator, uint256 yield) external view returns (uint256) {
        // Approximate daily discount in periods
        uint256 top = RATE_PRECISION - periodRate;
        uint256 sum = 0;
        uint256 npv = 0;
        for (uint256 i = PERIOD; i < maxDays && sum < yield; i += PERIOD) {
            uint256 nominal_ = (PERIOD * generator * daily) / (10**decimals);
            if (nominal_ + sum > yield) {
                nominal_ = yield - sum;
            }
            uint256 pv_ = (nominal_ * top) / RATE_PRECISION;
            sum += nominal_;
            npv += pv_;
            top = (top * (RATE_PRECISION - periodRate)) / RATE_PRECISION;
        }

        return npv;
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

    // TODO: decide if it is worth it to use periodized functions
    function unused_periodized_pv(uint256 numDays, uint256 yield) external view returns (uint256) {
        uint256 top = RATE_PRECISION - rate;
        uint256 i = 0;
        for (; i < (numDays - numDays % PERIOD); i += PERIOD) {
            top = (top * (RATE_PRECISION - periodRate)) / RATE_PRECISION;
        }
        for (; i < numDays; i++) {
            top = (top * (RATE_PRECISION - rate)) / RATE_PRECISION;
        }
        return (yield * top) / RATE_PRECISION;
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
