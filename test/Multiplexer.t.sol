// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FakeYieldSource } from "./helpers/FakeYieldSource.sol";

import { BaseTest } from "./BaseTest.sol";
import { NPVToken } from "../src/tokens/NPVToken.sol";
import { YieldSlice } from "../src/core/YieldSlice.sol";
import { NPVSwap } from "../src/core/NPVSwap.sol";
import { Discounter } from "../src/data/Discounter.sol";
import { YieldData } from "../src/data/YieldData.sol";
import { Multiplexer } from "../src/mx/Multiplexer.sol";

contract MultiplexerTest is BaseTest {

    FakeYieldSource public source2;
    NPVToken public npvToken2;
    NPVSwap public npvSwap2;
    YieldSlice public slice2;
    YieldData public dataDebt2;
    YieldData public dataCredit2;
    Discounter public discounter2;

    IERC20 public generatorToken2;
    IERC20 public yieldToken2;

    function init2() public {
        uint256 yieldPerSecond = 20000000000000;
        source2 = new FakeYieldSource(yieldPerSecond);
        generatorToken2 = source.generatorToken();
        yieldToken2 = source.yieldToken();
        dataDebt2 = new YieldData(20);
        dataCredit2 = new YieldData(20);

        discounter2 = new Discounter(1e13,
                                     500 * 30,
                                     360,
                                     18,
                                     30 days);

        slice2 = new YieldSlice("yFAKE2",
                               address(source2),
                               address(dataDebt2),
                               address(dataCredit2),
                               address(discounter2),
                               1e9);

        npvToken2 = slice2.npvToken();

        source2.setOwner(address(slice2));
        dataDebt2.setWriter(address(slice2));
        dataCredit2.setWriter(address(slice2));
    }

    function testMultiplexer() public {
        init();
        init2();

        console.log("testMultiplexer");

        Multiplexer mx = new Multiplexer("ymxAAA", 1 days);

        // Lock yield to mint fFAKE2
        source2.mintBoth(alice, 10e18);

        vm.startPrank(alice);
        uint256 amountGenerator = 5e18;
        uint256 amountYield = 1e18;

        console.log("Approving:    ", alice, address(generatorToken2), address(slice2));
        generatorToken2.approve(address(slice2), amountGenerator);

        uint256 id1 = slice2.debtSlice(alice, alice, amountGenerator, amountYield, "");

        uint256 npvSliced = npvToken.balanceOf(alice);
        console.log("npvSliced", npvSliced);
        
        vm.stopPrank();
    }
}
