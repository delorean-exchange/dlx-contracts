// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

    FakeYieldSource public source3;
    NPVToken public npvToken3;
    NPVSwap public npvSwap3;
    YieldSlice public slice3;
    YieldData public dataDebt3;
    YieldData public dataCredit3;
    Discounter public discounter3;
    IERC20 public generatorToken3;
    IERC20 public yieldToken3;

    Multiplexer public mx;
    Multiplexer public mx2;
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

    function init3() public {
        uint256 yieldPerSecond = 20000000000000;

        source3 = new FakeYieldSource(yieldPerSecond);

        generatorToken3 = source3.generatorToken();
        yieldToken3 = source3.yieldToken();
        dataDebt3 = new YieldData(20);
        dataCredit3 = new YieldData(20);

        discounter3 = new Discounter(1e13,
                                     500 * 30,
                                     360,
                                     18,
                                     30 days);

        slice3 = new YieldSlice("yFAKE3",
                               address(source3),
                               address(dataDebt3),
                               address(dataCredit3),
                               address(discounter3),
                               1e9);

        npvToken3 = slice3.npvToken();

        source3.setOwner(address(slice3));
        dataDebt3.setWriter(address(slice3));
        dataCredit3.setWriter(address(slice3));
    }

    function testSetUpMultiplexer() public {
        init();
        init1();
        init2();
        init3();

        // Set up multiplexer for slices 1 and 2
        mx = new Multiplexer("ymxAAA", address(slice1.yieldToken()));

        mx.addToWhitelist(slice1, 0);
        mx.addToWhitelist(slice2, 0);

        mx2 = new Multiplexer("ymxBBB", address(slice3.yieldToken()));

        (bool mintable,
         bool redeemable,
         uint256 limit,
         uint256 supply) = mx.whitelist(address(slice1.npvToken()));
        assertTrue(mintable);
        assertTrue(redeemable);
        assertEq(limit, 0);
        assertEq(supply, 0);
    }

    function testRemoveFromWhitelist() public {
        testSetUpMultiplexer();
        mx.removeFromWhitelist(address(slice1.npvToken()));
        (bool mintable,
         bool redeemable,
         uint256 limit,
         uint256 supply) = mx.whitelist(address(slice1.npvToken()));
        assertFalse(mintable);
        assertTrue(redeemable);
        assertEq(limit, 0);
        assertEq(supply, 0);

        vm.expectRevert("MX: not whitelisted");
        mx.removeFromWhitelist(address(npvToken1));

        vm.expectRevert("MX: not mintable");
        mx.mint(address(this), address(npvToken1), 1000);

        assertEq(mx.remaining(address(npvToken1)), 0);
        assertEq(mx.previewMint(address(npvToken1), 100), 0);
    }

    function testInvalidYieldToken() public {
        testSetUpMultiplexer();

        vm.expectRevert("MX: incompatible yield token");
        mx.addToWhitelist(slice3, 0);

        vm.expectRevert("MX: not mintable");
        mx.mint(address(this), address(npvToken3), 1000);
    }

    function testInvalidRedeem() public {
        testSetUpMultiplexer();

        vm.expectRevert("MX: not redeemable");
        mx.redeem(address(this), address(npvToken3), 1000);
    }

    function testDoubleAdd() public {
        testSetUpMultiplexer();

        vm.expectRevert("MX: already whitelisted");
        mx.addToWhitelist(slice1, 0);
    }

    function testLimit() public {
        testSetUpMultiplexer();

        ( , , uint256 limit1, ) = mx.whitelist(address(slice1.npvToken()));
        assertEq(limit1, 0);
        assertEq(mx.remaining(address(slice1.npvToken())), type(uint256).max);

        mx.modifyLimit(address(slice1.npvToken()), 1e9);
        ( , , uint256 limit2, ) = mx.whitelist(address(slice1.npvToken()));
        assertEq(limit2, 1e9);
        assertEq(mx.remaining(address(slice1.npvToken())), 1e9);

        source1.mintBoth(address(this), 100e18);
        generatorToken1.approve(address(slice1), 1e18);
        slice1.debtSlice(address(this), address(this), 1e18, 1e18, "");

        slice1.npvToken().approve(address(mx), 4e8);
        mx.mint(address(this), address(slice1.npvToken()), 4e8);
        ( , , uint256 limit3, ) = mx.whitelist(address(slice1.npvToken()));
        assertEq(limit3, 1e9);
        assertEq(mx.remaining(address(slice1.npvToken())), 6e8);

        slice1.npvToken().approve(address(mx), 1e9);
        vm.expectRevert("MX: token limit");
        mx.mint(address(this), address(npvToken1), 1e9);
    }

    function testMultiplexer() public {
        testSetUpMultiplexer();

        uint256 amountGenerator = 100e18;
        uint256 amountYield = 100e18;

        vm.startPrank(alice);

        // Lock yield to mint fFAKE2
        source1.mintBoth(alice, 100e18);
        generatorToken1.approve(address(slice1), amountGenerator);
        slice1.debtSlice(alice, alice, amountGenerator, amountYield, "");
        assertEq(npvToken1.balanceOf(alice), 326758890000000000);

        // Lock yield to mint fFAKE2
        source2.mintBoth(alice, 100e18);
        generatorToken2.approve(address(slice2), amountGenerator);
        slice2.debtSlice(alice, alice, amountGenerator, amountYield, "");
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

        // Test invalid redemption
        vm.expectRevert("MX: insufficient supply");
        mx.redeem(alice, address(npvToken1), 1e17);

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

        IERC20(params.token0).approve(address(manager), token0Amount);
        IERC20(params.token1).approve(address(manager), token1Amount);

        manager.mint(params);
    }

    function testRouter() public {
        testSetUpMultiplexer();

        router = new Router();

        // Set up two liquidity pools: one for npvToken1, and
        // another for mxToken, which is the multiplexed token
        uint256 amountGenerator = 100e18;
        uint256 amountYield = 100e18;

        vm.startPrank(alice);
        source1.mintBoth(alice, 100e18);

        generatorToken1.approve(address(slice1), amountGenerator);
        slice1.debtSlice(alice, alice, amountGenerator, amountYield, "");
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

        Multiplexer[] memory mxs = new Multiplexer[](2);
        mxs[0] = mx;
        mxs[1] = mx2;
        ILiquidityPool[] memory pools = new ILiquidityPool[](2);
        pools[0] = pool1;
        pools[1] = pool2;

        // Try it with invalid tokens
        vm.expectRevert("RMX: mismatched yield token");
        router.routeLockForYield(slice3,
                                 mxs,
                                 pools,
                                 2e18,
                                 1e18,
                                 0);

        Router.Route memory route;
        // Set limit go small number, and verify route does not use MX
        mx.modifyLimit(address(slice1.npvToken()), 100);
        route = router.routeLockForYield(slice1,
                                         mxs,
                                         pools,
                                         2e18,
                                         1e18,
                                         0);
        assertEq(route.mxs.length, 0);
        mx.modifyLimit(address(slice1.npvToken()), 1e30);

        // Get the route for valid query, with usable limit
        route = router.routeLockForYield(slice1,
                                         mxs,
                                         pools,
                                         2e18,
                                         1e18,
                                         0);

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

    function testRouterInvalidToken() public {
        testSetUpMultiplexer();

        router = new Router();
    }
}
