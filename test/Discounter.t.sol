// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";
import { NPVToken } from "../src/tokens/NPVToken.sol";

contract DiscounterTest is BaseTest {

    function testDiscounter() public {
        init();

        assertEq(discounter.discounted(1e18, 1e18), 3267588900000000);
        assertEq(discounter.shiftForward(20, 1e18), 1352930196488360054);
        assertEq(discounter.shiftBackward(20, 1e18), 739136433347101738);

        vm.prank(bob);
        vm.expectRevert();
        discounter.setDaily(2e13);

        vm.prank(bob);
        vm.expectRevert();
        discounter.setMaxDays(2e13);

        discounter.setDaily(2e13);

        assertEq(discounter.discounted(1e18, 1e18), 6535177800000000);
        assertEq(discounter.shiftForward(20, 1e18), 1352930196488360054);
        assertEq(discounter.shiftBackward(20, 1e18), 739136433347101738);
    }

    function testSetMaxDays() public {
        init();

        discounter.setMaxDays(8 * 360);
        assertEq(discounter.maxDays(), 8 * 360);

        vm.expectRevert("DS: max days limit");
        discounter.setMaxDays(8 * 360 + 1);
    }

    function testSingleEpochOverflow() public {
        init();

        discounter.setDaily(100e18);
        assertEq(discounter.discounted(10e18, 100), 98);
    }
}
