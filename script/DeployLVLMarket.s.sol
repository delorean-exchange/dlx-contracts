// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { BaseDeployScript, DeployOptions } from "./BaseDeployScript.sol";
import { LVLYieldSource, LVLConstants } from "../src/sources/LVLYieldSource.sol";

contract DeployLVLMarket is BaseDeployScript {
    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);

        runDeploy(DeployOptions({
            yieldSource: new LVLYieldSource(LVLConstants.NETWORK_ARBITRUM, LVLConstants.TOKEN_LVL),
            slug: "lvl",
            discountDaily: 1e14, // TODO
            discountRate: 250 * 10,
            discountMaxDays: 360,
            discountDecimals: 18,
            discountDiscountPeriod: 10 days,
            yieldSliceName: "npvLVL",
            yieldSliceDustLimit: 1e9
        }));

        vm.stopBroadcast();
    }
}
