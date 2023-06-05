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

    PirexGMXYieldSource yieldSource;
    IPirexRewards pxRewards;
    IERC20 pxGMXToken;

    address whale = 0x69059Fd0f306a6A752695A4d71aC43e82DEa8C2D;

    function setUp() public {
        init();
        arbitrumForkFrom97559408 = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 97559408);
    }

    function setUpManual() private {
        vm.selectFork(arbitrumForkFrom97559408);

        yieldSource = new PirexGMXYieldSource();
        pxGMXToken = yieldSource.pxGMXToken();
        pxRewards = yieldSource.pxRewards();
    }

    function testFirst() public {
        setUpManual();

        console.log("balance of our address: ", pxGMXToken.balanceOf(whale));
    }

    function testAccrueRewards() public {
        setUpManual();

        yieldSource.setOwner(whale);

        uint256 accrued = yieldSource.amountPending();
        assertEq(accrued, 0);

        // call pirex's weird function that manually updates accrued amounts
        pxRewards.accrueUser(address(yieldSource.pxGMXToken()), whale);

        // check that accrued amount updated
        accrued = yieldSource.amountPending();
        assertEq(accrued, 5305394474454629);
    }

    function testPirex() public {
        vm.selectFork(arbitrumForkFrom97559408);

        yieldSource = new PirexGMXYieldSource();
        pxGMXToken = yieldSource.pxGMXToken();
        pxRewards = yieldSource.pxRewards();

        uint256 amount = pxGMXToken.balanceOf(whale);

        yieldSource.setOwner(whale);

        vm.startPrank(whale);

        // as whale, approve our yieldsource to take our gmx tokens
        pxGMXToken.approve(address(yieldSource), amount);

        // deposit gmx tokens from whale into yieldsource
        uint256 oldAmount = pxGMXToken.balanceOf(address(yieldSource));
        yieldSource.deposit(amount, false);
        assertEq(pxGMXToken.balanceOf(whale), 0); // whale now has nothing
        assertEq(pxGMXToken.balanceOf(address(yieldSource)) - oldAmount, amount); // we gained by `amount`

        // allow the yields to accrue
        vm.warp(block.timestamp + 1 days);

        // harvest the yield, ensure whale got the weth
        yieldSource.harvest();
        assertEq(yieldSource.yieldToken().balanceOf(whale), 843455200656465);

        // withdraw gmx tokens as whale
        yieldSource.withdraw(amount, false, whale);
        assertEq(pxGMXToken.balanceOf(whale), amount);

        vm.stopPrank();
    }
}
