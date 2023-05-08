// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IGNSStaking {
    function harvest() external;
    function stakeTokens(uint amount) external;
    function unstakeTokens(uint amount) external;
    function pendingRewardDai() view external returns(uint);
}
