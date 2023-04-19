// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IGlpAdapter } from "../src/interfaces/jones/IGlpAdapter.sol";
import { IWhitelistController } from "../src/interfaces/jones/IWhitelistController.sol";

import { BaseTest } from "./BaseTest.sol";
import { JonesGLPYieldSource } from "../src/sources/JonesGLPYieldSource.sol";
import { YieldData } from "../src/data/YieldData.sol";

contract JonesGLPYieldSourceTest is BaseTest {
    uint256 arbitrumForkJonesGLP;
    uint256 arbitrumForkJonesGLP2;

    IGlpAdapter adapter = IGlpAdapter(0x42EfE3E686808ccA051A49BCDE34C5CbA2EBEfc1);
    IWhitelistController wl = IWhitelistController(0x2ACc798DA9487fdD7F4F653e04D8E8411cd73e88);
    IERC20 glp = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

    address depositor = 0x0df1cBD74b191aAB67a0c4F1f3c2047Eb251fe41;

    function setUp() public {
        init();
        arbitrumForkJonesGLP = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"),
                                             61648540 - 1);

        arbitrumForkJonesGLP2 = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"),
                                              81645858);
    }

    function testJonesGLPYieldSource() public {
        vm.selectFork(arbitrumForkJonesGLP2);

        address user = 0x9bb98140F36553dB71fe4a570aC0b1401BC61B4F;
        JonesGLPYieldSource source = new JonesGLPYieldSource();
        source.setOwner(user);

        uint256 bal = source.jglp().balanceOf(user);

        vm.startPrank(user);
        source.jglp().approve(address(source), bal - 1);
        source.deposit(bal - 1, false);

        vm.warp(block.timestamp + 0xf00000);
        vm.roll(block.number + 0xf00000);

        // Trigger update rewards values with 1 wei deposit
        source.jglp().approve(address(source), 1);
        source.deposit(1, false);

        uint256 pending = source.amountPending();
        uint256 before = source.weth().balanceOf(address(source));
        source.harvest();
        uint256 delta = source.weth().balanceOf(address(source)) - before;
        assertEq(delta, pending);

        vm.stopPrank();
    }

    function testJonesGLPMisc_2() public {
        vm.selectFork(arbitrumForkJonesGLP2);
        console.log("testJonesGLPMisc_2");

        address user = 0x9bb98140F36553dB71fe4a570aC0b1401BC61B4F;

        JonesGLPYieldSource source = new JonesGLPYieldSource();
        source.setOwner(user);

        vm.startPrank(user);

        {
            uint256 cl = source.router().glpRewardTracker().claimable(user);
            console.log("cl", cl);
            (uint256 a, uint256 b, uint256 c) = source.router().claimRewards();
            console.log("abc", a, b, c);
        }

        source.router().compoundGlpRewards(1e18);

        console.log("==");
        vm.warp(block.timestamp + 0xf00000);
        vm.roll(block.number + 0xf00000);

        {
            uint256 cl = source.router().glpRewardTracker().claimable(user);
            console.log("cl", cl);
            (uint256 a, uint256 b, uint256 c) = source.router().claimRewards();
            console.log("abc", a, b, c);
        }

        vm.stopPrank();
    }

    function disabled_testJonesGLPMisc() public {
        vm.selectFork(arbitrumForkJonesGLP);
        console.log("testJonesGLPYieldSource");

        JonesGLPYieldSource source = new JonesGLPYieldSource();
        source.setOwner(depositor);

        console.log("testJGLP", address(source.jglp()));
        console.log("glp balance", glp.balanceOf(depositor));
        console.log("jglp balance:", IERC20(address(source.jglp())).balanceOf(depositor));

        uint256 amount = 20004077738709392514;

        bool below = adapter.belowCap(amount);
        console.log("wl?", wl.isWhitelistedContract(depositor));

        vm.startPrank(0xc8ce0aC725f914dBf1D743D51B6e222b79F479f1);
        wl.addToWhitelistContracts(depositor);
        vm.stopPrank();

        console.log("wl?", wl.isWhitelistedContract(depositor));
        vm.startPrank(depositor);
        uint256 result = adapter.depositGlp(amount, true);
        console.log("deposit result", result);
        console.log("glp balance after: ", glp.balanceOf(depositor));
        console.log("jglp balance after:", source.jglp().balanceOf(depositor));

        return;

        source.jglp().approve(address(source), 1e6);
        source.deposit(1e6, false);

        console.log("Amount gen:", source.amountGenerator());

        vm.warp(block.timestamp + 0xf00000);
        vm.roll(block.number + 0xf00000);

        console.log("Pending", source.amountPending());

        return;

        source.withdraw(1e6, false, address(depositor));

        return;

        address compounder = address(source.router().rewardCompounder(address(glp)));
        address tracker = address(source.router().rewardTrackers(address(glp)));
        console.log("compounder", compounder);
        console.log("tracker   ", tracker);
        uint256 half = amount / 2;
        source.router().unCompoundGlpRewards(half, depositor);
        console.log("jglp balance after: 3", source.jglp().balanceOf(depositor));
        source.router().compoundGlpRewards(half);
        console.log("jglp balance after: 4", source.jglp().balanceOf(depositor));

        return;

        console.log("claimable", source.router().rewardTrackers(address(glp)).claimable(depositor));

        vm.warp(block.timestamp + 0xf00000);
        vm.roll(block.number + 0xf00000);

        console.log("claimable", source.router().rewardTrackers(address(glp)).claimable(depositor));
        console.log("amount   ", source.router().rewardTrackers(address(glp)).stakedAmounts(depositor));
        console.log("pr       ", source.router().rewardTrackers(address(glp)).distributor().pendingRewards(depositor));

        vm.stopPrank();
    }
}
