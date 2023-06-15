// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILvlPool {
    function calcRemoveLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount) external view
        returns (uint256 outAmount, uint256 outAmountAfterFee, uint256 feeAmount);
}
