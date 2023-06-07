// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";
import { PirexGMXYieldSource } from "../src/sources/PirexGMXYieldSource.sol";
import { IPirexRewards } from "../src/interfaces/pxgmx/IPirexRewards.sol";
import { YieldData } from "../src/data/YieldData.sol";

contract PirexGMXYieldSourceTest is BaseTest {
    uint256 arbitrumForkFrom97559408;

    PirexGMXYieldSource yieldSource;
    IPirexRewards pxRewards;
    IERC20 pxGMXToken;

    address whale = 0x9cDD0603437A7Da4e4Cf8F0c71755F6EF280Bbfe;

    function setUp() public {
        init();
        vm.selectFork(vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 97559408));

        yieldSource = new PirexGMXYieldSource();
        pxGMXToken = yieldSource.pxGMXToken();
        pxRewards = yieldSource.pxRewards();
    }

    function testFirst() public {
        assertEq(pxGMXToken.balanceOf(whale), 340252725009943497968);
    }

    function testAccrueRewards() public {
        yieldSource.setOwner(whale);

        uint256 accrued = pxRewards.getUserRewardsAccrued(whale, address(yieldSource.yieldToken()));
        assertEq(accrued, 0);

        // call pirex's weird function that manually updates accrued amounts
        pxRewards.accrueUser(address(pxGMXToken), whale);

        // check that accrued amount updated
        accrued = pxRewards.getUserRewardsAccrued(whale, address(yieldSource.yieldToken()));
        assertEq(accrued, 5305394474454629);
    }

    function testPirex() public {
        yieldSource.setOwner(whale);
        vm.startPrank(whale);

        // as whale, approve our yieldsource to take our gmx tokens
        uint256 amount = pxGMXToken.balanceOf(whale);
        pxGMXToken.approve(address(yieldSource), amount);

        // deposit gmx tokens from whale into yieldsource
        uint256 ourBalance = yieldSource.amountGenerator();
        yieldSource.deposit(amount, false);
        assertEq(pxGMXToken.balanceOf(whale), 0); // whale now has nothing
        assertEq(yieldSource.amountGenerator() - ourBalance, amount); // we gained by `amount`

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
