// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { BaseScript } from "./BaseScript.sol";
import { BaseDeployScript } from "./BaseDeployScript.sol";
import { PirexGMXYieldSource } from "../src/sources/PirexGMXYieldSource.sol";

contract DeployPirexGMXMarket is BaseScript, BaseDeployScript {
    using stdJson for string;

    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);
        runDeploy(new PirexGMXYieldSource(), "pxgmx", "yPXGMX", 158e10); // As of 6/5/22
    }
}
