// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDiscounter {
    function discounted(uint256 generator, uint256 yield) external view returns (uint256);
    function pv(uint256 numDays, uint256 nominal) external view returns (uint256);
    function nominal(uint256 numDays, uint256 pv) external view returns (uint256);
}
