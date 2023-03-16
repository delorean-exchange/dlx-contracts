// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./BaseTest.sol";
import "../src/sources/StakedGLPYieldSource.sol";
import "../src/interfaces/IGLPRewardTracker.sol";
import "../src/data/YieldData.sol";

contract StakedGLPYieldSourceTest is BaseTest {
    uint256 arbitrumForkFrom61289647;

    address glpWhale = 0x93006877903Fe83d8179dA661e72e4F9DB23Eb66;

    StakedGLPYieldSource glpYieldSource;
    IGLPRewardTracker tracker;

    IERC20 stakedGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

    function setUp() public {
        arbitrumForkFrom61289647 = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 61289647);
    }

    function testForkArbitrum() public {
        vm.selectFork(arbitrumForkFrom61289647);
        assertEq(stakedGLP.balanceOf(glpWhale), 1000000000000000000);
    }
}
