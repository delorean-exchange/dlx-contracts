// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { BaseScript } from "./BaseScript.sol";
import { BaseDeployScript } from "./BaseDeployScript.sol";
import { GMDYieldSource } from "../src/sources/GMDYieldSource.sol";

contract DeployGMDMarket is BaseScript, BaseDeployScript {
    using stdJson for string;

    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);
        runDeploy(DeployOptions({
            yieldSource: new GMDYieldSource(),
            slug: "gmd",
            discountDaily: 158e10, // As of 6/5/22
            discountRate: 250 * 10,
            discountMaxDays: 360,
            discountDecimals: 18,
            discountDiscountPeriod: 10 days,
            yieldSliceName: "yGMD",
            yieldSliceDustLimit: 1e9
        }));
    }
}
