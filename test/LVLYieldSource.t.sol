// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";
import { LVLYieldSource, LVLConstants } from "../src/sources/LVLYieldSource.sol";
import { ILvlStaking } from "../src/interfaces/lvl/ILvlStaking.sol";
import { ILvlRouter } from "../src/interfaces/lvl/ILvlRouter.sol";
import { ILvlPool } from "../src/interfaces/lvl/ILvlPool.sol";

contract LVLYieldSourceTest is BaseTest {
    LVLYieldSource yieldSource;
    ILvlStaking lvlStaking;
    ILvlRouter lvlRouter;
    ILvlPool lvlPool;
    IERC20 lvlToken;

    address whale = 0x804bbb7a06c0934571aAD137360215ef1335e6A1;

    function setUp() public {
        init();
        vm.selectFork(vm.createFork(vm.envString("BNB_MAINNET_RPC_URL"), 28106807));

        yieldSource = new LVLYieldSource(LVLConstants.NETWORK_BNB);
        lvlStaking = yieldSource.lvlStaking();
        lvlRouter = yieldSource.lvlRouter();
        lvlPool = yieldSource.lvlPool();
        lvlToken = yieldSource.lvlToken();
    }

    function testLvlToken() public {
        yieldSource.setOwner(whale);
        vm.startPrank(whale);

        // as whale, approve our yieldsource to take our lvl tokens
        uint256 amount = lvlToken.balanceOf(whale);
        lvlToken.approve(address(yieldSource), amount);

        // deposit lvl tokens from whale into yieldsource
        uint256 stakedAmount = 0;
        {
            uint256 old = yieldSource.amountGenerator();
            yieldSource.deposit(amount, false);
            assertEq(lvlToken.balanceOf(whale), 0); // whale now has nothing

            uint256 taxAmount = amount * lvlStaking.stakingTax() / lvlStaking.STAKING_TAX_PRECISION();
            stakedAmount = amount - taxAmount;
            assertEq(yieldSource.amountGenerator() - old, stakedAmount);
        }

        // allow the yields to accrue
        vm.warp(block.timestamp + 5 minutes);

        // harvest the yield, ensure whale got the weth
        {
            uint256 old = yieldSource.yieldToken().balanceOf(whale);
            yieldSource.harvest();
            assertEq(yieldSource.yieldToken().balanceOf(whale) - old, 11876933233527429);
        }

        // withdraw lvl tokens as whale
        yieldSource.withdraw(stakedAmount, false, whale);
        assertEq(lvlToken.balanceOf(whale), stakedAmount);

        vm.stopPrank();
    }
}
