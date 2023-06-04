// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPirexRewards {
    function accrueAndClaim(address user) external returns (uint256);
}
