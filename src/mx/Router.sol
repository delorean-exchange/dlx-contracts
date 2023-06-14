// SPDX-License-Identifier: BSL
pragma solidity ^0.8.13;

import { Multiplexer } from "./Multiplexer.sol";
import { YieldSlice } from "../core/YieldSlice.sol";
import { ILiquidityPool } from "../interfaces/ILiquidityPool.sol";

contract Router {

    struct Route {
        YieldSlice slice;           // Yield slice to use for minting origin NPV Tokens
        uint256 amountGenerator;    // Amount of generator to lock
        uint256 amountYield;        // Amount of yield to commit
        uint256 amountOutMin;       // Min yield token output
        Multiplexer[] mxs;          // Multiplexers to use for conversion, or 0 if none
        ILiquidityPool pool;        // Pool to use after conversion complete
        uint128 sqrtPriceLimitX96;  // Price limit
    }

    function routeLockForYield(YieldSlice slice,
                               Multiplexer[] memory mxs,
                               ILiquidityPool[] memory pools,
                               uint256 amountGenerator,
                               uint256 amountYield,
                               uint128 sqrtPriceLimitX96)
        public
        returns (Route memory) {


        Route memory best;
        for (uint256 i = 0; i < pools.length; i++) {
            Route memory candidate = evaluateLockForYield(slice,
                                                          mxs,
                                                          pools[i],
                                                          amountGenerator,
                                                          amountYield,
                                                          sqrtPriceLimitX96);

            if (i == 0 || candidate.amountOutMin > best.amountOutMin) {
                best = candidate;
            }
        }

        return best;
    }

    function evaluateLockForYield(YieldSlice slice,
                                  Multiplexer[] memory mxs,
                                  ILiquidityPool pool,
                                  uint256 amountGenerator,
                                  uint256 amountYield,
                                  uint128 sqrtPriceLimitX96)
        public
        returns (Route memory) {

        (uint256 npv, uint256 fees) = slice.previewDebtSlice(amountGenerator, amountYield);
        uint256 previewNPV = npv - fees;

        Multiplexer mx = Multiplexer(address(0));

        require(address(slice.yieldToken()) == pool.token0() ||
                address(slice.yieldToken()) == pool.token1(), "RMX: mismatched yield token");

        Route memory result = Route({
            slice: slice,
            amountGenerator: amountGenerator,
            amountYield: amountYield,
            amountOutMin: 0,
            mxs: new Multiplexer[](0),
            pool: ILiquidityPool(address(0)),
            sqrtPriceLimitX96: sqrtPriceLimitX96 });

        // No multiplexing applicable
        if (address(slice.npvToken()) == pool.token0() ||
            address(slice.npvToken()) == pool.token1()) {

            (uint256 amountOut, ) = pool.previewSwap(address(slice.npvToken()),
                                                     uint128(previewNPV),
                                                     sqrtPriceLimitX96);

            result.amountOutMin = amountOut;
            result.pool = pool;

            return result;
        }

        // Check for a relevant multiplexer, and use it
        for (uint256 i = 0; i < mxs.length; i++) {
            mx = mxs[i];
            if (address(mx.mxToken()) != pool.token0() &&
                address(mx.mxToken()) != pool.token1()) {

                continue;
            }

            // This multiplexer matches the pool, verify our swap is within limit
            if (mx.remaining(address(slice.npvToken())) < previewNPV) {
                continue;
            }

            // Limit allows us to swap for the MX token, so do a preveiw
            uint256 mxOut = mx.previewMint(address(slice.npvToken()), previewNPV);

            (uint256 amountOut, ) = pool.previewSwap(address(mx.mxToken()),
                                                     uint128(mxOut),
                                                     sqrtPriceLimitX96);

            result.amountOutMin = amountOut;
            result.mxs = new Multiplexer[](1);
            result.mxs[0] = mx;
            result.pool = pool;

            return result;
        }

        // No route found
        return result;
    }
}
