// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract EmittedRewardsTest is ERC20RewardsTest {
    function testSetRewardTokenPerBlock() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        // by default the reward token per block is 0.
        assertEq(token.rewardTokenPerBlock(), 0);

        // by default owner can set reward token per block.
        token.setRewardTokenPerBlock(1000);

        assertEq(token.rewardTokenPerBlock(), 1000);

        // set new operator.
        token.setOperator(user1);

        // operator can set reward token per block.
        vm.prank(user1);

        token.setRewardTokenPerBlock(2000);

        assertEq(token.rewardTokenPerBlock(), 2000);

        // owner now revert.
        vm.expectRevert("!operator");

        token.setRewardTokenPerBlock(3000);

        // non operator reverts.
        vm.prank(user2);

        vm.expectRevert("!operator");

        token.setRewardTokenPerBlock(3000);
    }

    function testEmittedRewardsAccumulates() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        // buy some reward tokens and send 1e9 units of reward in the contract.
        buyRewardToken(address(this), 1 ether);

        rewardToken.transfer(address(token), 1e9);

        // set the reward rate to 1e5 units.
        token.setRewardTokenPerBlock(1e5);

        // next 10 blocks 1e6 reward tokens has been emitted.
        vm.roll(block.number + 10);

        assertEq(token.rewardBalance(), 1e9);
        assertEq(token.emittedRewards(), 1e6);
        assertEq(token.remainingRewards(), 1e9 - 1e6);
        assertEq(token.emittedRewardsAcc(), 0);

        // set the reward rate to 1e6 units.
        token.setRewardTokenPerBlock(1e6);

        // next 9 blocks 1e7 reward tokens has been emitted.
        vm.roll(block.number + 9);

        assertEq(token.rewardBalance(), 1e9);
        assertEq(token.emittedRewards(), 1e7);
        assertEq(token.remainingRewards(), 1e9 - 1e7);
        assertEq(token.emittedRewardsAcc(), 1e6);

        // set the reward rate to 1e7 units.
        token.setRewardTokenPerBlock(1e7);

        // next 9 blocks 1e8 reward tokens has been emitted.
        vm.roll(block.number + 9);

        assertEq(token.rewardBalance(), 1e9);
        assertEq(token.emittedRewards(), 1e8);
        assertEq(token.remainingRewards(), 1e9 - 1e8);
        assertEq(token.emittedRewardsAcc(), 1e7);

        // set the reward rate to 1e8 units.
        token.setRewardTokenPerBlock(1e8);

        // next 9 blocks 1e9 reward tokens has been emitted.
        vm.roll(block.number + 9);

        assertEq(token.rewardBalance(), 1e9);
        assertEq(token.emittedRewards(), 1e9);
        assertEq(token.remainingRewards(), 0);
        assertEq(token.emittedRewardsAcc(), 1e8);

        // set the reward rate to 1 units.
        token.setRewardTokenPerBlock(1);

        // no more rewards are emitted.
        vm.roll(block.number + 1);

        assertEq(token.rewardBalance(), 1e9);
        assertEq(token.emittedRewards(), 1e9);
        assertEq(token.remainingRewards(), 0);
        assertEq(token.emittedRewardsAcc(), 1e9);

        // buy some tokens (so little than there cant be more than 1 tao reward).
        buyToken(user1, 0.01 ether);
        buyToken(user2, 0.01 ether);

        // distribute.
        token.swapCollectedTax(0);
        token.distribute(0);

        // all rewards should have been sent and reseted.
        assertEq(token.rewardBalance(), 0);
        assertEq(token.emittedRewards(), 0);
        assertEq(token.remainingRewards(), 0);
        assertEq(token.emittedRewardsAcc(), 0);
        assertGt(token.pendingRewards(user1) + token.pendingRewards(user2), 1e9);

        vm.prank(user1);

        token.claim(user1);

        vm.prank(user2);

        token.claim(user2);

        assertGt(rewardToken.balanceOf(user1) + rewardToken.balanceOf(user2), 1e9);
    }
}
