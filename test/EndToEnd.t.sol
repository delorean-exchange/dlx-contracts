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
        npvSwap.lockForNPV(alice, 2000e18, 10e18);

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
        npvSwap.lockForNPV(bob, 200e18, 1e18);
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
        (uint256 preview, ) = npvSwap.previewLockForYield(200e18, 1e18, 0);
        assertEq(preview, 612862441028507418);
        assertClose(preview, 6e17, 1e17);

        (uint256 quote ,) = npvSwap.previewNPVForYield(612862441028507418, 0);
        assertEq(quote, 657008058000000000);
        assertEq(quote, npvSwap.previewLockForNPV(200e18, 1e18));

        uint256 amount = npvSwap.lockForYield(bob, 200e18, 1e18, preview, 0);
        assertEq(amount, 612862441028507418);
        assertEq(yieldToken.balanceOf(bob), 612862441028507418);
        assertClose(amount, 6e17, 1e17);

        vm.stopPrank();

        // Chad swaps upfront yield for future yield
        vm.startPrank(chad);
        source.mintYield(chad, 1000000e18);
        (uint256 previewNpv, ) = npvSwap.previewSwapForSlice(1e18, 0);
        assertEq(previewNpv, 1024273655801028271);

        IERC20(yieldToken).approve(address(npvSwap), 1e18);
        uint256 id = npvSwap.swapForSlice(chad, 1e18, previewNpv, 0);

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

    /* function testScratch5() public { */
    /*     YieldSlice myslice = YieldSlice(0x0E801D84Fa97b50751Dbf25036d067dCf18858bF); */
    /*     console.log(myslice.nextId()); */
    /* } */

    /* function testScratch4() public { */
    /*     IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984); */
    /*     NPVSwap swap = NPVSwap(0x4aE4F6C7F96954fdCB5525c0786dE47342BaB82c); */
    /*     console.log("uni pool", factory.getPool(address(swap.npvToken()), */
    /*                                             address(swap.slice().yieldToken()), */
    /*                                             3000)); */

    /*     IUniswapV3Pool unipool = IUniswapV3Pool(0xB3a544B749565AAabf420d820c057b5279dB4f77); */
    /*     console.log("unipool liq", unipool.liquidity()); */

    /*     /\* address u = 0x77C78E9d81DF17463DeF7C0F0eE8a862df0b7dB1; *\/ */
    /*     /\* vm.startPrank(u); *\/ */
    /*     /\* console.log("preview!"); *\/ */
    /*     /\* swap.previewLockForYield(147000000000, 242093); *\/ */
    /*     /\* vm.stopPrank(); *\/ */
    /* } */

    /* function testScratch3() public { */
    /*     NPVSwap swap = NPVSwap(0x4aE4F6C7F96954fdCB5525c0786dE47342BaB82c); */
    /*     ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); */
    /*     address u = 0x77C78E9d81DF17463DeF7C0F0eE8a862df0b7dB1; */

    /*     // lockForYield 0xc8a2701d48FC0A082702511d3D5bD44384cA0C1E 0xcd82089D7a8b6D4e117D962a6E12f6a00e6847Ca 0xF20b80a2D122C0f316cfbE951248Dd1888Ce129E 20000000000000000000 2684818846947403 0 */

    /*     vm.startPrank(u); */
    /*     /\* IERC20(swap.slice().generatorToken()).approve(address(swap), 200000000000000000000); *\/ */
    /*     /\* swap.swapForNPV(u, 200000000000000000000, 1e18); *\/ */
    /*     /\* console.log("balanceIn", IERC20(0x4C11070E81429E1790326f3D5a01E216138601E2).balanceOf(u)); *\/ */

    /*     /\* uint256 amountIn = 2683475; *\/ */
    /*     /\* IQuoterV2 quoter = IQuoterV2(0x1dd92b83591781D0C6d98d07391eea4b9a6008FA); *\/ */
    /*     /\* IQuoterV2.QuoteExactInputSingleParams memory paramsq = IQuoterV2.QuoteExactInputSingleParams({ *\/ */
    /*     /\*     tokenIn: 0x4C11070E81429E1790326f3D5a01E216138601E2, *\/ */
    /*     /\*     tokenOut: 0x19c4f3D0a1efB215FA07d6F1D7Bc239faD1901B6, *\/ */
    /*     /\*     amountIn: amountIn, *\/ */
    /*     /\*     fee: 3000, *\/ */
    /*     /\*     sqrtPriceLimitX96: 0 }); *\/ */
    /*     /\* console.log("Calling preview with amountIn 2:", amountIn); *\/ */
    /*     /\* (uint256 x, , ,) = quoter.quoteExactInputSingle(paramsq); *\/ */
    /*     /\* console.log("X", x); *\/ */
    /*     /\* ISwapRouter.ExactInputSingleParams memory params = *\/ */
    /*     /\*     ISwapRouter.ExactInputSingleParams({ *\/ */
    /*     /\*         tokenIn: 0x4C11070E81429E1790326f3D5a01E216138601E2, *\/ */
    /*     /\*         tokenOut: 0x19c4f3D0a1efB215FA07d6F1D7Bc239faD1901B6, *\/ */
    /*     /\*         fee: 3000, *\/ */
    /*     /\*         recipient: u, *\/ */
    /*     /\*         deadline: block.timestamp + 1, *\/ */
    /*     /\*         amountIn: amountIn, *\/ */
    /*     /\*         amountOutMinimum: 0, *\/ */
    /*     /\*         sqrtPriceLimitX96: 0 }); *\/ */
    /*     /\* IERC20(0x4C11070E81429E1790326f3D5a01E216138601E2).approve(address(router), amountIn); *\/ */
    /*     /\* uint256 amountOut = router.exactInputSingle(params); *\/ */

    /*     IERC20(swap.slice().generatorToken()).approve(address(swap), 200000000000000000000); */
    /*     swap.lockForYield(0xF20b80a2D122C0f316cfbE951248Dd1888Ce129E, */
    /*                       10000000000000000000, */
    /*                       8202091446262925, */
    /*                       /\* 20000000000000, *\/ */
    /*                       /\* 2684818, *\/ */
    /*                       0, */
    /*                       0); */

    /*     vm.stopPrank(); */
    /* } */

    /* function testScratch2() public { */
    /*     /\* NPVSwap swap = NPVSwap(0xc8a2701d48FC0A082702511d3D5bD44384cA0C1E); *\/ */
    /*     /\* console.log(address(swap.npvToken())); *\/ */
    /*     /\* IUniswapV3Factory factory = IUniswapV3Factory(0x4893376342d5D7b3e31d4184c08b265e5aB2A3f6); *\/ */
    /*     IUniswapV3Pool unipool = IUniswapV3Pool(0x7d6319024974E9fad6076DE518f46DC78EB137Bd); */
    /*     /\* console.log("uni pool", factory.getPool(0x19c4f3D0a1efB215FA07d6F1D7Bc239faD1901B6, *\/ */
    /*     /\*                                         0x4C11070E81429E1790326f3D5a01E216138601E2, *\/ */
    /*     /\*                                         3000)); *\/ */
    /*     /\* console.log("liq", unipool.liquidity()); *\/ */

    /*     address u = 0xD8Dc00e6744D41730b907Dc859827B90c46226a8; */
    /*     vm.startPrank(u); */

    /*     /\* console.log("balance g", IERC20(swap.slice().generatorToken()).balanceOf(u)); *\/ */
    /*     /\* console.log("balance y", IERC20(swap.slice().yieldToken()).balanceOf(u)); *\/ */
    /*     /\* console.log("balance n", IERC20(swap.npvToken()).balanceOf(u)); *\/ */
    /*     /\* IERC20(swap.slice().generatorToken()).approve(address(swap), 200000000000000000000); *\/ */
    /*     /\* swap.swapForNPV(u, 200000000000000000000, 1e18); *\/ */
    /*     /\* console.log("balance n", IERC20(swap.npvToken()).balanceOf(u)); *\/ */

    /*     uint256 token0Amount = 1e16; */
    /*     uint256 token1Amount = 1e16; */

    /*     INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({ */
    /*         token0: address(0x19c4f3D0a1efB215FA07d6F1D7Bc239faD1901B6), */
    /*         token1: address(0x4C11070E81429E1790326f3D5a01E216138601E2), */
    /*         fee: 3000, */
    /*         tickLower: -1800, */
    /*         tickUpper: 2220, */
    /*         amount0Desired: 10000000000000000, */
    /*         amount1Desired: 10000000000000000, */
    /*         amount0Min: 0, */
    /*         amount1Min: 0, */
    /*         recipient: address(0xD8Dc00e6744D41730b907Dc859827B90c46226a8),  */
    /*         deadline: 1678350252 */
    /*         }); */

    /*     /\* assertEq(uniswapV3Pool.liquidity(), 0); *\/ */
    /*     console.log("liq before", unipool.liquidity()); */
    /*     INonfungiblePositionManager mgr = INonfungiblePositionManager(0x622e4726a167799826d1E1D150b076A7725f5D81); */
    /*     IERC20(params.token0).approve(address(mgr), token0Amount); */
    /*     IERC20(params.token1).approve(address(mgr), token1Amount); */
    /*     mgr.mint(params); */
    /*     console.log("liq after", unipool.liquidity()); */
    /*     vm.stopPrank(); */
    /* } */

    /* function testScratch() public { */
    /*     console.log("testScratch"); */

    /*     /\* NPVSwap swap = NPVSwap(0x6fCB3A96d2971007d352F2eF5A1e813374ab09F5); *\/ */
    /*     NPVSwap swap = NPVSwap(0xc8a2701d48FC0A082702511d3D5bD44384cA0C1E); */
    /*     console.log(address(swap.npvToken())); */

    /*     address u = 0xF20b80a2D122C0f316cfbE951248Dd1888Ce129E; */
    /*     vm.startPrank(u); */
    /*     generatorToken.approve(address(npvSwap), 2e18); */
    /*     npvSwap.swapForNPV(u, 2e18, 10e18); */

    /*     console.log("balance g", IERC20(swap.slice().generatorToken()).balanceOf(u)); */
    /*     console.log("balance y", IERC20(swap.slice().yieldToken()).balanceOf(u)); */
    /*     console.log("balance n", IERC20(swap.npvToken()).balanceOf(u)); */
    /*     return; */

    /*     uint256 tokens = 1000000; */
    /*     uint256 yield = 10000000; */

    /*     uint256 discounted = swap.slice().discounter().discounted(tokens, yield); */

    /*     console.log("discounter", address(swap.slice().discounter())); */
    /*     console.log("discounted", discounted); */

    /*     IERC20(swap.slice().generatorToken()).approve(address(swap), tokens); */
    /*     console.log("call ==>", address(swap.pool())); */
    /*     address unipool = address(0x7d6319024974E9fad6076DE518f46DC78EB137Bd); */
    /*     address quoter = address(0x1dd92b83591781D0C6d98d07391eea4b9a6008FA); */

    /*     console.log("token0", IUniswapV3Pool(unipool).token0()); */
    /*     console.log("token1", IUniswapV3Pool(unipool).token1()); */
    /*     console.log("liq", IUniswapV3Pool(unipool).liquidity()); */

    /*     uint256 token0Amount = 1e18; */
    /*     uint256 token1Amount = 1e18; */

    /*     INonfungiblePositionManager.MintParams memory params2 = INonfungiblePositionManager.MintParams({ */
    /*         token0: IUniswapV3Pool(unipool).token0(), */
    /*         token1: IUniswapV3Pool(unipool).token1(), */
    /*         fee: 3000, */
    /*         tickLower: -1800, */
    /*         tickUpper: 2220, */
    /*         amount0Desired: token0Amount, */
    /*         amount1Desired: token1Amount, */
    /*         amount0Min: 0, */
    /*         amount1Min: 0, */
    /*         recipient: u,  */
    /*         deadline: block.timestamp + 1 }); */

    /*     return; */

    /*     IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({ */
    /*         tokenIn: address(0x4C11070E81429E1790326f3D5a01E216138601E2), */
    /*         tokenOut: address(0x19c4f3D0a1efB215FA07d6F1D7Bc239faD1901B6), */
    /*         amountIn: 3082000, */
    /*         fee: 3000, */
    /*         sqrtPriceLimitX96: 0 }); */

    /*     IQuoterV2(quoter).quoteExactInputSingle(params); */

    /*     /\* swap.previewLockForYield(tokens, yield); *\/ */
    /*     /\* swap.lockForYield(u, tokens, yield, 0); *\/ */

    /*     vm.stopPrank(); */
    /* } */

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {}
}

