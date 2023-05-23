// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./BaseScript.sol";

import { YieldSlice } from "../src/core/YieldSlice.sol";

contract SetFees is BaseScript {
    using stdJson for string;

    function setUp() public {
        init();
    }

    function run() public {
        vm.startBroadcast(pk);

        string memory filename = "./json/config.";
        filename = string.concat(filename, vm.envString("NETWORK"));
        filename = string.concat(filename, ".json");
        string memory config = vm.readFile(filename);

        slice = YieldSlice(vm.parseJsonAddress(config, ".fakeglp_slice.address"));

        slice.setDebtFee(100_0);
        slice.setCreditFee(5_0);

        vm.stopBroadcast();
    }
}
