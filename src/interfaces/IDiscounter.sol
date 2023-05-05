// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDiscounter {
    function DISCOUNT_PERIOD() external view returns (uint256);

    function setDaily(uint256 daily) external;
    function setMaxDays(uint256 maxDays) external;

    function discounted(uint256 generator, uint256 yield) external view returns (uint256);
    function shiftForward(uint256 numDays, uint256 npv) external view returns (uint256);
    function shiftBackward(uint256 numDays, uint256 npv) external view returns (uint256);
}
