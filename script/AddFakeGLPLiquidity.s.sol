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

    function setUp() public {
        init();
    }

    function addLiquidity(NPVSwap npvSwap, int24 tickLower, int24 tickUpper) public {
        address npvToken = address(npvSwap.npvToken());
        address yieldToken = address(npvSwap.slice().yieldToken());

        npvSwap.slice().yieldSource().generatorToken().approve(address(npvSwap), 1000e18);
        npvSwap.lockForNPV(deployerAddress, deployerAddress, 1000e18, 1000e18);

        uint256 npvTokenAmount = IERC20(npvToken).balanceOf(deployerAddress);
        uint256 yieldTokenAmount = 1000e18;
        
        assert(IERC20(npvToken).balanceOf(deployerAddress) >= npvTokenAmount);
        assert(IERC20(yieldToken).balanceOf(deployerAddress) >= yieldTokenAmount);

        uint256 token0Amount;
        uint256 token1Amount;
        address token0;
        address token1;

        if (npvToken < yieldToken) {
            (token0, token1) = (npvToken, yieldToken);
            (token0Amount, token1Amount) = (npvTokenAmount, yieldTokenAmount);
        } else {
            (token0, token1) = (yieldToken, npvToken);
            (token0Amount, token1Amount) = (yieldTokenAmount, npvTokenAmount);
            (tickLower, tickUpper) = (-tickUpper, -tickLower);
        }

        manager = INonfungiblePositionManager(arbitrumNonfungiblePositionManager);
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
            recipient: deployerAddress,
            deadline: block.timestamp + 10000 });
        IERC20(params.token0).approve(address(manager), token0Amount);
        IERC20(params.token1).approve(address(manager), token1Amount);

        manager.mint(params);
    }

    function run() public {
        uint256 pk = vm.envUint("LOCALHOST_PRIVATE_KEY");

        vm.startBroadcast(pk);

        string memory config = vm.readFile("json/config.localhost.json");
        NPVSwap npvSwap = NPVSwap(vm.parseJsonAddress(config, ".fakeglp_npvSwap.address"));
        UniswapV3LiquidityPool pool = UniswapV3LiquidityPool(vm.parseJsonAddress(config, ".fakeglp_pool.address"));
        FakeYieldSource source = FakeYieldSource(vm.parseJsonAddress(config, ".fakeglp_yieldSource.address"));

        source.mintBoth(deployerAddress, 10000e18);

        uint256 before = IUniswapV3Pool(pool.pool()).liquidity();
        console.log("Liquidity before:", before);

        addLiquidity(npvSwap, -180, -60);
        addLiquidity(npvSwap, -360, -60);
        addLiquidity(npvSwap, -6960, -60);

        uint256 afterVal = IUniswapV3Pool(pool.pool()).liquidity();
        console.log("Liquidity after: ", afterVal);
        console.log("Delta:           ", afterVal - before);

        // Sanity check that liquidity is set up correctly
        npvSwap.previewSwapNPVForYield(115792089237316195423570985008687907853269984665640564039457584007913129639935, 83095197869223157895945127773);

        vm.stopBroadcast();
    }
}
