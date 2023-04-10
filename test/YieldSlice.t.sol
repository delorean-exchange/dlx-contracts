// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./BaseTest.sol";
import "./helpers/FakeToken.sol";
import "./helpers/FakeYieldSource.sol";
import "../src/tokens/NPVToken.sol";
import "../src/core/YieldSlice.sol";
import "../src/core/NPVSwap.sol";
import "../src/data/Discounter.sol";
import "../src/data/YieldData.sol";

contract YieldSliceTest is BaseTest {
    function setUp() public {
    }

    function debtSliceNPVDebt(uint256 id) internal view returns (uint256) {
        ( , , , , , uint256 npvDebt, ) = slice.debtSlices(id);
        return npvDebt;
    }

    function creditSliceNPVCredit(uint256 id) internal view returns (uint256) {
        ( , , uint256 npvCredit, , , , ) = slice.creditSlices(id);
        return npvCredit;
    }

    function testSimpleSale() public {
        init(10000000000);
        discounter.setMaxDays(1440);

        vm.startPrank(alice);

        uint256 id1 = slice.nextId();

        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        assertEq(discounter.discounted(200e18, 1e18), 884433656000000000);
        assertEq(npvToken.balanceOf(alice), 884433656000000000);
        assertEq(debtSliceNPVDebt(id1), 884433656000000000);

        vm.expectRevert("YS: npv debt");
        slice.unlockDebtSlice(id1);

        for (uint256 day = 0; day < 100; day += 7) {
            vm.warp(block.timestamp + 7 days);
            slice.recordData();
        }
        vm.expectRevert("YS: npv debt");
        slice.unlockDebtSlice(id1);

        for (uint256 day = 0; day < 100; day += 7) {
            vm.warp(block.timestamp + 7 days);
            slice.recordData();
        }
        vm.expectRevert("YS: npv debt");
        slice.unlockDebtSlice(id1);

        for (uint256 day = 0; day < 1240; day += 7) {
            vm.warp(block.timestamp + 7 days);
            slice.recordData();
        }

        slice.unlockDebtSlice(id1);
        assertEq(generatorToken.balanceOf(alice), before);

        slice.harvest();

        (uint256 nominal1, uint256 npv1, uint256 refund1) = slice.generatedDebt(id1);

        assertTrue(yieldToken.balanceOf(address(slice)) > npvToken.balanceOf(alice),
                   "nominal should exceed npv");
        assertTrue(yieldToken.balanceOf(address(slice)) > 1e18,
                   "nominal should exceed sold");
        assertEq(yieldToken.balanceOf(address(slice)), 1239713207999306393);

        console.log(yieldToken.balanceOf(address(slice)) + refund1);
        console.log(yieldToken.balanceOf(address(slice)));
        console.log(nominal1);
        assertClose(yieldToken.balanceOf(address(slice)), nominal1, 1e12);
        assertEq(npv1, 884433656000000000);
        assertEq(refund1, 18270792000693607);

        vm.warp(uint256(block.timestamp + 0x1000));
        (uint256 nominal2, uint256 npv2, ) = slice.generatedDebt(id1);
        assertEq(nominal1, nominal2);
        assertEq(npv1, npv2);

        vm.stopPrank();
    }

    function testUnlockWithNPVTokens() public {
        init();

        vm.startPrank(alice);

        uint256 id1 = slice.nextId();

        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        uint256 npvSliced = 657008058000000000;
        assertEq(discounter.discounted(200e18, 1e18), npvSliced);
        assertEq(npvToken.balanceOf(alice), npvSliced);

        ( , uint256 npv, ) = slice.generatedDebt(id1);
        assertEq(npv, 0);

        slice.recordData();

        npvToken.approve(address(slice), npvSliced);
        slice.payDebt(id1, npvSliced);
        slice.unlockDebtSlice(id1);
        assertEq(generatorToken.balanceOf(alice), before);

        vm.stopPrank();
    }

    function testUnlockWithNPVTokensPayExtra() public {
        init();

        vm.startPrank(alice);

        uint256 id1 = slice.nextId();

        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        uint256 npvSliced = 657008058000000000;
        assertEq(discounter.discounted(200e18, 1e18), npvSliced);
        assertEq(npvToken.balanceOf(alice), npvSliced);

        ( , uint256 npv, ) = slice.generatedDebt(id1);
        assertEq(npv, 0);

        slice.recordData();

        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));

        assertEq(IERC20(npvToken).balanceOf(alice), 2 * npvSliced);
        uint256 extra = npvSliced;

        npvToken.approve(address(slice), npvSliced + extra);
        uint256 npvBefore = npvToken.balanceOf(alice);
        slice.payDebt(id1, npvSliced + extra);
        slice.unlockDebtSlice(id1);
        uint256 npvAfter = npvToken.balanceOf(alice);
        assertEq(generatorToken.balanceOf(alice), before - 200e18);
        assertEq(npvBefore - npvAfter, npvSliced);

        vm.stopPrank();
    }

    function testUnlockWithNPVTokensCreditSlice() public {
        init();

        uint256 id1 = slice.nextId();
        uint256 id2 = slice.nextId() + 1;

        // Alice sells yield
        vm.startPrank(alice);
        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);
        uint256 npvSliced = 657008058000000000;
        assertEq(npvToken.balanceOf(alice), npvSliced);
        npvToken.transfer(bob, npvSliced);
        vm.stopPrank();

        // Bob buys yield
        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), npvSliced);
        npvSwap.swapNPVForSlice(bob, npvSliced, new bytes(0));
        vm.stopPrank();

        assertEq(discounter.discounted(200e18, 1e18), npvSliced);
        ( , uint256 npv1, ) = slice.generatedDebt(id1);
        assertEq(npv1, 0);

        slice.recordData();
        vm.warp(block.timestamp + 100);

        {
            ( , uint256 npv2, ) = slice.generatedDebt(id1);
            assertEq(npv2, 990000000000000);
            ( , uint256 creditNpv2, ) = slice.generatedCredit(id2);
            assertEq(creditNpv2, 989999999999952);

            uint256 remaining = npvSliced - npv2;
            assertEq(remaining, 656018058000000000);

            vm.startPrank(alice);

            // Get some more NPV tokens
            generatorToken.approve(address(npvSwap), 200e18);
            npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
            assertTrue(npvToken.balanceOf(alice) > remaining);

            npvToken.approve(address(slice), remaining);
            slice.payDebt(id1, remaining);
            slice.unlockDebtSlice(id1);
            vm.stopPrank();
        }

        {
            slice.recordData();
            vm.warp(block.timestamp + discounter.DISCOUNT_PERIOD());

            (uint256 creditNominal1, uint256 creditNpv1, uint256 claimable1) = slice.generatedCredit(id2);

            slice.recordData();
            vm.warp(block.timestamp + discounter.DISCOUNT_PERIOD());

            (uint256 creditNominal2, uint256 creditNpv2, uint256 claimable2) = slice.generatedCredit(id2);

            assertEq(creditNominal1, creditNominal2);
            assertEq(creditNpv1, creditNpv2);
            assertEq(claimable1, claimable2);
            assertEq(claimable1, 657336726363181590);

            assertEq(creditNpv1, npvSliced);
            assertTrue(creditNominal1 > npvSliced);
            assertClose(creditNominal1, npvSliced, npvSliced / 100);
            assertEq(creditNominal1, claimable1);
            assertEq(creditNominal1, 657336726363181590);
        }
    }

    function testRefund() public {
        init();

        uint256 id1 = slice.nextId();
        uint256 id2 = slice.nextId() + 1;

        // Alice sells yield
        vm.startPrank(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 10e18, new bytes(0));
        (, , , , , uint256 npvOwed, ) = slice.debtSlices(id1);
        npvToken.transfer(bob, npvOwed);
        vm.stopPrank();

        // Bob buys yield
        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), npvOwed);
        npvSwap.swapNPVForSlice(bob, npvOwed, new bytes(0));
        (, , uint256 npvEntitled, , , , ) = slice.creditSlices(id2);
        vm.stopPrank();

        {
            (uint256 nominalDebt1, uint256 npvDebt1, uint256 refund1) = slice.generatedDebt(id1);
            (uint256 nominalCredit1, uint256 npvCredit1, uint256 claimable1) = slice.generatedCredit(id2);
            assertEq(npvOwed, 657008058000000000);
            assertEq(npvEntitled, 657008058000000000);
            assertEq(nominalDebt1, 0);
            assertEq(npvDebt1, 0);
            assertEq(refund1, 0);
            assertEq(nominalCredit1, 0);
            assertEq(npvCredit1, 0);
            assertEq(claimable1, 0);
        }

        vm.warp(block.timestamp + 10);

        {
            (uint256 nominalDebt2, uint256 npvDebt2, uint256 refund2) = slice.generatedDebt(id1);
            (uint256 nominalCredit2, uint256 npvCredit2, uint256 claimable2) = slice.generatedCredit(id2);

            assertEq(npvDebt2, nominalDebt2);
            assertEq(nominalDebt2, 90000000000000);
            assertEq(npvDebt2, 90000000000000);
            assertEq(refund2, 0);

            assertEq(npvCredit2, nominalCredit2);
            assertEq(npvCredit2, claimable2);
            assertEq(npvCredit2, 89999999999995);
            assertEq(nominalCredit2, 89999999999995);
            assertEq(claimable2, 89999999999995);
        }

        vm.warp(block.timestamp + 7 * 7200);

        {
            (uint256 nominalDebt3, uint256 npvDebt3, uint256 refund3) = slice.generatedDebt(id1);
            (uint256 nominalCredit3, uint256 npvCredit3, uint256 claimable3) = slice.generatedCredit(id2);

            assertTrue(npvDebt3 <= nominalDebt3, "debt npv < nominal 3");
            assertEq(nominalDebt3, 504090000000000000);
            assertEq(npvDebt3, 504090000000000000);
            assertEq(refund3, 0);

            assertTrue(npvCredit3 <= nominalCredit3, "credit npv <= nominal 3");
            assertEq(nominalCredit3, 504089999999975747);
            assertEq(npvCredit3, 504089999999975747);
            assertEq(claimable3, 504089999999975747);
        }

        vm.warp(block.timestamp + 7 * 7200);

        {
            (uint256 nominalDebt4, uint256 npvDebt4, uint256 refund4) = slice.generatedDebt(id1);
            (uint256 nominalCredit4, uint256 npvCredit4, uint256 claimable4) = slice.generatedCredit(id2);

            assertTrue(npvDebt4 < nominalDebt4, "debt npv < nominal 4");
            assertEq(nominalDebt4, 657336726363181590);
            assertEq(npvDebt4,     npvOwed);
            assertEq(npvDebt4,     657008058000000000);
            assertEq(refund4,      350753273636818410);

            assertTrue(npvCredit4 < nominalCredit4, "credit npv < nominal 4");
            assertEq(nominalCredit4, 657336726363181590);
            assertEq(npvCredit4,     npvEntitled);
            assertEq(npvCredit4,     657008058000000000);
            assertEq(claimable4,     657336726363181590);

            uint256 aliceBefore = yieldToken.balanceOf(alice);
            vm.prank(alice);
            slice.unlockDebtSlice(id1);
            uint256 aliceAfter = yieldToken.balanceOf(alice);
            assertEq(aliceAfter - aliceBefore, refund4, "refund");

            uint256 bobBefore = yieldToken.balanceOf(bob);
            vm.prank(bob);
            slice.claim(id2, 0);
            uint256 bobAfter = yieldToken.balanceOf(bob);
            assertEq(bobAfter - bobBefore, claimable4, "claimable");
        }
    }

    function testSliceCredit() public  {
        init();

        vm.startPrank(alice);
        uint256 before1 = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
        uint256 afterVal1 = generatorToken.balanceOf(alice);
        assertEq(before1 - afterVal1, 200e18);
        vm.warp(block.timestamp + 0x2000);
        npvToken.transfer(bob, 5e17);
        vm.stopPrank();

        uint256 id2 = slice.nextId();

        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), 5e17);
        npvSwap.swapNPVForSlice(bob, 5e17, new bytes(0));
        vm.warp(block.timestamp + 0x8000);
        uint256 before2 = yieldToken.balanceOf(bob);

        slice.claim(id2, 0);
        uint256 afterVal2 = yieldToken.balanceOf(bob);
        assertEq(afterVal2 - before2, 311700895455364638);

        vm.warp(block.timestamp + 0xf000);

        uint256 before3 = yieldToken.balanceOf(bob);
        slice.claim(id2, 0);
        uint256 afterVal3 = yieldToken.balanceOf(bob);

        assertEq(afterVal3 - before3, 250884842544197042);
        assertEq(afterVal3 - before2, 562585737999561680);

        ( , uint256 npv3, uint256 claimable3) = slice.generatedCredit(id2);
        assertEq(npv3, 5e17);
        assertEq(claimable3, 0);

        vm.stopPrank();
    }

    function testReceiveNPV() public  {
        init();

        vm.startPrank(alice);
        uint256 before1 = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
        uint256 afterVal1 = generatorToken.balanceOf(alice);
        assertEq(before1 - afterVal1, 200e18);
        vm.warp(block.timestamp + 0x2000);
        npvToken.transfer(bob, 5e17);
        vm.stopPrank();

        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), 5e17);
        uint256 id2 = npvSwap.swapNPVForSlice(bob, 5e17, new bytes(0));

        {
            (, , uint256 claimable) = slice.generatedCredit(id2);
            assertEq(claimable, 62335612937030415);
        }

        vm.warp(block.timestamp + 0x8000);
        uint256 before2 = yieldToken.balanceOf(bob);

        slice.claim(id2, 0);
        uint256 afterVal2 = yieldToken.balanceOf(bob);
        assertEq(afterVal2 - before2, 311700895455364638);

        assertEq(npvToken.balanceOf(bob), 0);
        slice.receiveNPV(id2, bob, 1e17);
        assertEq(npvToken.balanceOf(bob), 1e17);
        assertEq(npvToken.balanceOf(address(slice)), 4e17);

        vm.warp(block.timestamp + 0xf0000);

        {
            (uint256 nominal3, uint256 npv3, uint256 claimable3) = slice.generatedCredit(id2);

            assertEq(npv3, creditSliceNPVCredit(id2));
            assertEq(npv3, 150634717481665777);
            assertEq(claimable3, 150710072517924739);
            assertEq(nominal3, 150710072517924739);
            assertEq(npvToken.totalSupply(), 657008058000000000);

            uint256 before3 = yieldToken.balanceOf(bob);
            slice.claim(id2, 0);
            uint256 delta = yieldToken.balanceOf(bob) - before2;

            assertClose(delta, 46e16, 1e16);
            assertEq(delta, 462410967973289377);
            assertEq(npvToken.totalSupply(), 257008058000000000);
        }

        vm.warp(block.timestamp + 0xf000);

        {
            ( , , uint256 claimable4) = slice.generatedCredit(id2);
            assertEq(claimable4, 0);
            assertEq(npvToken.totalSupply(), 257008058000000000);
            assertEq(npvToken.balanceOf(bob), 1e17);
            assertEq(npvToken.balanceOf(alice), npvToken.totalSupply() - 1e17);
        }

        vm.stopPrank();
    }

    function testComputePVAndNominal() public {
        init();

        uint256 pv = discounter.pv(500, 1e17);
        assertEq(pv, 77875209331343579);

        uint256 nominal = discounter.nominal(500, pv);
        assertEq(nominal, 99999999999999445);
        assertClose(nominal, 1e17, 1e6);
    }

    function testFees() public {
        init();

        slice.setTreasury(treasury);
        slice.setDebtFee(5_0);
        slice.setCreditFee(10_0);

        vm.startPrank(alice);
        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18, new bytes(0));
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);
        uint256 npv = discounter.discounted(200e18, 1e18);
        assertEq(npv, 657008058000000000);
        uint256 expectedDebtFee = ((1e18 - npv) * 5_0) / 100_0;
        assertEq(npvToken.balanceOf(alice), npv - expectedDebtFee);
        assertEq(npvToken.balanceOf(treasury), expectedDebtFee);
        npvToken.transfer(bob, 5e17);
        vm.stopPrank();

        uint256 id2 = slice.nextId();

        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), 5e17);
        npvSwap.swapNPVForSlice(bob, 5e17, new bytes(0));

        vm.warp(block.timestamp + 0x8000);

        uint256 before2 = yieldToken.balanceOf(bob);
        slice.claim(id2, 0);
        uint256 afterVal2 = yieldToken.balanceOf(bob);
        uint256 total2 = 249365282518334223;
        assertEq(afterVal2 - before2, total2 - (total2 * 10_0) / (100_0));

        vm.warp(block.timestamp + 0xf000);

        uint256 before3 = yieldToken.balanceOf(bob);
        slice.claim(id2, 0);
        uint256 afterVal3 = yieldToken.balanceOf(bob);

        uint256 total3 = 250884842544197042;
        uint256 total4 = 500250125062531265;
        assertEq(afterVal3 - before3, total3 - (total3 * 10_0) / (100_0));
        assertEq(afterVal3 - before2, total4 - (total4 * 10_0) / (100_0));

        ( , uint256 npv3, uint256 claimable3) = slice.generatedCredit(id2);
        assertEq(npv3, 45e16);
        assertEq(claimable3, 0);

        vm.stopPrank();

        assertEq(npvToken.balanceOf(treasury), expectedDebtFee + 5e16);
    }
}
