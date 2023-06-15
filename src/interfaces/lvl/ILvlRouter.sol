// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILvlRouter {
    function removeLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _to) external;
}
