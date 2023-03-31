// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UniswapV3LiquidityPool } from "../src/liquidity/UniswapV3LiquidityPool.sol";
import { IUniswapV3Pool } from "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "../src/interfaces/uniswap/IUniswapV3Factory.sol";
import { StakedGLPYieldSource } from "../src/sources/StakedGLPYieldSource.sol";
import { YieldSlice } from "../src/core/YieldSlice.sol";
import { NPVToken } from "../src/tokens/NPVToken.sol";
import { NPVSwap } from "../src/core/NPVSwap.sol";
import { Discounter } from "../src/data/Discounter.sol";
import { YieldData } from "../src/data/YieldData.sol";

contract BaseScript is Script {
    using stdJson for string;

    address public arbitrumUniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public arbitrumNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public arbitrumSwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public arbitrumQuoterV2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    address public arbitrumWeth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public stakedGLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;
    address public tracker = 0x4e971a87900b931fF39d1Aad67697F49835400b6;

    address public npvToken;
    address public yieldToken;

    NPVSwap public npvSwap;
    YieldSlice public slice;
    YieldData public dataDebt;
    YieldData public dataCredit;
    Discounter public discounter;

    UniswapV3LiquidityPool public pool;
    IUniswapV3Pool public uniswapV3Pool;
    INonfungiblePositionManager public manager;

    uint256 pk;
    address deployerAddress;
    address devAddress;

    function eq(string memory str1, string memory str2) public pure returns (bool) {
        return keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2));
    }

    function addLiquidity(NPVSwap npvSwap,
                          address who,
                          uint256 yieldTokenAmount,
                          uint256 generatorTokenAmount,
                          uint256 yieldToLock,
                          int24 tickLower,
                          int24 tickUpper) public {

        npvToken = address(npvSwap.npvToken());
        yieldToken = address(npvSwap.slice().yieldToken());

        uint256 before = IERC20(npvToken).balanceOf(who);

        console.log("before", before);
        console.log("GT bal", npvSwap.slice().yieldSource().generatorToken().balanceOf(deployerAddress));

        npvSwap.slice().yieldSource().generatorToken().approve(address(npvSwap), generatorTokenAmount);
        npvSwap.lockForNPV(who, who, generatorTokenAmount, yieldToLock, new bytes(0));

        {
            uint256 npvTokenAmount = IERC20(npvToken).balanceOf(who) - before;
        
            assert(IERC20(npvToken).balanceOf(who) >= npvTokenAmount);
            assert(IERC20(yieldToken).balanceOf(who) >= yieldTokenAmount);

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
                recipient: who,
                deadline: block.timestamp + 10000 });

            IERC20(params.token0).approve(address(manager), token0Amount);
            IERC20(params.token1).approve(address(manager), token1Amount);

            manager.mint(params);
        }
    }

    function init() public {
        if (eq(vm.envString("NETWORK"), "arbitrum")) {
            console.log("Using Arbitrum mainnet private key");
            pk = vm.envUint("ARBITRUM_PRIVATE_KEY");
            deployerAddress = vm.envAddress("ARBITRUM_DEPLOYER_ADDRESS");
            devAddress = vm.envAddress("ARBITRUM_DEV_ADDRESS");
        } else {
            console.log("Using localhost private key");
            pk = vm.envUint("LOCALHOST_PRIVATE_KEY");
            deployerAddress = vm.envAddress("LOCALHOST_DEPLOYER_ADDRESS");
            devAddress = vm.envAddress("LOCALHOST_DEV_ADDRESS");
        }
    }
}
