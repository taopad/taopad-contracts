// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract FeeTest is ERC20RewardsTest {
    function testDistribute() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // set the buy fee to something easy to compute.
        token.setBuyFee(800, 200);

        // add some tax.
        buyToken(user3, 1 ether);

        // send the same value to two users.
        uint256 balance = token.balanceOf(user3);

        vm.prank(user3);

        token.transfer(user1, balance / 2);

        vm.prank(user3);

        token.transfer(user2, balance / 2);

        // two users should get the same rewards.
        token.distribute();

        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), 0);
        assertEq(token.pendingRewards(user1), token.pendingRewards(user2));
        assertGt(rewardToken.balanceOf(token.marketingWallet()), 0);

        // two users should claim the same amount.
        vm.prank(user1);

        token.claim();

        vm.prank(user2);

        token.claim();

        assertEq(rewardToken.balanceOf(user1), rewardToken.balanceOf(user2));

        // check marketing amount.
        uint256 distributed =
            rewardToken.balanceOf(user1) + rewardToken.balanceOf(user2) + rewardToken.balanceOf(token.marketingWallet());

        assertApproxEqRel(rewardToken.balanceOf(token.marketingWallet()), distributed / 5, 0.01e18);
    }
}
