// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./YieldSlice.sol";
import "../tokens/NPVToken.sol";
import "../interfaces/ILiquidityPool.sol";

contract NPVSwap {
    using SafeERC20 for IERC20;

    NPVToken public immutable npvToken;
    YieldSlice public immutable slice;
    ILiquidityPool public immutable pool;

    constructor(address npvToken_, address slice_, address pool_) {
        require(npvToken_ == ILiquidityPool(pool_).token0() ||
                npvToken_ == ILiquidityPool(pool_).token1(), "NS: wrong token");

        npvToken = NPVToken(npvToken_);
        slice = YieldSlice(slice_);
        pool = ILiquidityPool(pool_);
    }


    // ---- Low level: Transacting in NPV tokens and slices ---- //
    function previewLockForNPV(uint256 tokens, uint256 yield) public returns (uint256) {
        return slice.discounter().discounted(tokens, yield);
    }

    function previewSwapYieldForNPV(uint256 yieldIn, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwap(address(slice.yieldToken()),
                                uint128(yieldIn),
                                sqrtPriceLimitX96);
    }

    function previewSwapYieldForNPVOut(uint256 npvOut, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwapOut(address(slice.yieldToken()),
                                   uint128(npvOut),
                                   sqrtPriceLimitX96);
    }

    function previewSwapNPVForYield(uint256 npvIn, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwap(address(npvToken),
                                uint128(npvIn),
                                sqrtPriceLimitX96);
    }

    function previewSwapNPVForYieldOut(uint256 yieldOut, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwapOut(address(npvToken),
                                   uint128(yieldOut),
                                   sqrtPriceLimitX96);
    }

    // Lock yield generating tokens for NPV tokens
    function lockForNPV(address recipient, uint256 tokens, uint256 yield) public returns (uint256) {
        IERC20(slice.generatorToken()).safeTransferFrom(msg.sender, address(this), tokens);
        slice.generatorToken().approve(address(slice), 0);
        slice.generatorToken().approve(address(slice), tokens);

        uint256 id = slice.debtSlice(recipient, tokens, yield);

        return id;
    }

    // Swap NPV tokens for a future yield slice
    function swapNPVForSlice(uint256 npv) public returns (uint256) {
        IERC20(slice.npvToken()).safeTransferFrom(msg.sender, address(this), npv);
        slice.npvToken().approve(address(slice), 0);
        slice.npvToken().approve(address(slice), npv);

        uint256 id = slice.creditSlice(npv, msg.sender);

        return id;
    }


    // ---- High level: Transacting in generator and yield tokens ---- //
    // Give a preview of `lockForYield`. Not a view, and should not be used
    // on-chain, due to underlying Uniswap v3 behavior.
    function previewLockForYield(uint256 tokens, uint256 yield, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        uint256 previewNPV = previewLockForNPV(tokens, yield);
        return pool.previewSwap(address(npvToken), uint128(previewNPV), sqrtPriceLimitX96);
    }

    function previewSwapForSlice(uint256 yieldIn, uint128 sqrtPriceLimitX96) public returns (uint256, uint256) {
        return pool.previewSwap(address(slice.yieldToken()), uint128(yieldIn), sqrtPriceLimitX96);
    }

    // Lock and swap yield generating tokens for yield tokens
    function lockForYield(address recipient,
                          uint256 tokens,
                          uint256 yield,
                          uint256 amountOutMin,
                          uint128 sqrtPriceLimitX96) public returns (uint256) {

        uint256 npv = previewLockForNPV(tokens, yield);
        lockForNPV(address(this), tokens, yield);
        IERC20(npvToken).approve(address(pool), npv);
        return pool.swap(recipient,
                         address(npvToken),
                         uint128(npv),
                         uint128(amountOutMin),
                         sqrtPriceLimitX96);
    }

    // Swap yield for future yield slice
    function swapForSlice(address recipient,
                          uint256 yield,
                          uint256 npvMin,
                          uint128 sqrtPriceLimitX96) public returns (uint256) {
        slice.yieldToken().safeTransferFrom(msg.sender, address(this), yield);
        slice.yieldToken().approve(address(pool), 0);
        slice.yieldToken().approve(address(pool), yield);

        uint256 out = pool.swap(address(this),
                                address(slice.yieldToken()),
                                uint128(yield),
                                uint128(npvMin),
                                sqrtPriceLimitX96);

        slice.npvToken().approve(address(slice), out);
        uint256 id = slice.creditSlice(out, recipient);

        return id;
    }
}
