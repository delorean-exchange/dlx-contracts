// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct UserInfo {
    uint256 amount;
    int256 rewardDebt;
}

interface ILvlStaking {
    function stake(address to, uint256 amount) external;
    function unstake(address to, uint256 amount) external;
    function pendingRewards(address to) external view returns (uint256);
    function claimRewards(address to) external;
    function userInfo(address addr) external view returns (UserInfo memory);
    function STAKING_TAX_PRECISION() external view returns (uint256);
    function stakingTax() external view returns (uint256);
}
