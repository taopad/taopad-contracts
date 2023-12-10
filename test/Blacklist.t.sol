// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract BlacklistTest is ERC20RewardsTest {
    function testDeadblocks() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);
        address user4 = vm.addr(4);

        // n block is a dead block.
        vm.roll(token.startBlock());

        buyToken(user1, 1 ether);

        assertTrue(token.isBlacklisted(user1));
        assertGt(token.balanceOf(user1), 0);

        // n + 1 block is a dead block.
        vm.roll(token.startBlock() + 1);

        buyToken(user2, 1 ether);

        assertTrue(token.isBlacklisted(user2));
        assertGt(token.balanceOf(user2), 0);

        // n + 2 block is a dead block.
        vm.roll(token.startBlock() + 2);

        buyToken(user3, 1 ether);

        assertTrue(token.isBlacklisted(user3));
        assertGt(token.balanceOf(user3), 0);

        // n + 3 is ok.
        vm.roll(token.startBlock() + 3);

        buyToken(user4, 1 ether);

        assertFalse(token.isBlacklisted(user4));
        assertGt(token.balanceOf(user4), 0);
    }

    function testRemoveFromBlacklist() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        // blacklist user1.
        vm.roll(token.startBlock());

        buyToken(user1, 1 ether);

        uint256 balance1 = token.balanceOf(user1);

        assertGt(balance1, 0);
        assertTrue(token.isBlacklisted(user1));

        // user2 buys.
        vm.roll(token.startBlock() + token.deadBlocks() + 1);

        buyToken(user2, 1 ether);

        uint256 balance2 = token.balanceOf(user2);

        assertGt(balance2, 0);
        assertFalse(token.isBlacklisted(user2));

        // total shares is only user2 balance.
        assertEq(token.totalShares(), balance2);

        // remove from blacklist reverts for non owner.
        vm.prank(user2);

        vm.expectRevert();

        token.removeFromBlacklist(user1);

        // owner can remove from blacklist.
        token.removeFromBlacklist(user1);

        assertFalse(token.isBlacklisted(user1));
        assertEq(token.totalShares(), balance1 + balance2);

        // can remove many times from blacklist.
        token.removeFromBlacklist(user1);

        assertFalse(token.isBlacklisted(user1));
        assertEq(token.totalShares(), balance1 + balance2);
    }

    function testBlacklistTransfer() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        // blacklist user1.
        vm.roll(token.startBlock());

        buyToken(user1, 1 ether);

        uint256 balance1 = token.balanceOf(user1);

        assertGt(balance1, 0);
        assertTrue(token.isBlacklisted(user1));

        // user2 buys.
        vm.roll(token.startBlock() + token.deadBlocks() + 1);

        buyToken(user2, 1 ether);

        uint256 balance2 = token.balanceOf(user2);

        assertGt(balance2, 0);
        assertFalse(token.isBlacklisted(user2));

        // keep half of user2 balance.
        uint256 half = balance2 / 2;

        assertGt(half, 0);

        // blacklisted user can still receive tokens.
        vm.prank(user2);

        token.transfer(user1, half);

        assertEq(token.balanceOf(user1), balance1 + half);
        assertEq(token.balanceOf(user2), balance2 - half);

        // blacklisted user can still receive tokens with transfered from.
        vm.prank(user2);

        token.approve(address(this), half);

        token.transferFrom(user2, user1, half);

        assertEq(token.balanceOf(user1), balance1 + half * 2);
        assertEq(token.balanceOf(user2), balance2 - half * 2);

        // blacklisted user can't send tokens anymore.
        vm.prank(user1);

        vm.expectRevert("blacklisted");

        token.transfer(user2, half);

        // blacklisted user can't send with a transfer from.
        vm.prank(user1);

        token.approve(address(this), half);

        vm.expectRevert("blacklisted");

        token.transferFrom(user1, user2, half);

        // remove user1 from blacklist.
        token.removeFromBlacklist(user1);

        assertFalse(token.isBlacklisted(user1));

        // user1 can send tokens again.
        vm.prank(user1);

        token.transfer(user2, half);

        assertEq(token.balanceOf(user1), balance1 + half);
        assertEq(token.balanceOf(user2), balance2 - half);

        // user1 can send from a transfer from again.
        vm.prank(user1);

        token.approve(address(this), half);

        token.transferFrom(user1, user2, half);

        assertEq(token.balanceOf(user1), balance1);
        assertEq(token.balanceOf(user2), balance2);
    }

    function testBlacklistDistribution() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        // blacklist user1.
        vm.roll(token.startBlock());

        buyToken(user1, 1 ether);

        uint256 balance1 = token.balanceOf(user1);

        assertGt(balance1, 0);
        assertTrue(token.isBlacklisted(user1));

        // user2 buys.
        vm.roll(token.startBlock() + token.deadBlocks() + 1);

        buyToken(user2, 1 ether);

        uint256 balance2 = token.balanceOf(user2);

        assertGt(balance2, 0);
        assertFalse(token.isBlacklisted(user2));

        // total shares are user2 balance.
        assertEq(token.totalShares(), balance2);

        // distribute the rewards.
        token.swapCollectedTax(0);
        token.distribute(0);

        // only user2 has rewards.
        uint256 pendingRewards1 = token.pendingRewards(user1);
        uint256 pendingRewards2 = token.pendingRewards(user2);

        assertEq(pendingRewards1, 0);
        assertGt(pendingRewards2, 0);

        // remove user1 from blacklist.
        token.removeFromBlacklist(user1);

        assertFalse(token.isBlacklisted(user1));

        // total shares are now user1 + user2 balance.
        assertEq(token.totalShares(), balance1 + balance2);

        // add rewards and distribute.
        addRewards(1 ether);

        token.distribute(0);

        // user1 now has rewards.
        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), pendingRewards2);
    }
}
