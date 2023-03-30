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

contract AddFakeGLPLiquidity is BaseScript {
    using stdJson for string;

    /* UniswapV3LiquidityPool public pool; */
    FakeYieldSource public source;

    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);

        string memory filename = "./json/";
        if (eq(vm.envString("NETWORK"), "arbitrum")) {
            filename = "json/config.arbitrum.json";
        } else {
            filename = "json/config.localhost.json";
        }

        string memory prefix;
        if (eq(vm.envString("USE_WETH"), "1")) {
            prefix = ".fakeglp_weth_";
        } else {
            prefix = ".fakeglp_";
        }
        
        string memory config = vm.readFile(filename);
        npvSwap = NPVSwap(vm.parseJsonAddress(config, string.concat(prefix, "npvSwap.address")));

        pool = UniswapV3LiquidityPool(vm.parseJsonAddress(config, string.concat(prefix, "pool.address")));
        source = FakeYieldSource(vm.parseJsonAddress(config, string.concat(prefix, "yieldSource.address")));

        uint256 yieldTokenAmount;
        uint256 generatorTokenAmount;
        uint256 yieldToLock;

        if (eq(vm.envString("USE_WETH"), "1")) {
            if (eq(vm.envString("NETWORK"), "arbitrum")) {
                yieldTokenAmount = 1000 wei;
                generatorTokenAmount = 10e18;
                yieldToLock = 1000 wei;
            } else {
                yieldTokenAmount = 10 ether;
                generatorTokenAmount = 10e18;
                yieldToLock = 10 ether;
            }
            source.mintGenerator(deployerAddress, 10 * generatorTokenAmount);
        } else {
            source.mintBoth(deployerAddress, 10000e18);
            yieldTokenAmount = 1000e18;
            generatorTokenAmount = 1000e18;
            yieldToLock = 1000e18;
        }

        uint256 before = IUniswapV3Pool(pool.pool()).liquidity();
        console.log("Liquidity before:", before);

        addLiquidity(npvSwap, deployerAddress, yieldTokenAmount, generatorTokenAmount, yieldToLock,  -180, -60);
        addLiquidity(npvSwap, deployerAddress, yieldTokenAmount, generatorTokenAmount, yieldToLock,  -360, -60);
        addLiquidity(npvSwap, deployerAddress, yieldTokenAmount, generatorTokenAmount, yieldToLock,  -6960, -60);

        uint256 afterVal = IUniswapV3Pool(pool.pool()).liquidity();
        console.log("Liquidity after: ", afterVal);
        console.log("Delta:           ", afterVal - before);

        // Sanity check that liquidity is set up correctly, one of these should succeed
        uint256 m = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        if (address(npvSwap.npvToken()) < address(npvSwap.slice().yieldToken())) {
            npvSwap.previewSwapNPVForYield(m, 75162434512514376853788557312);
        } else {
            npvSwap.previewSwapNPVForYield(m, 83513816125015982100736638976);
        }

        vm.stopBroadcast();
    }
}
