// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";
import { LVLYieldSource, LVLConstants } from "../src/sources/LVLYieldSource.sol";
import { ILvlStaking } from "../src/interfaces/lvl/ILvlStaking.sol";
import { ILvlRouter } from "../src/interfaces/lvl/ILvlRouter.sol";
import { ILvlPool } from "../src/interfaces/lvl/ILvlPool.sol";

contract LVLYieldSourceTest is BaseTest {

    function setUp() public {
        init();
    }

    /*
    function testLvlArbitrum() public {
        vm.selectFork(vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 101889417));
        address whale = ...;
        _testLvlToken(whale, LVLConstants.NETWORK_ARBITRUM, LVLConstants.TOKEN_LVL);
    }

    function testLgoArbitrum() public {
        vm.selectFork(vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 101889417));
        address whale = ...;
        _testLvlToken(whale, LVLConstants.NETWORK_ARBITRUM, LVLConstants.TOKEN_LGO);
    }
    */

    function testLvlBsc() public {
        vm.selectFork(vm.createFork(vm.envString("BNB_MAINNET_RPC_URL"), 28106807));
        _testLvlToken(
            0x804bbb7a06c0934571aAD137360215ef1335e6A1,
            LVLConstants.NETWORK_BNB,
            LVLConstants.TOKEN_LVL);
    }

    function testLgoBsc() public {
        vm.selectFork(vm.createFork(vm.envString("BNB_MAINNET_RPC_URL"), 28106807));
        _testLvlToken(
            0x712A2e08C67cD7153f04FdB3037d4696300921d0,
            LVLConstants.NETWORK_BNB,
            LVLConstants.TOKEN_LGO);
    }

    function _testLvlToken(address whale, uint256 network, uint256 token) internal {
        LVLYieldSource yieldSource = new LVLYieldSource(network, token);
        ILvlStaking lvlStaking = yieldSource.lvlStaking();
        IERC20 lvlToken = yieldSource.generatorToken();

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
            
            stakedAmount = amount;
            if (token == LVLConstants.TOKEN_LVL) {
                stakedAmount -= amount * lvlStaking.stakingTax() / lvlStaking.STAKING_TAX_PRECISION();
            }

            assertEq(yieldSource.amountGenerator() - old, stakedAmount);
        }

        // allow the yields to accrue
        vm.warp(block.timestamp + 5 minutes);

        // harvest the yield, ensure whale got the weth
        {
            uint256 old = yieldSource.yieldToken().balanceOf(whale);
            yieldSource.harvest();
            assert(yieldSource.yieldToken().balanceOf(whale) > old);
        }

        // withdraw lvl tokens as whale
        yieldSource.withdraw(stakedAmount, false, whale);
        assertEq(lvlToken.balanceOf(whale), stakedAmount);

        vm.stopPrank();
    }
}
