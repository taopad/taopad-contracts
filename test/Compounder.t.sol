// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract CompounderTest is ERC20RewardsTest {
    function testCompounderRewards() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        assertTrue(token.isOptin(address(compounder)));

        uint256 rewardBalance = compounder.rewardBalance();

        assertEq(rewardBalance, 0);

        // buy some tokens, distribute and claim.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);

        token.distribute();

        vm.prank(user1);

        token.claim();

        vm.prank(user2);

        token.claim();

        assertGt(rewardToken.balanceOf(user1), 0);
        assertGt(rewardToken.balanceOf(user2), 0);

        // stack in the compounder.
        uint256 balance1 = token.balanceOf(user1);
        uint256 balance2 = token.balanceOf(user2);

        vm.startPrank(user1);
        token.approve(address(compounder), balance1);
        compounder.deposit(balance1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(compounder), balance2);
        compounder.deposit(balance2, user2);
        vm.stopPrank();

        assertGt(compounder.balanceOf(user1), 0);
        assertGt(compounder.balanceOf(user2), 0);
        assertEq(compounder.rewardBalance(), 0);
        assertEq(compounder.totalAssets(), balance1 + balance2);

        // distribute more rewards.
        buyToken(user3, 1 ether);

        token.distribute();

        assertGt(compounder.rewardBalance(), 0);

        // compound the rewards.
        compounder.compound();

        assertEq(compounder.rewardBalance(), 0);
        assertEq(rewardToken.balanceOf(address(compounder)), 0);
        assertEq(IERC20(router.WETH()).balanceOf(address(compounder)), 0);
        assertGt(compounder.totalAssets(), balance1 + balance2);

        // user can now redeem more tokens.
        uint256 shareBalance1 = compounder.balanceOf(user1);
        uint256 shareBalance2 = compounder.balanceOf(user2);

        vm.startPrank(user1);
        compounder.approve(address(compounder), shareBalance1);
        compounder.redeem(shareBalance1, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        compounder.approve(address(compounder), shareBalance2);
        compounder.redeem(shareBalance2, user2, user2);
        vm.stopPrank();

        assertGt(token.balanceOf(user1), balance1);
        assertGt(token.balanceOf(user2), balance2);
        assertApproxEqAbs(compounder.totalAssets(), 0, 1); // account for dust
    }

    function testCompounderDonations() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // buy some tokens.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // stack in the compounder.
        uint256 balance1 = token.balanceOf(user1);
        uint256 balance2 = token.balanceOf(user2);

        vm.startPrank(user1);
        token.approve(address(compounder), balance1);
        compounder.deposit(balance1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(compounder), balance2);
        compounder.deposit(balance2, user2);
        vm.stopPrank();

        // distribute the reward.
        token.distribute();

        vm.prank(user3);

        token.claim();

        uint256 donatorRewardBalance = rewardToken.balanceOf(user3);
        uint256 compounderRewardBalance = compounder.rewardBalance();

        assertGt(donatorRewardBalance, 0);
        assertGt(compounderRewardBalance, 0);

        // make a donation, compound and check.
        vm.prank(user3);

        rewardToken.transfer(address(compounder), donatorRewardBalance);

        assertEq(compounder.rewardBalance(), compounderRewardBalance + donatorRewardBalance);

        compounder.compound();

        assertEq(compounder.rewardBalance(), 0);

        // check everyone can redeem
        uint256 shareBalance1 = compounder.balanceOf(user1);
        uint256 shareBalance2 = compounder.balanceOf(user2);

        vm.startPrank(user1);
        compounder.approve(address(compounder), shareBalance1);
        compounder.redeem(shareBalance1, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        compounder.approve(address(compounder), shareBalance2);
        compounder.redeem(shareBalance2, user2, user2);
        vm.stopPrank();

        assertGt(token.balanceOf(user1), balance1);
        assertGt(token.balanceOf(user2), balance2);
        assertApproxEqAbs(compounder.totalAssets(), 0, 1); // account for dust
    }

    function testSetAutocompoundThreshold() public {
        // autocompound threshold is max value by default.
        assertEq(compounder.autocompoundThreshold(), type(uint256).max);

        // non owner can't set autocompound threshold.
        vm.prank(vm.addr(1));

        vm.expectRevert();

        compounder.setAutocompoundTheshold(1);

        // owner can set it.
        compounder.setAutocompoundTheshold(1);

        assertEq(compounder.autocompoundThreshold(), 1);
    }

    function testAutocompoundDepositExact() public {
        autocompoundDeposit(0);
    }

    function testAutocompoundDepositGreater() public {
        autocompoundDeposit(-1);
    }

    function testFailAutocompoundDepositLesser() public {
        autocompoundDeposit(1);
    }

    function testAutocompoundRedeemExact() public {
        autocompoundRedeem(0);
    }

    function testAutocompoundRedeemGreater() public {
        autocompoundRedeem(-1);
    }

    function testFailAutocompoundRedeemLesser() public {
        autocompoundRedeem(1);
    }

    function autocompoundDeposit(int256 delta) private {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // buy some tokens.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // stack in the compounder.
        uint256 balance1 = token.balanceOf(user1);
        uint256 balance2 = token.balanceOf(user2);
        uint256 balance3 = token.balanceOf(user3);

        vm.startPrank(user1);
        token.approve(address(compounder), balance1);
        compounder.deposit(balance1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(compounder), balance2);
        compounder.deposit(balance2, user2);
        vm.stopPrank();

        // distribute, compound and claim.
        token.distribute();

        compounder.compound();

        vm.prank(user3);

        token.claim();

        // preview how much user1 and 2 can redeem.
        uint256 shareBalance1 = compounder.balanceOf(user1);
        uint256 shareBalance2 = compounder.balanceOf(user2);

        uint256 previewRedeem1 = compounder.previewRedeem(shareBalance1);
        uint256 previewRedeem2 = compounder.previewRedeem(shareBalance2);

        assertGt(previewRedeem1, balance1);
        assertGt(previewRedeem2, balance2);

        // set threshold to exact user3 balance and donate.
        uint256 donationAmount = rewardToken.balanceOf(user3);

        // delta allow to test exact or lesser.
        compounder.setAutocompoundTheshold(uint256(int256(donationAmount) + delta));

        assertEq(compounder.rewardBalance(), 0);

        vm.prank(user3);

        rewardToken.transfer(address(compounder), donationAmount);

        assertEq(compounder.rewardBalance(), donationAmount);

        // deposit with user3, it should autocompound.
        vm.startPrank(user3);
        token.approve(address(compounder), balance3);
        compounder.deposit(balance3, user3);
        vm.stopPrank();

        assertGt(compounder.previewRedeem(shareBalance1), previewRedeem1);
        assertGt(compounder.previewRedeem(shareBalance2), previewRedeem2);

        // everyone should be able to redeem and shares should be 0.
        uint256 shareBalance3 = compounder.balanceOf(user3);

        vm.startPrank(user1);
        compounder.approve(address(compounder), shareBalance1);
        compounder.redeem(shareBalance1, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        compounder.approve(address(compounder), shareBalance2);
        compounder.redeem(shareBalance2, user2, user2);
        vm.stopPrank();

        vm.startPrank(user3);
        compounder.approve(address(compounder), shareBalance3);
        compounder.redeem(shareBalance3, user3, user3);
        vm.stopPrank();

        assertEq(compounder.totalSupply(), 0);
        assertGt(token.balanceOf(user1), balance1);
        assertGt(token.balanceOf(user2), balance2);
        assertGt(token.balanceOf(user1), previewRedeem1);
        assertGt(token.balanceOf(user2), previewRedeem2);
        assertApproxEqAbs(token.balanceOf(user3), balance3, 1); // account for dust
    }

    function autocompoundRedeem(int256 delta) private {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // buy some tokens.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // stack in the compounder.
        uint256 balance1 = token.balanceOf(user1);
        uint256 balance2 = token.balanceOf(user2);

        vm.startPrank(user1);
        token.approve(address(compounder), balance1);
        compounder.deposit(balance1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(compounder), balance2);
        compounder.deposit(balance2, user2);
        vm.stopPrank();

        // distribute, compound and claim.
        token.distribute();

        compounder.compound();

        vm.prank(user3);

        token.claim();

        // preview how much user1 and 2 can redeem.
        uint256 shareBalance1 = compounder.balanceOf(user1);
        uint256 shareBalance2 = compounder.balanceOf(user2);

        uint256 previewRedeem1 = compounder.previewRedeem(shareBalance1);
        uint256 previewRedeem2 = compounder.previewRedeem(shareBalance2);

        assertGt(previewRedeem1, balance1);
        assertGt(previewRedeem2, balance2);

        // set threshold to exact user3 balance and donate.
        uint256 donationAmount = rewardToken.balanceOf(user3);

        // delta allow to test exact or lesser.
        compounder.setAutocompoundTheshold(uint256(int256(donationAmount) + delta));

        assertEq(compounder.rewardBalance(), 0);

        vm.prank(user3);

        rewardToken.transfer(address(compounder), donationAmount);

        assertEq(compounder.rewardBalance(), donationAmount);

        // redeem with user1, it should autocompound.
        vm.startPrank(user1);
        compounder.approve(address(compounder), shareBalance1);
        compounder.redeem(shareBalance1, user1, user1);
        vm.stopPrank();

        assertGt(compounder.previewRedeem(shareBalance2), previewRedeem2);

        vm.startPrank(user2);
        compounder.approve(address(compounder), shareBalance2);
        compounder.redeem(shareBalance2, user2, user2);
        vm.stopPrank();

        assertEq(compounder.totalSupply(), 0);
        assertGt(token.balanceOf(user1), balance1);
        assertGt(token.balanceOf(user2), balance2);
        assertGt(token.balanceOf(user1), previewRedeem1);
        assertGt(token.balanceOf(user2), previewRedeem2);
    }
}
