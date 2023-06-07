// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPirexRewards {
    function accrueAndClaim(address user) external returns (uint256);
    function getUserRewardsAccrued(address user, address rewardToken) external view returns (uint256);
    function accrueUser(address producerToken, address user) external;
    function accrueStrategy() external;
}
