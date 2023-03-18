// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "./BaseTest.sol";
import "../src/data/YieldData.sol";

contract YieldDataTest is BaseTest {

    YieldData public data;
    address public user0;

    function setUp() public {
        user0 = createUser(0);
        data = new YieldData(20);
        data.setWriter(user0);
        vm.startPrank(user0);
    }

    function testSimple() public {
        data.record(10e18, 0);
        vm.roll(block.number + 20);
        vm.warp(block.timestamp + 20);
        data.record(10e18, 5000);
        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 20, block.timestamp, 0, 0), 25);
    }

    function testSplitEpoch() public {
        data.record(10e18, 0);
        vm.warp(block.timestamp + 1);
        data.record(20e18, 20000);
        vm.warp(block.timestamp + 7);
        data.record(20e18, 280000);

        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 8, block.timestamp, 0, 0), 1875);
    }

    function testMultipleEpochs() public {
        data.record(10e18, 0);
        vm.warp(block.timestamp + 20);
        data.record(10e18, 5000);

        vm.warp(block.timestamp + 20);
        data.record(10e18, 15000);

        vm.warp(block.timestamp + 20);
        data.record(10e18, 55000);

        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 60, block.timestamp - 40, 0, 0), 25);
        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 40, block.timestamp - 20, 0, 0), 50);
        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 20, block.timestamp, 0, 0), 200);
        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 60, block.timestamp - 20, 0, 0), (25 + 50) >> 1);
        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 50, block.timestamp - 20, 0, 0), 41);
        assertEq(data.yieldPerTokenPerSecond(block.timestamp - 50, block.timestamp - 10, 0, 0), 81);
    }

    function testManyDifferentEpochs() public {
        data.record(10e18, 0);
        uint256 startBlockNumber = block.timestamp;
        for (uint256 i = 0; i < 100; i++) {
            vm.warp(block.timestamp + 20);
            data.record(10e18, (i+1) * (i+1) * 10e2);
        }

        assertEq(data.yieldPerTokenPerSecond(startBlockNumber, startBlockNumber + 20, 0, 0), 5);
        assertEq(data.yieldPerTokenPerSecond(startBlockNumber + 20, startBlockNumber + 40, 0, 0), 15);
        assertEq(data.yieldPerTokenPerSecond(startBlockNumber + 40, startBlockNumber + 60, 0, 0), 25);
        assertEq(data.yieldPerTokenPerSecond(startBlockNumber + 1800, startBlockNumber + 1820, 0, 0), 905);
        assertEq(data.yieldPerTokenPerSecond(startBlockNumber + 200, startBlockNumber + 1820, 0, 0), 505);
    }

    function testValidateStartAndEnd() public {
        data.record(10e18, 0);
        uint256 startBlockNumber = block.timestamp;
        for (uint256 i = 0; i < 100; i++) {
            vm.warp(block.timestamp + 20);
            data.record(10e18, (i+1) * (i+1) * 10e2);
        }

        vm.expectRevert("YD: start must precede end");
        data.yieldPerTokenPerSecond(startBlockNumber + 20, startBlockNumber, 0, 0);
    }
}
