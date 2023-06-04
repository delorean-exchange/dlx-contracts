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
    IERC20 pxGMXToken = IERC20(0x9A592B4539E22EeB8B2A3Df679d572C7712Ef999);
    IPirexRewards rewards = IPirexRewards(0x612293B0b3aD2dCa6770E74478A30E0FCe266fDE);

    function setUp() public {
        init();
        arbitrumForkFrom97559408 = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 97559408);
    }

    function testFirst() public {
        vm.selectFork(arbitrumForkFrom97559408);
        console.log("balance of our address: ", pxGMXToken.balanceOf(0x69059Fd0f306a6A752695A4d71aC43e82DEa8C2D));
    }
    
    function testPirex() public {
        vm.selectFork(arbitrumForkFrom97559408);
        gmxYieldSource = new PirexGMXYieldSource();

        address whale = 0x9cDD0603437A7Da4e4Cf8F0c71755F6EF280Bbfe;
        uint256 amount = pxGMXToken.balanceOf(whale);

        gmxYieldSource.setOwner(whale);

        vm.startPrank(whale);
        
        pxGMXToken.approve(address(gmxYieldSource), amount);

        gmxYieldSource.deposit(amount, false);
        assertEq(pxGMXToken.balanceOf(whale), 0);

        vm.warp(block.timestamp + 1 days);
        gmxYieldSource.harvest();

        assertEq(IERC20(gmxYieldSource.yieldToken()).balanceOf(whale), 843455200656465);
        
        gmxYieldSource.withdraw(amount, false, whale);
        assertEq(pxGMXToken.balanceOf(whale), amount);

        vm.stopPrank();
    }
}
