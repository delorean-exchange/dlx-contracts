// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
 
import { BaseTest } from "./BaseTest.sol";
import { GMDYieldSource } from "../src/sources/GMDYieldSource.sol";
import { IGMDVault } from "../src/interfaces/gmd/IGMDVault.sol";
import { YieldData } from "../src/data/YieldData.sol";

contract GMDYieldSourceTest is BaseTest {
    uint256 arbitrumForkFrom97559408;

    GMDYieldSource yieldSource;
    IERC20 gmdToken;
    IGMDVault gmdVault;
    
    address whale = 0x93A356288E202dB0c9533eA384ec8D4B94270806;

    function setUp() public {
        init();
        vm.selectFork(vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 97559408));

        yieldSource = new GMDYieldSource();
        gmdToken = yieldSource.gmdToken();
        gmdVault = yieldSource.gmdVault();
    }
    
    function testEnterAndLeave() public {
        yieldSource.setOwner(whale);
        vm.startPrank(whale);
        vm.deal(whale, 134324235);

        // deposit eth & check that we got back gmd
        assert(whale.balance > 4242);
        uint256 old = gmdToken.balanceOf(whale);
        gmdVault.enterETH{value: 4242}(1);
        uint256 delta = gmdToken.balanceOf(whale) - old;
        assertEq(delta, 3923);

        // allow the yields to accrue
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);

        // unstake like 10% of our gmd
        uint256 oldEth = whale.balance;
        gmdVault.leaveETH(gmdToken.balanceOf(whale) / 10, 1);
        uint256 deltaEth = whale.balance - oldEth;
        assertEq(deltaEth, 8033624120389000637);

        vm.stopPrank();
    }

    function testGMD() public {
        yieldSource.setOwner(whale);
        vm.startPrank(whale);
        
        uint256 ethAmount = 132343243243242212;
        vm.deal(whale, ethAmount);

        // deposit eth & check that we got back gmd
        assert(whale.balance >= ethAmount);
        uint256 old = gmdToken.balanceOf(whale);
        gmdVault.enterETH{value: ethAmount}(1);
        uint256 gmd = gmdToken.balanceOf(whale) - old;
        assertEq(gmd, 122425808812368556);

        // approve yieldsource to take whale's gmd tokens
        gmdToken.approve(address(yieldSource), gmd);

        // deposit tokens from whale into yieldsource
        old = yieldSource.amountGenerator();
        yieldSource.deposit(gmd, false);
        assertEq(yieldSource.amountGenerator() - old, gmd); // we gained by `gmd`

        // allow the yields to accrue
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);

        // harvest the yield & ensure whale got the eth
        old = yieldSource.yieldToken().balanceOf(whale);
        yieldSource.harvest();
        uint256 delta = yieldSource.yieldToken().balanceOf(whale) - old;
        assertEq(delta, 601285511537);

        // withdraw some gmx tokens as whale
        old = gmdToken.balanceOf(whale);
        uint256 avail = yieldSource.amountGenerator();
        yieldSource.withdraw(avail / 2, false, whale);
        assertEq(gmdToken.balanceOf(whale) - old, avail / 2);

        vm.stopPrank();
    }
}
