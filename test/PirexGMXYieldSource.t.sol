// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseTest} from "./BaseTest.sol";
import {PirexGMXYieldSource} from "../src/sources/PirexGMXYieldSource.sol";
import {IPirexRewards} from "../src/interfaces/pxgmx/IPirexRewards.sol";
import {YieldData} from "../src/data/YieldData.sol";

import "forge-std/console.sol";

contract PirexGMXYieldSourceTest is BaseTest {
    uint256 arbitrumForkFrom97559408;
    
    PirexGMXYieldSource gmxYieldSource;
    address whale = 0x69059Fd0f306a6A752695A4d71aC43e82DEa8C2D;

    function setUp() public {
        init();
        arbitrumForkFrom97559408 = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 97559408);
    }

    function testFirst() public {
        vm.selectFork(arbitrumForkFrom97559408);

        gmxYieldSource = new PirexGMXYieldSource();
        console.log("balance of our address: ", gmxYieldSource.pxGMXToken().balanceOf(whale));
    }
    
    function testAccrueRewards() public {
        vm.selectFork(arbitrumForkFrom97559408);

        gmxYieldSource = new PirexGMXYieldSource();
        gmxYieldSource.setOwner(whale);

        IERC20 pxGMXToken = gmxYieldSource.pxGMXToken();
        IPirexRewards rewards = gmxYieldSource.rewards();
        
        uint256 accrued = rewards.getUserRewardsAccrued(whale, address(gmxYieldSource.yieldToken()));
        assertEq(accrued, 0);

        // accrue rewards
        rewards.accrueUser(address(gmxYieldSource.pxGMXToken()), whale);
        
        // check that accrued amount updated
        accrued = rewards.getUserRewardsAccrued(whale, address(gmxYieldSource.yieldToken()));
        assertEq(accrued, 5305394474454629);
    }
    
    function testPirex() public {
        vm.selectFork(arbitrumForkFrom97559408);

        gmxYieldSource = new PirexGMXYieldSource();
        gmxYieldSource.setOwner(whale);

        IERC20 pxGMXToken = gmxYieldSource.pxGMXToken();

        uint256 amount = pxGMXToken.balanceOf(whale);

        vm.startPrank(whale);

        pxGMXToken.approve(address(gmxYieldSource), amount);

        gmxYieldSource.deposit(amount, false);
        assertEq(pxGMXToken.balanceOf(whale), 0);

        vm.warp(block.timestamp + 1 days);
        gmxYieldSource.harvest();
        assertEq(gmxYieldSource.yieldToken().balanceOf(whale), 843455200656465);
        
        gmxYieldSource.withdraw(amount, false, whale);
        assertEq(pxGMXToken.balanceOf(whale), amount);

        vm.stopPrank();
    }
}
