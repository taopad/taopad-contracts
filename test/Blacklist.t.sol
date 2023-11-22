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

    function testBlacklistAdmin() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);

        // user is not blacklisted by default.
        assertFalse(token.isBlacklisted(user1));

        // user can be blacklisted.
        token.addToBlacklist(user1);

        assertTrue(token.isBlacklisted(user1));

        // user can be removed from blacklist.
        token.removeFromBlacklist(user1);

        assertFalse(token.isBlacklisted(user1));

        // add to blacklist reverts for non owner.
        vm.prank(user1);

        vm.expectRevert();

        token.addToBlacklist(user2);

        // remove from blacklist reverts for non owner.
        vm.prank(user1);

        vm.expectRevert();

        token.removeFromBlacklist(user2);

        // add to blacklist many times does not update total shares.
        token.addToBlacklist(user2);

        assertEq(token.totalShares(), token.balanceOf(user1));

        token.addToBlacklist(user2);

        assertEq(token.totalShares(), token.balanceOf(user1));

        // remove from blacklist many times does not update total shares.
        token.removeFromBlacklist(user2);

        assertEq(token.totalShares(), token.balanceOf(user1) + token.balanceOf(user2));

        token.removeFromBlacklist(user2);

        assertEq(token.totalShares(), token.balanceOf(user1) + token.balanceOf(user2));
    }

    function testBlacklistTransfer() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        // add user to blacklist.
        token.addToBlacklist(user1);

        // blacklisted user can still buy.
        buyToken(user1, 1 ether);

        uint256 balance = token.balanceOf(user1);

        assertGt(balance, 0);

        // blacklisted user cant sell.
        vm.prank(user1);

        vm.expectRevert();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(balance, 0, path, user1, block.timestamp);

        assertEq(token.balanceOf(user1), balance);

        // blacklisted user cant transfer.
        vm.prank(user1);

        vm.expectRevert("blacklisted");

        token.transfer(user2, balance);

        assertEq(token.balanceOf(user1), balance);

        // remove user from blacklist.
        token.removeFromBlacklist(user1);

        // he can now sell.
        vm.prank(user1);

        token.approve(address(router), balance / 2);

        vm.prank(user1);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(balance / 2, 0, path, user1, block.timestamp);

        assertEq(token.balanceOf(user1), balance - (balance / 2));

        // he can now transfer.
        balance = token.balanceOf(user1);

        vm.prank(user1);

        token.transfer(user2, balance);

        assertEq(token.balanceOf(user1), 0);
    }

    function testBlacklistDistribution() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // add some shares.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);

        assertEq(token.totalShares(), token.balanceOf(user1) + token.balanceOf(user2));

        // distribute the rewards.
        token.distribute();

        uint256 pendingRewards1 = token.pendingRewards(user1);
        uint256 pendingRewards2 = token.pendingRewards(user2);
        uint256 pendingRewards3 = token.pendingRewards(user3);

        assertGt(pendingRewards1, 0);
        assertGt(pendingRewards2, 0);
        assertEq(pendingRewards3, 0);

        // adding user to blacklist remove its shares but pending rewards are the same.
        token.addToBlacklist(user2);

        assertEq(token.totalShares(), token.balanceOf(user1));
        assertEq(token.pendingRewards(user1), pendingRewards1);
        assertEq(token.pendingRewards(user2), pendingRewards2);

        // add more shares.
        buyToken(user3, 1 ether);

        assertEq(token.totalShares(), token.balanceOf(user1) + token.balanceOf(user3));

        // distribute the rewards.
        token.distribute();

        assertGt(token.pendingRewards(user1), pendingRewards1);
        assertEq(token.pendingRewards(user2), pendingRewards2);
        assertGt(token.pendingRewards(user3), pendingRewards3);

        pendingRewards1 = token.pendingRewards(user1);
        pendingRewards3 = token.pendingRewards(user3);

        // removing user from blacklist now take his shares into account.
        token.removeFromBlacklist(user2);

        assertEq(token.totalShares(), token.balanceOf(user1) + token.balanceOf(user2) + token.balanceOf(user3));

        // add more shares.
        buyToken(user3, 1 ether);

        assertEq(token.totalShares(), token.balanceOf(user1) + token.balanceOf(user2) + token.balanceOf(user3));

        // distribute the rewards.
        token.distribute();

        assertGt(token.pendingRewards(user1), pendingRewards1);
        assertGt(token.pendingRewards(user2), pendingRewards2);
        assertGt(token.pendingRewards(user3), pendingRewards3);

        pendingRewards1 = token.pendingRewards(user1);
        pendingRewards2 = token.pendingRewards(user2);
        pendingRewards3 = token.pendingRewards(user3);

        // make sure user1 can claim.
        vm.prank(user1);

        token.claim();

        assertEq(token.pendingRewards(user1), 0);
        assertEq(rewardToken.balanceOf(user1), pendingRewards1);

        // make sure user2 can claim.
        vm.prank(user2);

        token.claim();

        assertEq(token.pendingRewards(user2), 0);
        assertEq(rewardToken.balanceOf(user2), pendingRewards2);

        // make sure user3 can claim.
        vm.prank(user3);

        token.claim();

        assertEq(token.pendingRewards(user3), 0);
        assertEq(rewardToken.balanceOf(user3), pendingRewards3);

        // only dust should stay in contract balance.
        assertLt(rewardToken.balanceOf(address(token)), 1e6);
    }
}
