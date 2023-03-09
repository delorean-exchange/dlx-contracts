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
        npvSwap.lockForNPV(alice, 200e18, 1e18);
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        assertEq(discounter.discounted(200e18, 1e18), 657008058000000000);
        assertEq(npvToken.balanceOf(alice), 657008058000000000);

        // Not enough yield generated, and safe transfer fails due to lacking approval
        vm.expectRevert("ERC20: insufficient allowance");
        slice.unlockDebtSlice(id1);

        // Advance a few weeks */
        for (uint256 day = 0; day < 100; day += 7) {
            vm.roll(block.number + uint256(0xe000));
            slice.recordData();
        }

        (uint256 nominal, uint256 npv) = slice.generated(id1);

        slice.unlockDebtSlice(id1);
        assertEq(generatorToken.balanceOf(alice), before);

        (uint256 nominal1, uint256 npv1) = slice.generated(id1);

        vm.roll(uint256(block.number + 0x1000));
        (uint256 nominal2, uint256 npv2) = slice.generated(id1);
        assertEq(nominal1, nominal2);
        assertEq(npv1, npv2);

        vm.stopPrank();
    }

    function testUnlockWithNPVTokens() public {
        vm.startPrank(alice);

        uint256 id1 = slice.nextId();

        uint256 before = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, 200e18, 1e18);
        uint256 afterVal = generatorToken.balanceOf(alice);
        assertEq(before - afterVal, 200e18);

        uint256 npvSliced = 657008058000000000;
        assertEq(discounter.discounted(200e18, 1e18), npvSliced);
        assertEq(npvToken.balanceOf(alice), npvSliced);

        (uint256 nominal, uint256 npv) = slice.generated(id1);
        assertEq(npv, 0);

        slice.recordData();

        npvToken.approve(address(slice), npvSliced);
        slice.unlockDebtSlice(id1);
        assertEq(generatorToken.balanceOf(alice), before);

        vm.stopPrank();
    }

    function testSliceCredit() public  {
        uint256 id1 = slice.nextId();

        vm.startPrank(alice);
        uint256 before1 = generatorToken.balanceOf(alice);
        generatorToken.approve(address(npvSwap), 200e18);
        npvSwap.lockForNPV(alice, 200e18, 1e18);
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

        slice.claimCreditSlice(id2);
        uint256 afterVal2 = yieldToken.balanceOf(bob);
        assertEq(afterVal2 - before2, 249365282518334223);
        vm.roll(block.number + 0xf000);

        uint256 before3 = yieldToken.balanceOf(bob);
        slice.claimCreditSlice(id2);
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
