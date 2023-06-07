// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PoolInfo {
    address lpToken;
    address GDlptoken;
    uint256 EarnRateSec;
    uint256 totalStaked;
    uint256 lastUpdate;
    uint256 vaultcap;
    uint256 glpFees;
    uint256 APR;
    bool stakable;
    bool withdrawable;
    bool rewardStart;
}

interface IGMDVault {
    function poolInfo(uint256 index) external view returns (PoolInfo memory);
    function enterETH(uint256 _pid) external payable;
    function leaveETH(uint256 share, uint256 pid) external payable;
}
