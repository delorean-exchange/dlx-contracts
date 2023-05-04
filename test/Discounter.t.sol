// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";
import { NPVToken } from "../src/tokens/NPVToken.sol";

contract DiscounterTest is BaseTest {

    function testDiscounter() public {
        init();

        assertEq(discounter.discounted(1e18, 1e18), 3285040290000000);
        assertEq(discounter.pv(20, 1e18), 990047357802328597);
        assertEq(discounter.nominal(20, 1e18), 1010052693054768512);
        assertEq(discounter.shiftNPV(20, 1e18), 1010052693054768512);

        vm.prank(bob);
        vm.expectRevert();
        discounter.setDaily(2e13);

        vm.prank(bob);
        vm.expectRevert();
        discounter.setMaxDays(2e13);

        discounter.setDaily(2e13);

        assertEq(discounter.discounted(1e18, 1e18), 6570080580000000);
        assertEq(discounter.pv(20, 1e18), 990047357802328597);
        assertEq(discounter.nominal(20, 1e18), 1010052693054768512);
        assertEq(discounter.shiftNPV(20, 1e18), 1010052693054768512);
    }

}
