// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./BaseScript.sol";

import { FakeToken } from "../test/helpers/FakeToken.sol";
import { FakeYieldSource } from "../test/helpers/FakeYieldSource.sol";
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

contract DeployGLPMarket is BaseScript {
    using stdJson for string;

    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);

        FakeYieldSource source = new FakeYieldSource(10000000000000);
        address yieldToken = address(source.yieldToken());
        dataDebt = new YieldData(20);
        dataCredit = new YieldData(20);
        discounter = new Discounter(1e13, 500, 360, 18);
        slice = new YieldSlice("npvETH-fGLP",
                               address(source),
                               address(dataDebt),
                               address(dataCredit),
                               address(discounter),
                               1e9);

        npvToken = address(slice.npvToken());

        source.setOwner(address(slice));
        dataDebt.setWriter(address(slice));
        dataCredit.setWriter(address(slice));

        uint160 initialPrice;
        address token0;
        address token1;

        // Initial price is 0.99 ETH/npvETH
        if (npvToken < yieldToken) {
            initialPrice = 78831026366734653132768280576;
            (token0, token1) = (npvToken, yieldToken);
        } else {
            initialPrice = 79627299360338034355936952320;
            (token0, token1) = (yieldToken, npvToken);
        }

        manager = INonfungiblePositionManager(arbitrumNonfungiblePositionManager);
        uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(arbitrumUniswapV3Factory).getPool(token0, token1, 3000));
        if (address(uniswapV3Pool) == address(0)) {
            uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(arbitrumUniswapV3Factory).createPool(token0, token1, 3000));
            IUniswapV3Pool(uniswapV3Pool).initialize(initialPrice);
        }
        pool = new UniswapV3LiquidityPool(address(uniswapV3Pool), arbitrumSwapRouter, arbitrumQuoterV2);

        npvSwap = new NPVSwap(address(npvToken), address(slice), address(pool));

        source.mintBoth(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 10000e18);
        source.mintBoth(deployerAddress, 10000e18);

        vm.stopBroadcast();

        {
            string memory objName = "deploy_fakeglp";
            string memory json;
            json = vm.serializeAddress(objName, "address_dataCredit", address(dataCredit));
            json = vm.serializeAddress(objName, "address_dataDebt", address(dataDebt));
            json = vm.serializeAddress(objName, "address_discounter", address(discounter));
            json = vm.serializeAddress(objName, "address_npvSwap", address(npvSwap));
            json = vm.serializeAddress(objName, "address_npvToken", address(npvToken));
            json = vm.serializeAddress(objName, "address_pool", address(pool));
            json = vm.serializeAddress(objName, "address_slice", address(slice));
            json = vm.serializeAddress(objName, "address_yieldSource", address(source));

            json = vm.serializeString(objName, "contractName_dataCredit", "YieldData");
            json = vm.serializeString(objName, "contractName_dataDebt", "YieldData");
            json = vm.serializeString(objName, "contractName_discounter", "Discounter");
            json = vm.serializeString(objName, "contractName_npvSwap", "NPVSwap");
            json = vm.serializeString(objName, "contractName_npvToken", "NPVToken");
            json = vm.serializeString(objName, "contractName_pool", "UniswapV3LiquidityPool");
            json = vm.serializeString(objName, "contractName_slice", "YieldSlice");
            json = vm.serializeString(objName, "contractName_yieldSource", "IYieldSource");

            if (eq(vm.envString("NETWORK"), "arbitrum_mainnet")) {
                vm.writeJson(json, "./json/deploy_fakeglp.arbitrum.json");
            } else {
                vm.writeJson(json, "./json/deploy_fakeglp.localhost.json");
            }
        }
    }
}
