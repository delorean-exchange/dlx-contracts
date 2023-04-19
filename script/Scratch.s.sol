// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./BaseScript.sol";

import { FakeYieldSource } from "../test/helpers/FakeYieldSource.sol";
import { UniswapV3LiquidityPool } from "../src/liquidity/UniswapV3LiquidityPool.sol";
import { IUniswapV3Factory } from "../src/interfaces/uniswap/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import { NPVSwap } from "../src/core/NPVSwap.sol";
import { YieldSlice } from "../src/core/YieldSlice.sol";
import { ISwapRouter } from  "../src/interfaces/uniswap/ISwapRouter.sol";

contract Scratch is BaseScript {
    using stdJson for string;

    function run() public {
        console.log("Scratch");
        ISwapRouter router = ISwapRouter(0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2);

        IUniswapV3Factory factory = IUniswapV3Factory(bscUniswapV3Factory);
        IUniswapV3Pool uniswapV3Pool = IUniswapV3Pool(factory.getPool(0xA447FD3Bb893F32D2C38a1F38C60BA5294DDC137,
                                                                      0xB3829ce1AAFbef4d95c7A68EfBC0879F58cFd4A2,
                                                                      3000));

        string memory filename = "./json/config.localhost.json";
        string memory config = vm.readFile(filename);
        FakeYieldSource source = FakeYieldSource(vm.parseJsonAddress(config, ".fakeglp_yieldSource.address"));
        YieldSlice slice = YieldSlice(vm.parseJsonAddress(config, ".fakeglp_slice.address"));
        NPVSwap npvSwap = NPVSwap(vm.parseJsonAddress(config, ".fakeglp_npvSwap.address"));

        source.mintBoth(address(this), 1000e18);
        source.generatorToken().approve(address(npvSwap), 10e18);
        npvSwap.lockForNPV(address(this), address(this), 10e18, 1e18, new bytes(0));

        IERC20 ti = IERC20(0xA447FD3Bb893F32D2C38a1F38C60BA5294DDC137);
        console.log("bal 1", ti.balanceOf(address(this)));
        console.log("bal 2", source.generatorToken().balanceOf(address(this)));
        console.log("slice ", address(slice));
        console.log("source", address(source));
        console.log("source gt", address(source.generatorToken()));
        console.log("source yt", address(source.yieldToken()));
        console.log("slice npv", address(slice.npvToken()));

        console.log("uniswapV3Pool", uniswapV3Pool.liquidity());

        uint256 amount = 1000;
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: 0xA447FD3Bb893F32D2C38a1F38C60BA5294DDC137,
                tokenOut: 0xB3829ce1AAFbef4d95c7A68EfBC0879F58cFd4A2,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp + 100000000000000,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0 });

        console.log("Made params");
        IERC20(0xA447FD3Bb893F32D2C38a1F38C60BA5294DDC137).approve(address(router), amount);
        uint256 amountOut = router.exactInputSingle(params);
        console.log("Swap done");
        
    }

}
