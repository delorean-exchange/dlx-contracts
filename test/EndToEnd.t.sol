// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./BaseTest.sol";
import "../src/liquidity/UniswapV3LiquidityPool.sol";
import "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import "../src/interfaces/uniswap/INonfungiblePositionManager.sol";

contract EndToEndTest is BaseTest {

    function setUp() public {
        init();
    }

    function testAliceAddLiquidity() public {
        // Alice: Get some NPV tokens so we can add liquidity
        vm.startPrank(alice);
        generatorToken.approve(address(npvSwap), 2000e18);
        npvSwap.swapForNPV(alice, 2000e18, 10e18);

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
        assertEq(npvSwap.previewSwapForNPV(200e18, 1e18), 657008058000000000);
        npvSwap.swapForNPV(bob, 200e18, 1e18);
        assertEq(IERC20(npvToken).balanceOf(bob), 657008058000000000);

        IERC20(npvToken).approve(address(pool), 5e17);
        uint256 before = IERC20(yieldToken).balanceOf(bob);
        uint256 out = pool.swap(bob, address(npvToken), 5e17, 0);
        uint256 delta = IERC20(yieldToken).balanceOf(bob) - before;
        assertClose(delta, 5e17, 1e17);
        assertEq(out, 473692461556744701);
        assertEq(delta, 473692461556744701);

        vm.stopPrank();

        // Chad: Use ETH to buy future yield
        vm.startPrank(chad);

        source.mintYield(chad, 1000000e18);
        IERC20(yieldToken).approve(address(pool), 1e18);
        uint256 out2 = pool.swap(chad, address(yieldToken), 1e18, 0);
        uint256 balance2 = IERC20(npvToken).balanceOf(chad);
        assertClose(balance2, 1e18, 5e17);
        assertEq(out2, 994537036467183765);
        assertEq(balance2, 994537036467183765);

        IERC20(npvToken).approve(address(npvSwap), 99e16);
        uint256 id = npvSwap.swapNPVForSlice(99e16);
        (, , uint256 claimable1) = slice.generatedCredit(id);
        assertEq(claimable1, 0);

        vm.roll(block.number + 0x1000);
        (uint256 nominal2, uint256 npv2, uint256 claimable2) = slice.generatedCredit(id);
        assertEq(nominal2, 5609520241224149);
        assertEq(npv2, 5609520241224149);
        assertEq(claimable2, 5609520241224149);

        vm.roll(block.number + 0x80000);
        (uint256 nominal3, uint256 npv3, uint256 claimable3) = slice.generatedCredit(id);
        assertEq(nominal3, 723803451433147656);
        assertEq(npv3, 709473836125037900);
        assertEq(claimable3, 723803451433147656);

        vm.roll(block.number + 0xf0000);
        (uint256 nominal4, uint256 npv4, uint256 claimable4) = slice.generatedCredit(id);
        assertEq(nominal4, 1017563670304100229);
        assertEq(npv4, 99e16);
        assertEq(claimable4, 1017563670304100229);

        vm.stopPrank();
    }

    function testSwapWithDirectFunctions() public {
        testAliceAddLiquidity();

        // Bob locks and swaps generator tokens for upfront payment
        vm.startPrank(bob);

        source.mintGenerator(bob, 1000000e18);
        generatorToken.approve(address(npvSwap), 200e18);
        uint256 preview = npvSwap.previewSwapForYield(200e18, 1e18);
        assertEq(preview, 612862441028507418);
        assertClose(preview, 6e17, 1e17);

        uint256 amount = npvSwap.swapForYield(bob, 200e18, 1e18, preview);
        assertEq(amount, 612862441028507418);
        assertEq(yieldToken.balanceOf(bob), 612862441028507418);
        assertClose(amount, 6e17, 1e17);

        vm.stopPrank();

        // Chad swaps upfront yield for future yield
        vm.startPrank(chad);
        source.mintYield(chad, 1000000e18);
        uint256 previewNpv = npvSwap.previewSwapForSlice(1e18);
        assertEq(previewNpv, 1024273655801028271);

        IERC20(yieldToken).approve(address(npvSwap), 1e18);
        uint256 id = npvSwap.swapForSlice(chad, 1e18, previewNpv);

        vm.roll(block.number + 0x1000);
        (uint256 nominal2, uint256 npv2, uint256 claimable2) = slice.generatedCredit(id);
        assertEq(nominal2, 5803721014917702);
        assertEq(npv2, 5803721014917702);
        assertEq(claimable2, 5803721014917702);

        vm.roll(block.number + 0x80000);
        (uint256 nominal3, uint256 npv3, uint256 claimable3) = slice.generatedCredit(id);
        assertEq(nominal3, 748861421495790064);
        assertEq(npv3, 734035716992901208);
        assertEq(claimable3, 748861421495790064);

        vm.roll(block.number + 0xf0000);
        (uint256 nominal4, uint256 npv4, uint256 claimable4) = slice.generatedCredit(id);
        assertEq(nominal4, 1052791576356255516);

        // NPV paid out should equal the preview
        assertEq(npv4, 1024273655801028271);
        assertEq(npv4, previewNpv);

        assertEq(claimable4, 1052791576356255516);

        vm.stopPrank();
    }
}

