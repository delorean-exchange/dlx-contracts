// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

abstract contract ILiquidityPool {
    address public token0;
    address public token1;

    // Not marked `view` to allow calls to Uniswap Quoter.
    // Gas inefficient, do not call on-chain.
    function previewSwap(address tokenIn, uint128 amountIn, uint128 amountOutMinimum) virtual external returns (uint256);

    function swap(address recipient,
                  address tokenIn,
                  uint128 amountIn,
                  uint128 amountOutMinimum)
        virtual external returns (uint256);
}
