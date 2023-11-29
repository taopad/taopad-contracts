// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20RewardsTest, ERC20Mock} from "./ERC20RewardsTest.t.sol";

contract CompounderTest is ERC20RewardsTest {
    struct AutocompoundUser {
        address addr;
        uint256 balance;
        uint256 shareBalance;
    }

    function depositToken(address addr, uint256 amount) private {
        vm.startPrank(addr);
        token.approve(address(compounder), amount);
        compounder.deposit(amount, addr);
        vm.stopPrank();
    }

    function redeemShare(address addr, uint256 amount) private {
        vm.startPrank(addr);
        compounder.approve(address(compounder), amount);
        compounder.redeem(amount, addr, addr);
        vm.stopPrank();
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

    function testCompounderCompound() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        assertTrue(token.isOptin(address(compounder)));

        uint256 rewardBalance = compounder.rewardBalance();

        assertEq(rewardBalance, 0);

        // buy some tokens and deposit in the compounder.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);

        uint256 balance1 = token.balanceOf(user1);
        uint256 balance2 = token.balanceOf(user2);

        depositToken(user1, balance1);
        depositToken(user2, balance2);

        assertGt(compounder.balanceOf(user1), 0);
        assertGt(compounder.balanceOf(user2), 0);
        assertEq(compounder.rewardBalance(), 0);
        assertEq(compounder.totalAssets(), balance1 + balance2);

        // distribute and compound the rewards (from first buy).
        token.distribute();

        assertGt(compounder.rewardBalance(), 0);

        compounder.compound();

        assertEq(compounder.rewardBalance(), 0);
        assertEq(rewardToken.balanceOf(address(compounder)), 0);
        assertEq(IERC20(router.WETH()).balanceOf(address(compounder)), 0);
        assertGt(compounder.totalAssets(), balance1 + balance2);

        // user can now redeem more tokens.
        redeemShare(user1, compounder.balanceOf(user1));
        redeemShare(user2, compounder.balanceOf(user2));

        assertGt(token.balanceOf(user1), balance1);
        assertGt(token.balanceOf(user2), balance2);
        assertApproxEqAbs(compounder.totalAssets(), 0, 1); // account for dust
    }

    function testCompounderDonations() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // buy some token and deposit in the compounder.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);

        uint256 balance1 = token.balanceOf(user1);
        uint256 balance2 = token.balanceOf(user2);

        depositToken(user1, balance1);
        depositToken(user2, balance2);

        // distribute the rewards and get the compounder reward amount.
        token.distribute();

        uint256 compounderRewardAmount = compounder.rewardBalance();

        assertGt(compounderRewardAmount, 0);

        // make a donation to the contract.
        buyRewardToken(user3, 1 ether);

        uint256 donationAmount = rewardToken.balanceOf(user3);

        vm.prank(user3);

        rewardToken.transfer(address(compounder), donationAmount);

        assertGt(donationAmount, 0);
        assertEq(compounder.rewardBalance(), compounderRewardAmount + donationAmount);

        // compound and redeem.
        compounder.compound();

        redeemShare(user1, compounder.balanceOf(user1));
        redeemShare(user2, compounder.balanceOf(user2));

        assertGt(token.balanceOf(user1), balance1);
        assertGt(token.balanceOf(user2), balance2);
        assertEq(compounder.balanceOf(user1), 0);
        assertEq(compounder.balanceOf(user2), 0);
        assertEq(compounder.rewardBalance(), 0);
        assertApproxEqAbs(compounder.totalAssets(), 0, 1); // account for dust
    }

    function testAutocompoundDepositExact() public {
        testAutocompoundDeposit(0);
    }

    function testAutocompoundDepositGreater() public {
        testAutocompoundDeposit(-1); // threshold will be less than donation.
    }

    function testFailAutocompoundDepositLesser() public {
        testAutocompoundDeposit(1); // threshold will be more than donation.
    }

    function testAutocompoundDeposit(int256 delta) private {
        AutocompoundUser memory user1 = AutocompoundUser(vm.addr(1), 0, 0);
        AutocompoundUser memory user2 = AutocompoundUser(vm.addr(2), 0, 0);
        AutocompoundUser memory user3 = AutocompoundUser(vm.addr(3), 0, 0);

        // buy some tokens and deposit in the compounder.
        buyToken(user1.addr, 1 ether);
        buyToken(user2.addr, 1 ether);

        user1.balance = token.balanceOf(user1.addr);
        user2.balance = token.balanceOf(user2.addr);

        uint256 previewDeposit1 = compounder.previewDeposit(user1.balance);

        depositToken(user1.addr, user1.balance);

        uint256 previewDeposit2 = compounder.previewDeposit(user2.balance);

        depositToken(user2.addr, user2.balance);

        user1.shareBalance = compounder.balanceOf(user1.addr);
        user2.shareBalance = compounder.balanceOf(user2.addr);

        assertGt(user1.shareBalance, 0);
        assertGt(user2.shareBalance, 0);
        assertEq(user1.shareBalance, previewDeposit1);
        assertEq(user2.shareBalance, previewDeposit2);

        // distribute and compound.
        token.distribute();

        compounder.compound();

        assertEq(compounder.rewardBalance(), 0);

        // get user3 buys token and preview deposit now.
        buyToken(user3.addr, 1 ether);

        user3.balance = token.balanceOf(user3.addr);

        uint256 originalPreviewDeposit3 = compounder.previewDeposit(user3.balance);

        assertGt(originalPreviewDeposit3, 0);

        // make a donation equal or above autocompound threshold.
        buyRewardToken(user1.addr, 1 ether);

        uint256 donationAmount = rewardToken.balanceOf(user1.addr);

        vm.prank(user1.addr);

        rewardToken.transfer(address(compounder), donationAmount);

        compounder.setAutocompoundTheshold(uint256(int256(donationAmount) + delta));

        assertGt(donationAmount, 0);
        assertEq(compounder.rewardBalance(), donationAmount);

        // user3 deposit, should trigger autocompound.
        // should mint less shares than without autocompound.
        // because the underlying total assets will grow before before minting the shares.
        uint256 previewDeposit3 = compounder.previewDeposit(user3.balance);

        depositToken(user3.addr, user3.balance);

        user3.shareBalance = compounder.balanceOf(user3.addr);

        assertGt(previewDeposit3, 0);
        assertEq(previewDeposit3, user3.shareBalance);
        assertLt(previewDeposit3, originalPreviewDeposit3);

        // check everyone can redeem and everything fine.
        redeemShare(user1.addr, user1.shareBalance);
        redeemShare(user2.addr, user2.shareBalance);
        redeemShare(user3.addr, user3.shareBalance);

        assertGt(token.balanceOf(user1.addr), user1.balance);
        assertGt(token.balanceOf(user2.addr), user2.balance);
        assertApproxEqAbs(token.balanceOf(user3.addr), user3.balance, 1); // it didn't compounded more + account for dust

        assertEq(compounder.totalSupply(), 0);
        assertEq(compounder.rewardBalance(), 0);
        assertEq(compounder.balanceOf(user1.addr), 0);
        assertEq(compounder.balanceOf(user2.addr), 0);
        assertEq(compounder.balanceOf(user3.addr), 0);
        assertApproxEqAbs(compounder.totalAssets(), 0, 1); // account for dust
    }

    function testAutocompoundRedeemExact() public {
        testAutocompoundRedeem(0);
    }

    function testAutocompoundRedeemGreater() public {
        testAutocompoundRedeem(-1);
    }

    function testFailAutocompoundRedeemLesser() public {
        testAutocompoundRedeem(1);
    }

    function testAutocompoundRedeem(int256 delta) private {
        AutocompoundUser memory user1 = AutocompoundUser(vm.addr(1), 0, 0);
        AutocompoundUser memory user2 = AutocompoundUser(vm.addr(2), 0, 0);
        AutocompoundUser memory user3 = AutocompoundUser(vm.addr(3), 0, 0);

        // buy some tokens and deposit in the compounder.
        buyToken(user1.addr, 1 ether);
        buyToken(user2.addr, 1 ether);
        buyToken(user3.addr, 1 ether);

        user1.balance = token.balanceOf(user1.addr);
        user2.balance = token.balanceOf(user2.addr);
        user3.balance = token.balanceOf(user3.addr);

        depositToken(user1.addr, user1.balance);
        depositToken(user2.addr, user2.balance);
        depositToken(user3.addr, user3.balance);

        user1.shareBalance = compounder.balanceOf(user1.addr);
        user2.shareBalance = compounder.balanceOf(user2.addr);
        user3.shareBalance = compounder.balanceOf(user3.addr);

        assertGt(user1.shareBalance, 0);
        assertGt(user2.shareBalance, 0);
        assertGt(user3.shareBalance, 0);

        // distribute and compound.
        token.distribute();

        compounder.compound();

        assertEq(compounder.rewardBalance(), 0);

        // user1 redeems, no autocompound.
        uint256 previewRedeem1 = compounder.previewRedeem(user1.shareBalance);

        redeemShare(user1.addr, user1.shareBalance);

        assertGt(previewRedeem1, user1.balance);
        assertEq(previewRedeem1, token.balanceOf(user1.addr));

        // get user2 expected assets now.
        uint256 originalPreviewRedeem2 = compounder.previewRedeem(user2.balance);

        assertGt(originalPreviewRedeem2, 0);

        // make a donation equal or above autocompound threshold.
        buyRewardToken(user1.addr, 1 ether);

        uint256 donationAmount = rewardToken.balanceOf(user1.addr);

        vm.prank(user1.addr);

        rewardToken.transfer(address(compounder), donationAmount);

        compounder.setAutocompoundTheshold(uint256(int256(donationAmount) + delta));

        assertGt(donationAmount, 0);
        assertEq(compounder.rewardBalance(), donationAmount);

        // user2 redeems, should trigger autocompound.
        // should redeem more assets than without autocompound.
        // because the underlying total assets will grow before before redeeming the shares.
        uint256 previewRedeem2 = compounder.previewRedeem(user2.shareBalance);

        redeemShare(user2.addr, user2.shareBalance);

        assertGt(previewRedeem2, 0);
        assertEq(previewRedeem2, token.balanceOf(user2.addr));
        assertGt(previewRedeem2, originalPreviewRedeem2);

        // check user3 can redeem and everything fine.
        redeemShare(user3.addr, user3.shareBalance);

        assertGt(token.balanceOf(user1.addr), user1.balance);
        assertGt(token.balanceOf(user2.addr), user2.balance);
        assertGt(token.balanceOf(user3.addr), user3.balance);

        assertEq(compounder.totalSupply(), 0);
        assertEq(compounder.rewardBalance(), 0);
        assertEq(compounder.balanceOf(user1.addr), 0);
        assertEq(compounder.balanceOf(user2.addr), 0);
        assertEq(compounder.balanceOf(user3.addr), 0);
        assertApproxEqAbs(compounder.totalAssets(), 0, 1); // account for dust
    }

    function testCompounderSweep() public {
        IERC20 randomToken = new ERC20Mock(1000);

        address user = vm.addr(1);

        // put token and reward token in the contract.
        buyToken(user, 1 ether);
        buyRewardToken(user, 1 ether);

        vm.startPrank(user);
        token.transfer(address(compounder), token.balanceOf(address(user)));
        rewardToken.transfer(address(compounder), rewardToken.balanceOf(address(user)));
        vm.stopPrank();

        assertGt(token.balanceOf(address(compounder)), 0);
        assertGt(rewardToken.balanceOf(address(compounder)), 0);

        // owner cant sweep token.
        vm.expectRevert("!sweep");

        compounder.sweep(token);

        // owner cant sweep reward token.
        vm.expectRevert("!sweep");

        compounder.sweep(rewardToken);

        // user cant sweep token.
        vm.prank(user);

        vm.expectRevert("!sweep");

        compounder.sweep(token);

        // user cant sweep reward token.
        vm.prank(user);

        vm.expectRevert("!sweep");

        compounder.sweep(rewardToken);

        // owner can sweep random token.
        randomToken.transfer(address(compounder), 1000);

        assertEq(randomToken.balanceOf(address(this)), 0);
        assertEq(randomToken.balanceOf(address(compounder)), 1000);

        compounder.sweep(randomToken);

        assertEq(randomToken.balanceOf(address(this)), 1000);
        assertEq(randomToken.balanceOf(address(compounder)), 0);

        // user can sweep random token.
        randomToken.transfer(address(compounder), 1000);

        assertEq(randomToken.balanceOf(address(user)), 0);
        assertEq(randomToken.balanceOf(address(compounder)), 1000);

        vm.prank(user);

        compounder.sweep(randomToken);

        assertEq(randomToken.balanceOf(address(user)), 1000);
        assertEq(randomToken.balanceOf(address(compounder)), 0);
    }
}
