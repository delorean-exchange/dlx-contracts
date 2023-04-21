// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";
import { LvlYieldSource } from "../src/sources/LvlYieldSource.sol";
import { ILvlStaking } from "../src/interfaces/level/ILvlStaking.sol";


contract LvlYieldSourceTest is BaseTest {
    uint256 bnbLvlFork;

    ILvlStaking lvlStaking = ILvlStaking(0x08A12FFedf49fa5f149C73B07E31f99249e40869);

    function setUp() public {
        bnbLvlFork = vm.createFork(vm.envString("BSC_RPC_URL"), 27526853);
    }

    function testLVLYieldSource() public {
        vm.selectFork(bnbLvlFork);
        address user = 0x08fa296ca8D0c9cb34aCE38ae9cF49b751dC8aeC;

        LvlYieldSource source = new LvlYieldSource(address(lvlStaking));
        source.setOwner(user);

        // Unstake to get some LVL
        (uint256 amount, ) = lvlStaking.userInfo(user);
        vm.startPrank(user);

        lvlStaking.unstake(user, amount);
        source.lvl().approve(address(source), amount);
        source.deposit(amount, false);

        assertEq(source.amountPending(), 0);
        assertEq(source.amountGenerator(), amount);

        vm.roll(block.number + 0xf000);
        vm.warp(block.timestamp + 0xf000);

        assertTrue(source.amountPending() > 0);
        assertEq(source.amountPending(), 3573879325042644);
        assertEq(source.amountGenerator(), amount);

        vm.roll(block.number + 0xf000);
        vm.warp(block.timestamp + 0xf000);

        assertTrue(source.amountPending() > 0);
        assertEq(source.amountPending(), 7147758650442316);
        assertEq(source.amountGenerator(), amount);

        source.harvest();

        assertEq(source.llp().balanceOf(user), 7149605906265222);

        source.withdraw(amount / 2, false, user);
        assertEq(source.amountGenerator(), amount / 2);
        assertEq(source.lvl().balanceOf(user), amount / 2);

        vm.stopPrank();
    }
}
