// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { BaseDeployScript, DeployOptions } from "./BaseDeployScript.sol";
import { GMDYieldSource } from "../src/sources/GMDYieldSource.sol";

contract DeployGMDMarket is BaseDeployScript {
    function setUp() public {
        init();
    }

    function run() public {
        runDeploy(DeployOptions({
            yieldSource: new GMDYieldSource(),
            slug: "gmd",
            discountDaily: 1e14, // TODO
            discountRate: 250 * 10,
            discountMaxDays: 360,
            discountDecimals: 18,
            discountDiscountPeriod: 10 days,
            yieldSliceName: "npvGMD",
            yieldSliceDustLimit: 1e9
        }));
    }
}
