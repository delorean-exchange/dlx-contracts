// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILiquidityPool } from "../src/interfaces/ILiquidityPool.sol";
import { IUniswapV3Pool } from "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "../src/interfaces/uniswap/IUniswapV3Factory.sol";

import { FakeYieldSource } from "./helpers/FakeYieldSource.sol";

import { BaseTest } from "./BaseTest.sol";
import { NPVToken } from "../src/tokens/NPVToken.sol";
import { YieldSlice } from "../src/core/YieldSlice.sol";
import { NPVSwap } from "../src/core/NPVSwap.sol";
import { Discounter } from "../src/data/Discounter.sol";
import { YieldData } from "../src/data/YieldData.sol";
import { UniswapV3LiquidityPool } from "../src/liquidity/UniswapV3LiquidityPool.sol";
import { Multiplexer } from "../src/mx/Multiplexer.sol";
import { Router } from "../src/mx/Router.sol";

contract MultiplexerTest is BaseTest {

    FakeYieldSource public source1;
    NPVToken public npvToken1;
    NPVSwap public npvSwap1;
    YieldSlice public slice1;
    YieldData public dataDebt1;
    YieldData public dataCredit1;
    Discounter public discounter1;
    IERC20 public generatorToken1;
    IERC20 public yieldToken1;

    FakeYieldSource public source2;
    NPVToken public npvToken2;
    NPVSwap public npvSwap2;
    YieldSlice public slice2;
    YieldData public dataDebt2;
    YieldData public dataCredit2;
    Discounter public discounter2;
    IERC20 public generatorToken2;
    IERC20 public yieldToken2;

    Multiplexer public mx;
    Router public router;

    function init1() public {
        uint256 yieldPerSecond = 20000000000000;
        source1 = new FakeYieldSource(yieldPerSecond);
        generatorToken1 = source1.generatorToken();
        yieldToken1 = source1.yieldToken();
        dataDebt1 = new YieldData(10);
        dataCredit1 = new YieldData(10);

        discounter1 = new Discounter(1e13,
                                     500 * 30,
                                     360,
                                     18,
                                     30 days);

        slice1 = new YieldSlice("yFAKE1",
                               address(source1),
                               address(dataDebt1),
                               address(dataCredit1),
                               address(discounter1),
                               1e9);

        npvToken1 = slice1.npvToken();

        source1.setOwner(address(slice1));
        dataDebt1.setWriter(address(slice1));
        dataCredit1.setWriter(address(slice1));

        address unusedUniPool = createUniswapPool(address(npvToken1),
                                                  address(source1.yieldToken()));
        ILiquidityPool unusedPool = new UniswapV3LiquidityPool(unusedUniPool,
                                                               arbitrumSwapRouter,
                                                               arbitrumQuoterV2);

        npvSwap1 = new NPVSwap(address(slice1), address(unusedPool));
    }

    function init2() public {
        uint256 yieldPerSecond = 20000000000000;

        source2 = new FakeYieldSource(yieldPerSecond);
        source2.setYieldToken(address(source1.yieldToken()));

        generatorToken2 = source2.generatorToken();
        yieldToken2 = source2.yieldToken();
        dataDebt2 = new YieldData(20);
        dataCredit2 = new YieldData(20);

        discounter2 = new Discounter(1e13,
                                     500 * 30,
                                     360,
                                     18,
                                     30 days);

        slice2 = new YieldSlice("yFAKE2",
                               address(source2),
                               address(dataDebt2),
                               address(dataCredit2),
                               address(discounter2),
                               1e9);

        npvToken2 = slice2.npvToken();

        source2.setOwner(address(slice2));
        dataDebt2.setWriter(address(slice2));
        dataCredit2.setWriter(address(slice2));

        address unusedUniPool = createUniswapPool(address(npvToken2),
                                                  address(source2.yieldToken()));
        ILiquidityPool unusedPool = new UniswapV3LiquidityPool(unusedUniPool,
                                                               arbitrumSwapRouter,
                                                               arbitrumQuoterV2);

        npvSwap2 = new NPVSwap(address(slice2), address(unusedPool));
    }

    function testSetUpMultiplexer() public {
        init();
        init1();
        init2();

        // Set up multiplexer for slices 1 and 2
        mx = new Multiplexer("ymxAAA", address(slice1.yieldToken()));

        mx.addToWhitelist(slice1, 0);
        mx.addToWhitelist(slice2, 0);
    }

    function testMultiplexer() public {
        testSetUpMultiplexer();

        uint256 amountGenerator = 100e18;
        uint256 amountYield = 100e18;

        vm.startPrank(alice);

        // Lock yield to mint fFAKE2
        source1.mintBoth(alice, 100e18);
        generatorToken1.approve(address(slice1), amountGenerator);
        uint256 id1 = slice1.debtSlice(alice, alice, amountGenerator, amountYield, "");
        assertEq(npvToken1.balanceOf(alice), 326758890000000000);

        // Lock yield to mint fFAKE2
        source2.mintBoth(alice, 100e18);
        generatorToken2.approve(address(slice2), amountGenerator);
        uint256 id2 = slice2.debtSlice(alice, alice, amountGenerator, amountYield, "");
        assertEq(npvToken2.balanceOf(alice), 326758890000000000);

        // Swap it for ymxAAA
        npvToken1.approve(address(mx), 1e17);
        mx.mint(alice, address(npvToken1), 1e17);

        assertEq(npvToken1.balanceOf(alice), 226758890000000000);
        assertEq(npvToken2.balanceOf(alice), 326758890000000000);
        assertEq(mx.mxToken().balanceOf(alice), 1e17);

        // Redeem back into token 1
        mx.mxToken().approve(address(mx), 5e16);
        mx.redeem(alice, address(npvToken1), 5e16);
        assertEq(npvToken1.balanceOf(alice), 276758890000000000);
        assertEq(npvToken2.balanceOf(alice), 326758890000000000);
        assertEq(mx.mxToken().balanceOf(alice), 5e16);

        // Same thing buy npv token 2
        npvToken2.approve(address(mx), 1e17);
        mx.mint(alice, address(npvToken2), 1e17);

        assertEq(npvToken1.balanceOf(alice), 276758890000000000);
        assertEq(npvToken2.balanceOf(alice), 226758890000000000);
        assertEq(mx.mxToken().balanceOf(alice), 15e16);

        vm.stopPrank();
    }

    function createUniswapPool(address tokenA, address tokenB) public returns (address) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(arbitrumUniswapV3Factory).getPool(token0, token1, 3000));
        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(IUniswapV3Factory(arbitrumUniswapV3Factory).createPool(token0, token1, 3000));
            pool.initialize(79228162514264337593543950336);
        }

        return address(pool);
    }

    function addUniswapLiquidity(address tokenA,
                                 address tokenB,
                                 uint256 tokenAAmount,
                                 uint256 tokenBAmount,
                                 int24 tickLower,
                                 int24 tickUpper) public {

        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        (uint256 token0Amount, uint256 token1Amount) = tokenAAmount < tokenBAmount
            ? (tokenAAmount, tokenBAmount)
            : (tokenBAmount, tokenAAmount);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000,
            tickLower: tickLower,
            tickUpper: tickUpper, 
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 1 });

        console.log("approve and balance 0",
                    address(params.token0),
                    IERC20(params.token0).balanceOf(address(this)),
                    token0Amount);
        console.log("approve and balance 1",
                    address(params.token1),
                    IERC20(params.token1).balanceOf(address(this)),
                    token1Amount);

        IERC20(params.token0).approve(address(manager), token0Amount);
        IERC20(params.token1).approve(address(manager), token1Amount);

        manager.mint(params);
    }

    function testRouter() public {
        testSetUpMultiplexer();

        console.log("testRouter");
        router = new Router();

        // Set up two liquidity pools: one for npvToken1, and
        // another for mxToken, which is the multiplexed token
        uint256 amountGenerator = 100e18;
        uint256 amountYield = 100e18;

        vm.startPrank(alice);
        source1.mintBoth(alice, 100e18);

        console.log("alice GT ->", generatorToken1.balanceOf(alice));

        generatorToken1.approve(address(slice1), amountGenerator);
        uint256 id1 = slice1.debtSlice(alice, alice, amountGenerator, amountYield, "");
        assertEq(npvToken1.balanceOf(alice), 326758890000000000);
        npvToken1.approve(address(mx), 1e17);
        mx.mint(alice, address(npvToken1), 1e17);

        npvToken1.transfer(address(this), 2e17);
        mx.mxToken().transfer(address(this), 1e17);
        vm.stopPrank();

        source1.mintBoth(address(this), 100e18);

        assertEq(npvToken1.balanceOf(address(this)), 2e17);
        assertEq(mx.mxToken().balanceOf(address(this)), 1e17);
        assertTrue(source1.yieldToken().balanceOf(address(this)) > 10e18);

        // Create the Uniswap pools
        address uniPool1 = createUniswapPool(address(npvToken1), address(source1.yieldToken()));
        address uniPool2 = createUniswapPool(address(mx.mxToken()), address(source1.yieldToken()));

        addUniswapLiquidity(address(npvToken1),
                            address(source1.yieldToken()),
                            1e16,
                            1e16,
                            -600000,
                            600000);

        addUniswapLiquidity(address(mx.mxToken()),
                            address(source1.yieldToken()),
                            1e16,
                            1e16,
                            -120,
                            120);

        // Deploy the wrappers
        ILiquidityPool pool1 = new UniswapV3LiquidityPool(uniPool1,
                                                          arbitrumSwapRouter,
                                                          arbitrumQuoterV2);
        ILiquidityPool pool2 = new UniswapV3LiquidityPool(uniPool2,
                                                          arbitrumSwapRouter,
                                                          arbitrumQuoterV2);

        console.log("wrapper 1", address(pool1));
        console.log("slice1 yield token: ", address(slice1.yieldToken()));
        console.log("source1 yield token:", address(source1.yieldToken()));
        console.log("pool1 token0:       ", address(pool1.token0()));
        console.log("pool1 token1:       ", address(pool1.token1()));
        console.log("");
        console.log("--");
        console.log("wrapper 2", address(pool2));

        Multiplexer[] memory mxs = new Multiplexer[](1);
        mxs[0] = mx;
        ILiquidityPool[] memory pools = new ILiquidityPool[](2);
        pools[0] = pool1;
        pools[1] = pool2;

        console.log("run router");

        Router.Route memory route;
        route = router.routeLockForYield(slice1,
                                         mxs,
                                         pools,
                                         2e18,
                                         1e18,
                                         0);

        console.log("Got route with:", route.amountOutMin, address(route.pool));

        assertEq(address(route.slice), address(slice1));
        assertEq(route.amountGenerator, 2e18);
        assertEq(route.amountYield, 1e18);
        assertEq(route.amountOutMin, 6490276773308067);
        assertEq(route.mxs.length, 1);
        assertEq(address(route.mxs[0]), address(mx));
        assertEq(address(route.pool), address(pool2));

        {
            vm.startPrank(alice);
            source1.mintBoth(alice, 100e18);
            generatorToken1.approve(address(npvSwap1), route.amountGenerator);
            uint256 before = yieldToken1.balanceOf(alice);
            uint256 preview = npvSwap1.previewRouteLockForYield(route);
            npvSwap1.executeRouteLockForYield(alice, route, new bytes(0));
            uint256 delta = yieldToken1.balanceOf(alice) - before;
            assertEq(preview, 6490276773308067);
            assertEq(delta, 6490276773308067);
            vm.stopPrank();
        }

        // The 2nd route should use the other pool
        Router.Route memory route2;
        route2 = router.routeLockForYield(slice1,
                                          mxs,
                                          pools,
                                          2e18,
                                          1e18,
                                          0);

        assertEq(address(route2.slice), address(slice1));
        assertEq(route2.amountGenerator, 2e18);
        assertEq(route2.amountYield, 1e18);
        assertEq(route2.amountOutMin, 3945108387056561);
        assertEq(route2.mxs.length, 0);
        assertEq(address(route2.pool), address(pool1));

        {
            vm.startPrank(alice);
            generatorToken1.approve(address(npvSwap1), route2.amountGenerator);
            uint256 before = yieldToken1.balanceOf(alice);
            uint256 preview = npvSwap1.previewRouteLockForYield(route2);
            npvSwap1.executeRouteLockForYield(alice, route2, new bytes(0));
            uint256 delta = yieldToken1.balanceOf(alice) - before;
            assertEq(preview, 3945108387056561);
            assertEq(delta, 3945108387056561);
            vm.stopPrank();
        }
    }
}
