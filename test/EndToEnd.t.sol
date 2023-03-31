// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./BaseTest.sol";
import "../src/core/NPVSwap.sol";
import "../src/liquidity/UniswapV3LiquidityPool.sol";
import "../src/interfaces/uniswap/ISwapRouter.sol";
import "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import "../src/interfaces/uniswap/INonfungiblePositionManager.sol";

import "../src/interfaces/uniswap/IQuoterV2.sol";

contract EndToEndTest is BaseTest {

    function setUp() public {
        init();
    }

    function testAliceAddLiquidity() public {
        // Alice: Get some NPV tokens so we can add liquidity
        vm.startPrank(alice);
        generatorToken.approve(address(npvSwap), 2000e18);
        npvSwap.lockForNPV(alice, alice, 2000e18, 10e18, new bytes(0));

        uint256 token0Amount = 1e18;
        uint256 token1Amount = 1e18;
        source.mintGenerator(alice, 1e18);
        source.mintYield(alice, 1e18);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: uniswapV3Pool.token0(),
            token1: uniswapV3Pool.token1(),
            fee: 3000,
            tickLower: -1800,
            tickUpper: 2220,
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: alice,
            deadline: block.timestamp + 1 });

        assertEq(uniswapV3Pool.liquidity(), 0);
        IERC20(params.token0).approve(address(manager), token0Amount);
        IERC20(params.token1).approve(address(manager), token1Amount);
        manager.mint(params);
        assertEq(uniswapV3Pool.liquidity(), 9518707090837465627);
        vm.stopPrank();
    }

    function testSwapWithUniswapLiquidityPool() public {
        testAliceAddLiquidity();

        // Bob: Lock some future yield, and swap it for ETH
        vm.startPrank(bob);

        source.mintGenerator(bob, 1000000e18);
        generatorToken.approve(address(npvSwap), 200e18);
        assertEq(npvSwap.previewLockForNPV(200e18, 1e18), 657008058000000000);
        npvSwap.lockForNPV(bob, bob, 200e18, 1e18, new bytes(0));
        assertEq(IERC20(npvToken).balanceOf(bob), 657008058000000000);

        IERC20(npvToken).approve(address(pool), 5e17);
        uint256 before = IERC20(yieldToken).balanceOf(bob);
        uint256 out = pool.swap(bob, address(npvToken), 5e17, 0, 0);
        uint256 delta = IERC20(yieldToken).balanceOf(bob) - before;
        assertClose(delta, 5e17, 1e17);
        assertEq(out, 473692461556744701);
        assertEq(delta, 473692461556744701);

        vm.stopPrank();

        // Chad: Use ETH to buy future yield
        vm.startPrank(chad);

        source.mintYield(chad, 1000000e18);
        IERC20(yieldToken).approve(address(pool), 1e18);
        uint256 out2 = pool.swap(chad, address(yieldToken), 1e18, 0, 0);
        uint256 balance2 = IERC20(npvToken).balanceOf(chad);
        assertClose(balance2, 1e18, 5e17);
        assertEq(out2, 994537036467183765);
        assertEq(balance2, 994537036467183765);

        IERC20(npvToken).approve(address(npvSwap), 99e16);
        uint256 id = npvSwap.swapNPVForSlice(chad, 99e16, new bytes(0));
        (, , uint256 claimable1) = slice.generatedCredit(id);
        assertEq(claimable1, 0);

        vm.warp(block.timestamp + 0x1000);
        (uint256 nominal2, uint256 npv2, uint256 claimable2) = slice.generatedCredit(id);
        assertEq(nominal2, 5609520241224149);
        assertEq(npv2, 5609520241224149);
        assertEq(claimable2, 5609520241224149);

        vm.warp(block.timestamp + 0x80000);
        (uint256 nominal3, uint256 npv3, uint256 claimable3) = slice.generatedCredit(id);
        assertEq(nominal3, 723803451433147656);
        assertEq(npv3, 722520787758532690);
        assertEq(claimable3, 723803451433147656);

        vm.warp(block.timestamp + 0xf0000);
        (uint256 nominal4, uint256 npv4, uint256 claimable4) = slice.generatedCredit(id);
        assertEq(nominal4, 992332217589964033);
        assertEq(npv4, 99e16);
        assertEq(claimable4, 992332217589964033);

        uint256 before2 = yieldToken.balanceOf(chad);
        slice.claim(id, 0);
        assertEq(yieldToken.balanceOf(chad) - before2, claimable4);

        vm.stopPrank();
    }

    function testSwapWithDirectFunctions() public {
        testAliceAddLiquidity();

        // Bob locks and swaps generator tokens for upfront payment
        vm.startPrank(bob);

        source.mintGenerator(bob, 1000000e18);
        generatorToken.approve(address(npvSwap), 200e18);
        (uint256 preview, ) = npvSwap.previewLockForYield(200e18, 1e18, 0);
        assertEq(preview, 612862441028507418);
        assertClose(preview, 6e17, 1e17);

        (uint256 quote ,) = npvSwap.previewSwapNPVForYieldOut(612862441028507418, 0);
        assertEq(quote, 657008058000000000);
        assertEq(quote, npvSwap.previewLockForNPV(200e18, 1e18));

        (uint256 id1 , uint256 amount) = npvSwap.lockForYield(bob, 200e18, 1e18, preview, 0, new bytes(0));
        (address owner , , , , , , ) = npvSwap.slice().debtSlices(id1);
        assertEq(owner, bob);
        assertEq(amount, 612862441028507418);
        assertEq(yieldToken.balanceOf(bob), 612862441028507418);
        assertClose(amount, 6e17, 1e17);

        vm.stopPrank();

        // Chad swaps upfront yield for future yield
        vm.startPrank(chad);
        source.mintYield(chad, 1000000e18);
        (uint256 previewNpv, ) = npvSwap.previewSwapForSlice(1e18, 0);
        assertEq(previewNpv, 1024273655801028271);

        (uint256 npvOut, ) = npvSwap.previewSwapYieldForNPV(1e18, 0);
        assertEq(npvOut, 1024273655801028271);

        (uint256 yieldIn, ) = npvSwap.previewSwapYieldForNPVOut(npvOut, 0);
        assertEq(yieldIn, 1e18);

        IERC20(yieldToken).approve(address(npvSwap), 1e18);
        uint256 id = npvSwap.swapForSlice(chad, 1e18, previewNpv, 0, new bytes(0));

        vm.warp(block.timestamp + 0x1000);
        (uint256 nominal2, uint256 npv2, uint256 claimable2) = slice.generatedCredit(id);
        assertEq(nominal2, 5803721014917702);
        assertEq(npv2, 5803721014917702);
        assertEq(claimable2, 5803721014917702);

        vm.warp(block.timestamp + 0x80000);
        (uint256 nominal3, uint256 npv3, uint256 claimable3) = slice.generatedCredit(id);
        assertEq(nominal3, 748861421495790065);
        assertEq(npv3, 747534352191586982);
        assertEq(claimable3, 748861421495790065);

        vm.warp(block.timestamp + 0xf0000);
        (uint256 nominal4, uint256 npv4, uint256 claimable4) = slice.generatedCredit(id);
        assertEq(nominal4, 1026686614424256478);

        // NPV paid out should equal the preview
        assertEq(npv4, 1024273655801028271);
        assertEq(npv4, previewNpv);
        assertEq(claimable4, 1026686614424256478);

        vm.stopPrank();
    }

    function testNPVClaimableForExistingYield() public {
        console.log("testNPVClaimableForExistingYield");

        // Add liquidity and move forward in time
        testAliceAddLiquidity();
        vm.warp(block.timestamp + 0x8000);
        slice.harvest();

        console.log("YT balance:", yieldToken.balanceOf(address(slice)));

        // Bob purchases future yield. Some should be immediately claimable.
        vm.startPrank(bob);
        source.mintYield(bob, 1000000e18);
        IERC20(yieldToken).approve(address(npvSwap), 1e18);
        (uint256 previewNpv, ) = npvSwap.previewSwapForSlice(5e17, 0);
        console.log("previewNpv", previewNpv);
        uint256 id = npvSwap.swapForSlice(bob, 5e17, previewNpv, 0, new bytes(0));
        console.log("id", id);
        vm.stopPrank();

        {
            (uint256 nominal, uint256 npv, uint256 claimable) = slice.generatedCredit(id);
            console.log("nominal  ", nominal);
            console.log("npv      ", npv);
            console.log("claimable", claimable);
            assertEq(nominal, 23624490900579010);
            assertEq(npv, 0);
            assertEq(claimable, 23624490900579010);
        }

        // Set yield rate to 0 and advance. No new yield, so claimable should stay flat.
        console.log("---");
        slice.recordData();
        source.setYieldPerBlock(0);
        vm.warp(block.timestamp + 0xf000);
        slice.recordData();

        {
            (uint256 nominal, uint256 npv, uint256 claimable) = slice.generatedCredit(id);
            console.log("nominal  ", nominal);
            console.log("npv      ", npv);
            console.log("claimable", claimable);
            assertEq(nominal, 23624490900579010);
            assertEq(npv, 0);
            assertEq(claimable, 23624490900579010);
        }

        // Resume yield generation
        console.log("---");
        slice.recordData();
        source.setYieldPerBlock(10000000000000);
        vm.warp(block.timestamp + 0xf00);
        slice.recordData();

        {
            (uint256 nominal, uint256 npv, uint256 claimable) = slice.generatedCredit(id);
            console.log("nominal  ", nominal);
            console.log("npv      ", npv);
            console.log("claimable", claimable);
            assertTrue(npv < nominal);
            assertEq(nominal,   26392349434071262);
            assertEq(npv,        2767858533492252);
            assertEq(claimable, 26392349434071262);
        }

        // Chad purchases some future yield. Some should be immediately available.
        vm.startPrank(chad);
        source.mintBoth(chad, 1000000e18);

        yieldToken.approve(address(npvSwap), 5e17);
        uint256 id2 = npvSwap.swapForSlice(chad, 5e17, 0, 0, new bytes(0));
        console.log("id2", id2);

        /* console.log("npv balance", npvToken.balanceOf(chad)); */
        /* assertEq(npvToken.balanceOf(chad), 100000000000000000000); */

        console.log("previewNpv     ", previewNpv);
        console.log("previewNpv 3e17", 3e17);
        assertEq(previewNpv, 473692461556744701);

        vm.stopPrank();

        {
            (uint256 bNominal, uint256 bNpv, uint256 bClaimable) = slice.generatedCredit(id);
            (uint256 cNominal, uint256 cNpv, uint256 cClaimable) = slice.generatedCredit(id2);
            console.log("-- BOB");
            console.log("nominal  ", bNominal);
            console.log("npv      ", bNpv);
            console.log("claimable", bClaimable);
            assertEq(bNominal, 26392349434071262);
            assertEq(bNpv, 2767858533492252);
            assertEq(bClaimable, 26392349434071262);

            console.log("-- CHAD");
            console.log("nominal  ", cNominal);
            console.log("npv      ", cNpv);
            console.log("claimable", cClaimable);
            assertEq(cNominal, 19251746879997161);
            assertEq(cNpv, 0);
            assertEq(cClaimable, 19251746879997161);
        }
    }
}
