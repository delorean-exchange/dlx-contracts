// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { BaseScript } from "./BaseScript.sol";
import { UniswapV3LiquidityPool } from "../src/liquidity/UniswapV3LiquidityPool.sol";
import { IUniswapV3Pool } from "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "../src/interfaces/uniswap/IUniswapV3Factory.sol";
import { IYieldSource } from "../src/interfaces/IYieldSource.sol";
import { YieldSlice } from "../src/core/YieldSlice.sol";
import { NPVToken } from "../src/tokens/NPVToken.sol";
import { NPVSwap } from "../src/core/NPVSwap.sol";
import { Discounter } from "../src/data/Discounter.sol";
import { YieldData } from "../src/data/YieldData.sol";

struct DeployOptions {
    IYieldSource yieldSource;
    string slug;

    uint256 discountDaily;
    uint256 discountRate;
    uint256 discountMaxDays;
    uint256 discountDecimals;
    uint256 discountDiscountPeriod;

    string yieldSliceName;
    uint256 yieldSliceDustLimit;
}

contract BaseDeployScript is BaseScript {
    function runDeploy(DeployOptions memory options) public {
        vm.startBroadcast(pk);

        address yieldToken = address(options.yieldSource.yieldToken());

        dataDebt = new YieldData(7 days);
        dataCredit = new YieldData(7 days);

        discounter = new Discounter(
            options.discountDaily,
            options.discountRate,
            options.discountMaxDays,
            options.discountDecimals,
            options.discountDiscountPeriod
        );

        slice = new YieldSlice(options.yieldSliceName,
                               address(options.yieldSource),
                               address(dataDebt),
                               address(dataCredit),
                               address(discounter),
                               options.yieldSliceDustLimit);

        options.yieldSource.setOwner(address(slice));
        dataDebt.setWriter(address(slice));
        dataCredit.setWriter(address(slice));
        address npvToken = address(slice.npvToken());

        {
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
        }

        npvSwap = new NPVSwap(address(slice), address(pool));

        slice.setTreasury(treasuryAddress);

        vm.stopBroadcast();

        {
            string memory objName = string.concat("deploy_", options.slug);
            string memory json;
            json = vm.serializeAddress(objName, "address_dataCredit", address(dataCredit));
            json = vm.serializeAddress(objName, "address_dataDebt", address(dataDebt));
            json = vm.serializeAddress(objName, "address_discounter", address(discounter));
            json = vm.serializeAddress(objName, "address_npvSwap", address(npvSwap));
            json = vm.serializeAddress(objName, "address_npvToken", address(npvToken));
            json = vm.serializeAddress(objName, "address_pool", address(pool));
            json = vm.serializeAddress(objName, "address_slice", address(slice));
            json = vm.serializeAddress(objName, "address_yieldSource", address(options.yieldSource));

            json = vm.serializeString(objName, "contractName_dataCredit", "YieldData");
            json = vm.serializeString(objName, "contractName_dataDebt", "YieldData");
            json = vm.serializeString(objName, "contractName_discounter", "Discounter");
            json = vm.serializeString(objName, "contractName_npvSwap", "NPVSwap");
            json = vm.serializeString(objName, "contractName_npvToken", "NPVToken");
            json = vm.serializeString(objName, "contractName_pool", "UniswapV3LiquidityPool");
            json = vm.serializeString(objName, "contractName_slice", "YieldSlice");
            json = vm.serializeString(objName, "contractName_yieldSource", "IYieldSource");

            if (eq(vm.envString("NETWORK"), "arbitrum")) {
                vm.writeJson(json, string.concat("./json/deploy_", options.slug, ".arbitrum.json"));
            } else {
                vm.writeJson(json, string.concat("./json/deploy_", options.slug, ".localhost.json"));
            }
        }
    }
}
