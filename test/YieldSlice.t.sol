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
        init();
    }

    function testSimple() public {
        vm.startPrank(alice);

        uint256 id1 = slice.nextId();

        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18);
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        assertEq(discounter.discounted(200e18, 1e18), 657008058000000000);
        assertEq(npvToken.balanceOf(alice), 657008058000000000);

        // Not enough yield generated
        vm.expectRevert("YS: npv debt");
        slice.unlockDebtSlice(id1);

        // Advance a few weeks */
        for (uint256 day = 0; day < 100; day += 7) {
            vm.roll(block.number + uint256(0xe000));
            slice.recordData();
        }

        (uint256 nominal, uint256 npv, ) = slice.generated(id1);

        slice.unlockDebtSlice(id1);
        assertEq(generatorToken.balanceOf(alice), before);

        (uint256 nominal1, uint256 npv1, ) = slice.generated(id1);

        vm.roll(uint256(block.number + 0x1000));
        (uint256 nominal2, uint256 npv2, ) = slice.generated(id1);
        assertEq(nominal1, nominal2);
        assertEq(npv1, npv2);

        vm.stopPrank();
    }

    function testUnlockWithNPVTokens() public {
        vm.startPrank(alice);

        uint256 id1 = slice.nextId();

        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18);
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        uint256 npvSliced = 657008058000000000;
        assertEq(discounter.discounted(200e18, 1e18), npvSliced);
        assertEq(npvToken.balanceOf(alice), npvSliced);

        (uint256 nominal, uint256 npv, ) = slice.generated(id1);
        assertEq(npv, 0);

        slice.recordData();

        npvToken.approve(address(slice), npvSliced);
        slice.payDebt(id1, npvSliced);
        slice.unlockDebtSlice(id1);
        assertEq(generatorToken.balanceOf(alice), before);

        vm.stopPrank();
    }

    function testUnlockWithNPVTokensPayExtra() public {
        vm.startPrank(alice);

        uint256 id1 = slice.nextId();

        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18);
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        uint256 npvSliced = 657008058000000000;
        assertEq(discounter.discounted(200e18, 1e18), npvSliced);
        assertEq(npvToken.balanceOf(alice), npvSliced);

        (uint256 nominal, uint256 npv, ) = slice.generated(id1);
        assertEq(npv, 0);

        slice.recordData();

        uint256 extra = 1e18;
        yieldToken.approve(address(slice), extra);
        slice.mintFromYield(alice, extra);
        assertEq(IERC20(npvToken).balanceOf(alice), npvSliced + extra);

        npvToken.approve(address(slice), npvSliced + extra);
        uint256 npvBefore = npvToken.balanceOf(alice);
        slice.payDebt(id1, npvSliced + extra);
        slice.unlockDebtSlice(id1);
        uint256 npvAfter = npvToken.balanceOf(alice);
        assertEq(generatorToken.balanceOf(alice), before);
        assertEq(npvBefore - npvAfter, npvSliced);

        vm.stopPrank();
    }

    function testUnlockWithNPVTokensCreditSlice() public {

        uint256 id1 = slice.nextId();
        uint256 id2 = slice.nextId() + 1;

        // Alice sells yield
        vm.startPrank(alice);
        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18);
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);
        uint256 npvSliced = 657008058000000000;
        assertEq(npvToken.balanceOf(alice), npvSliced);
        npvToken.transfer(bob, npvSliced);
        vm.stopPrank();

        // Bob buys yield
        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), npvSliced);
        npvSwap.swapNPVForSlice(npvSliced);
        (, , , uint256 npvEntitled, ) = slice.creditSlices(id2);
        vm.stopPrank();

        assertEq(discounter.discounted(200e18, 1e18), npvSliced);
        (uint256 nominal1, uint256 npv1, ) = slice.generated(id1);
        assertEq(npv1, 0);

        slice.recordData();
        vm.roll(block.number + 100);

        {
            (uint256 nominal2, uint256 npv2, ) = slice.generated(id1);
            assertEq(npv2, 990000000000000);
            (uint256 creditNominal2, uint256 creditNpv2, ) = slice.generatedCredit(id2);
            assertEq(creditNpv2, 989999999999952);

            uint256 remaining = npvSliced - npv2;
            assertEq(remaining, 656018058000000000);

            vm.startPrank(alice);
            yieldToken.approve(address(slice), remaining);
            slice.mintFromYield(alice, remaining);
            assertEq(npvToken.balanceOf(alice), remaining);
            npvToken.approve(address(slice), remaining);
            slice.payDebt(id1, remaining);
            slice.unlockDebtSlice(id1);
            vm.stopPrank();
        }

        {
            (uint256 nominal, uint256 npv, uint256 refund) = slice.generated(id1);
            assertEq(nominal, 990000000000000);
            assertEq(npv, 990000000000000);
            assertEq(refund, 0);
            (uint256 creditNominal, uint256 creditNpv, uint256 claimable) = slice.generatedCredit(id2);
            assertEq(creditNominal, 650447877419999972);
            assertEq(creditNpv,     650447877419999972);
            assertEq(claimable,     650447877419999972);
        }


        {
            slice.recordData();
            vm.roll(block.number + slice.GENERATION_PERIOD());

            (uint256 creditNominal1, uint256 creditNpv1, uint256 claimable1) = slice.generatedCredit(id2);

            slice.recordData();
            vm.roll(block.number + slice.GENERATION_PERIOD());

            (uint256 creditNominal2, uint256 creditNpv2, uint256 claimable2) = slice.generatedCredit(id2);

            assertEq(creditNominal1, creditNominal2);
            assertEq(creditNpv1, creditNpv2);
            assertEq(claimable1, claimable2);

            assertEq(creditNpv1, npvSliced);
            assertTrue(creditNominal1 > npvSliced);
            assertClose(creditNominal1, npvSliced, npvSliced / 100);
            assertEq(creditNominal1, claimable1);
            assertEq(creditNominal1, 659312192166623331);
        }
    }

    function testRefund() public {
        uint256 id1 = slice.nextId();
        uint256 id2 = slice.nextId() + 1;

        // Alice sells yield
        vm.startPrank(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 10e18);
        (, , , , , , uint256 npvOwed) = slice.debtSlices(id1);
        npvToken.transfer(bob, npvOwed);
        vm.stopPrank();

        // Bob buys yield
        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), npvOwed);
        npvSwap.swapNPVForSlice(npvOwed);
        (, , , uint256 npvEntitled, ) = slice.creditSlices(id2);
        vm.stopPrank();

        {
            (uint256 nominalDebt1, uint256 npvDebt1, uint256 refund1) = slice.generated(id1);
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

        vm.roll(block.number + 10);

        {
            (uint256 nominalDebt2, uint256 npvDebt2, uint256 refund2) = slice.generated(id1);
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

        vm.roll(block.number + 7 * 7200);

        {
            (uint256 nominalDebt3, uint256 npvDebt3, uint256 refund3) = slice.generated(id1);
            (uint256 nominalCredit3, uint256 npvCredit3, uint256 claimable3) = slice.generatedCredit(id2);

            assertTrue(npvDebt3 < nominalDebt3);
            assertEq(nominalDebt3, 504090000000000000);
            assertEq(npvDebt3, 502328329268208613);
            assertEq(refund3, 0);

            assertTrue(npvCredit3 < nominalCredit3);
            assertEq(nominalCredit3, 504089999999975746);
            assertEq(npvCredit3, 502328329268184443);
            assertEq(claimable3, 504089999999975746);
        }

        vm.roll(block.number + 7 * 7200);

        {
            (uint256 nominalDebt4, uint256 npvDebt4, uint256 refund4) = slice.generated(id1);
            (uint256 nominalCredit4, uint256 npvCredit4, uint256 claimable4) = slice.generatedCredit(id2);

            assertTrue(npvDebt4 < nominalDebt4);
            assertEq(nominalDebt4, 659856873657370411);
            assertEq(npvDebt4,     npvOwed);
            assertEq(npvDebt4,     657008058000000000);
            assertEq(refund4,      348233126342629589);

            assertTrue(npvCredit4 < nominalCredit4);
            assertEq(nominalCredit4, 659856873657370497);
            assertEq(npvCredit4,     npvEntitled);
            assertEq(npvCredit4,     657008058000000000);
            assertEq(claimable4,     659856873657370497);

            vm.prank(alice);
            uint256 aliceBefore = yieldToken.balanceOf(alice);
            slice.unlockDebtSlice(id1);
            uint256 aliceAfter = yieldToken.balanceOf(alice);
            assertEq(aliceAfter - aliceBefore, refund4, "refund");

            vm.prank(bob);
            uint256 bobBefore = yieldToken.balanceOf(bob);
            slice.claim(id2);
            uint256 bobAfter = yieldToken.balanceOf(bob);
            assertEq(bobAfter - bobBefore, claimable4, "claimable");
        }
    }

    function testSliceCredit() public  {
        uint256 id1 = slice.nextId();

        vm.startPrank(alice);
        uint256 before1 = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, alice, 200e18, 1e18);
        uint256 afterVal1 = generatorToken.balanceOf(alice);
        assertEq(before1 - afterVal1, 200e18);
        vm.roll(block.number + 0x2000);
        npvToken.transfer(bob, 5e17);
        vm.stopPrank();

        uint256 id2 = slice.nextId();

        vm.startPrank(bob);
        npvToken.approve(address(npvSwap), 5e17);
        npvSwap.swapNPVForSlice(5e17);
        vm.roll(block.number + 0x8000);
        uint256 before2 = yieldToken.balanceOf(bob);

        slice.claim(id2);
        uint256 afterVal2 = yieldToken.balanceOf(bob);
        assertEq(afterVal2 - before2, 249365282518334223);
        vm.roll(block.number + 0xf000);

        uint256 before3 = yieldToken.balanceOf(bob);
        slice.claim(id2);
        uint256 afterVal3 = yieldToken.balanceOf(bob);

        assertEq(afterVal3 - before3, 252743433795569647);
        assertEq(afterVal3 - before2, 502108716313903870);
        (uint256 nominal3, uint256 npv3, uint256 claimable3) = slice.generatedCredit(id2);
        assertEq(npv3, 5e17);

        vm.stopPrank();
    }

    function testComputePVAndNominal() public {
        uint256 pv = discounter.pv(500, 1e17);
        assertEq(pv, 77875209331343579);

        uint256 nominal = discounter.nominal(500, pv);
        assertEq(nominal, 99999999999999445);
        assertClose(nominal, 1e17, 1e6);
    }
}
