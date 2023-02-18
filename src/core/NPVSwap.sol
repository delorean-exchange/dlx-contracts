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


    // ---- Transacting in NPV tokens and slices ---- //
    function previewSwapForNPV(uint256 tokens, uint256 yield) public returns (uint256) {
        return slice.discounter().discounted(tokens, yield);
    }

    // Lock and swap yield generating tokens for NPV tokens
    function swapForNPV(address recipient, uint256 tokens, uint256 yield) public returns (uint256) {
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


    // ---- Transacting in generator and yield tokens ---- //
    // Give a preview of `swapForYield`
    function previewSwapForYield(uint256 tokens, uint256 yield) public returns (uint256) {
        uint256 previewNPV = previewSwapForNPV(tokens, yield);
        return pool.previewSwap(address(npvToken), uint128(previewNPV), 0);
    }

    // Lock and swap yield generating tokens for yield tokens
    function swapForYield(address recipient, uint256 tokens, uint256 yield, uint256 amountOutMin) public returns (uint256) {
        uint256 npv = previewSwapForNPV(tokens, yield);
        swapForNPV(address(this), tokens, yield);
        IERC20(npvToken).approve(address(pool), npv);
        return pool.swap(recipient,
                         address(npvToken),
                         uint128(npv),
                         uint128(amountOutMin));
    }

    function previewSwapForSlice(uint256 yield) public returns (uint256) {
        return pool.previewSwap(address(slice.yieldToken()), uint128(yield), 0);
    }

    // Swap yield for future yield slice
    function swapForSlice(address recipient, uint256 yield, uint256 npvMin) public returns (uint256) {
        slice.yieldToken().safeTransferFrom(msg.sender, address(this), yield);
        slice.yieldToken().approve(address(pool), 0);
        slice.yieldToken().approve(address(pool), yield);

        uint256 out = pool.swap(address(this),
                                address(slice.yieldToken()),
                                uint128(yield),
                                uint128(npvMin));

        slice.npvToken().approve(address(slice), out);
        uint256 id = slice.creditSlice(out, recipient);

        return id;
    }
}
