// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { BaseDeployScript, DeployOptions } from "./BaseDeployScript.sol";
import { StakedGLPYieldSource } from "../src/sources/StakedGLPYieldSource.sol";

contract DeployGLPMarket is BaseDeployScript {
    using stdJson for string;

    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);

        string memory historical = vm.readFile("json/historical.json");
        uint256 daily = vm.parseJsonUint(historical, ".glp.avgDailyRewardPerToken");

        StakedGLPYieldSource yieldSource = new StakedGLPYieldSource(
            address(stakedGLP), arbitrumWeth, address(tracker));

        runDeploy(DeployOptions({
            yieldSource: yieldSource,
            slug: "glp",
            discountDaily: daily, // As of 6/5/22
            discountRate: 250 * 10,
            discountMaxDays: 360,
            discountDecimals: 18,
            discountDiscountPeriod: 10 days,
            yieldSliceName: "yGLP",
            yieldSliceDustLimit: 1e9
        }));
    }
}
