// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { BaseDeployScript, DeployOptions } from "./BaseDeployScript.sol";
import { PirexGMXYieldSource } from "../src/sources/PirexGMXYieldSource.sol";

contract DeployPirexGMXMarket is BaseDeployScript {
    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);
        runDeploy(DeployOptions({
            yieldSource: new PirexGMXYieldSource(),
            slug: "pxgmx",
            discountDaily: 158e10, // As of 6/5/22
            discountRate: 250 * 10,
            discountMaxDays: 360,
            discountDecimals: 18,
            discountDiscountPeriod: 10 days,
            yieldSliceName: "yPXGMX",
            yieldSliceDustLimit: 1e9
        }));
        vm.stopBroadcast();
    }
}
