// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";
import { StakedGLPYieldSource } from "../src/sources/StakedGLPYieldSource.sol";
import { IGLPRewardTracker } from "../src/interfaces/IGLPRewardTracker.sol";
import { YieldData } from "../src/data/YieldData.sol";

contract StakedGLPYieldSourceTest is BaseTest {
    uint256 arbitrumForkFrom61289647;

    address glpWhale = 0x93006877903Fe83d8179dA661e72e4F9DB23Eb66;

    StakedGLPYieldSource glpYieldSource;
    IGLPRewardTracker tracker = IGLPRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);

    IERC20 glp = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

    function setUp() public {
        init();
        arbitrumForkFrom61289647 = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 61289647);
    }

    function testGLPYieldSource() public {
        vm.selectFork(arbitrumForkFrom61289647);
        assertEq(glp.balanceOf(glpWhale), 1e18);

        vm.startPrank(glpWhale);

        glpYieldSource = new StakedGLPYieldSource(address(glp),
                                                  arbitrumWeth,
                                                  address(tracker));

        glp.approve(address(glpYieldSource), 2e17);
        glpYieldSource.deposit(2e17, false);
        assertEq(glp.balanceOf(glpWhale), 8e17);
        assertEq(glp.balanceOf(address(glpYieldSource)), 2e17);
        assertEq(glpYieldSource.amountPending(), 0);

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 100);

        assertTrue(glpYieldSource.amountPending() > 0, "non-zero pending");
        assertEq(glpYieldSource.amountPending(), 197878327);

        assertEq(IERC20(arbitrumWeth).balanceOf(address(glpYieldSource)), 0);
        uint256 before = IERC20(arbitrumWeth).balanceOf(address(glpWhale));

        glpYieldSource.harvest();

        uint256 delta = IERC20(arbitrumWeth).balanceOf(address(glpWhale)) - before;
        assertTrue(delta > 0, "non-zero weth");
        assertEq(delta, 197878327);
        assertEq(IERC20(arbitrumWeth).balanceOf(address(glpYieldSource)), 0);
        assertEq(glpYieldSource.amountPending(), 0);

        assertEq(IERC20(glp).balanceOf(address(alice)), 0);
        glpYieldSource.withdraw(100, false, alice);
        assertEq(IERC20(glp).balanceOf(address(alice)), 100);
        glpYieldSource.withdraw(99e18, false, alice);
        assertEq(IERC20(glp).balanceOf(address(alice)), 2e17);

        vm.stopPrank();
    }
}
