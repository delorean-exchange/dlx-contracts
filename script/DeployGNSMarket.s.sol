// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { BaseDeployScript, DeployOptions } from "./BaseDeployScript.sol";
import { GNSYieldSource } from "../src/sources/GNSYieldSource.sol";

contract DeployGNSMarket is BaseDeployScript {
    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);

        string memory historical = vm.readFile("json/historical.json");
        uint256 daily = vm.parseJsonUint(historical, ".gns.avgDailyRewardPerToken");

        GNSYieldSource yieldSource = new GNSYieldSource(0x18c11FD286C5EC11c3b683Caa813B77f5163A122,
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
