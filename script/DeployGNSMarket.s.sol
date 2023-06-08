// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { BaseScript } from "./BaseScript.sol";

import { UniswapV3LiquidityPool } from "../src/liquidity/UniswapV3LiquidityPool.sol";
import { IUniswapV3Pool } from "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "../src/interfaces/uniswap/IUniswapV3Factory.sol";
import { GNSYieldSource } from "../src/sources/GNSYieldSource.sol";
import { YieldSlice } from "../src/core/YieldSlice.sol";
import { NPVToken } from "../src/tokens/NPVToken.sol";
import { NPVSwap } from "../src/core/NPVSwap.sol";
import { Discounter } from "../src/data/Discounter.sol";
import { YieldData } from "../src/data/YieldData.sol";

contract DeployGNSMarket is BaseScript {
    using stdJson for string;

    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);

        string memory historical = vm.readFile("json/historical.json");
        uint256 daily = vm.parseJsonUint(historical, ".gns.avgDailyRewardPerToken");

        GNSYieldSource source = new GNSYieldSource(0x18c11FD286C5EC11c3b683Caa813B77f5163A122,
                                                   0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
                                                   0x6B8D3C08072a020aC065c467ce922e3A36D3F9d6);

        runDeploy(DeployOptions({
            yieldSource: yieldSource,
            slug: "gns",
            discountDaily: daily,
            discountRate: 250 * 10,
            discountMaxDays: 720,
            discountDecimals: 18,
            discountDiscountPeriod: 10 days,
            yieldSliceName: "npvGNS",
            yieldSliceDustLimit: 1e9
        }));

        vm.stopBroadcast();
    }
}
