// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ILiquidityPool.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/uniswap/IQuoterV2.sol";
import "../interfaces/uniswap/IUniswapV3Factory.sol";
import "../interfaces/uniswap/IUniswapV3Pool.sol";

contract UniswapV3LiquidityPool is ILiquidityPool {
    using SafeERC20 for IERC20;

    /* IUniswapV3Factory public immutable factory; */
    /* address public override immutable token0; */
    /* address public override immutable token1; */
    uint24 public immutable fee;

    IUniswapV3Pool public immutable pool;
    ISwapRouter public immutable router;
    IQuoterV2 public immutable quoter;

    constructor(address pool_,
                address router_,
                address quoter_) {
        pool = IUniswapV3Pool(pool_);
        router = ISwapRouter(router_);
        quoter = IQuoterV2(quoter_);

        token0 = pool.token0();
        token1 = pool.token1();
        fee = pool.fee();
    }

    function previewSwap(address tokenIn, uint128 amountIn, uint128 amountOutMinimum)
        external override returns (uint256) {

        require(address(pool) != address(0), "ULP: no pool");

        // TODO: Use amountOutMinimum to compute sqrtPriceLimitX96

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenIn == token0 ? token1 : token0,
            amountIn: amountIn,
            fee: fee,
            sqrtPriceLimitX96: 0 });
        (uint256 amountOut, , ,) = quoter.quoteExactInputSingle(params);
        return amountOut;
    }

    function swap(address recipient,
                  address tokenIn,
                  uint128 amountIn,
                  uint128 amountOutMinimum)
        external override returns (uint256) {

        require(address(pool) != address(0), "ULP: no pool");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        // TODO: Use amountOutMinimum to compute sqrtPriceLimitX96

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenIn == token0 ? token1 : token0,
                fee: fee,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0 });

        uint256 amountOut = router.exactInputSingle(params);
        return amountOut;
    }
}
