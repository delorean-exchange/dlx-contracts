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
        runDeploy(new GMDYieldSource(), "gmd", "yGMD", 158e10); // As of 6/5/22
    }
}
