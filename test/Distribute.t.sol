// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract DistributeTest is ERC20RewardsTest {
    function testDistributeSwap() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);
        address user4 = vm.addr(3);

        // set the buy fee to something easy to compute.
        token.setFee(1000, 1000, 2000);

        // add some tax.
        buyToken(user4, 1 ether);

        // send the same value to two users.
        uint256 balance = token.balanceOf(user4);
        uint256 quarter = balance / 4;

        vm.prank(user4);

        token.transfer(user1, quarter * 2);

        vm.prank(user4);

        token.transfer(user2, quarter);

        vm.prank(user4);

        token.transfer(user3, quarter);

        // users with same shares should get same rewards.
        // user with twice more shares should get twice more rewards.
        token.swapCollectedTax(0);
        token.distribute(0);

        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), 0);
        assertGt(token.pendingRewards(user3), 0);
        assertEq(token.pendingRewards(user2), token.pendingRewards(user3));
        assertApproxEqAbs(token.pendingRewards(user1), token.pendingRewards(user2) + token.pendingRewards(user3), 1);
        assertApproxEqRel(token.operator().balance, 0.02 ether, 0.01e18); // tax is 100 tokens ~= 0.1 eth, marketing is 1/5

        // claim everything.
        vm.prank(user1);

        token.claim(user1);

        vm.prank(user2);

        token.claim(user2);

        vm.prank(user3);

        token.claim(user3);

        assertEq(token.balanceOf(address(token)), 0);
        assertGt(rewardToken.balanceOf(user1), 0);
        assertGt(rewardToken.balanceOf(user2), 0);
        assertGt(rewardToken.balanceOf(user3), 0);
        assertEq(rewardToken.balanceOf(user2), rewardToken.balanceOf(user3));
        assertApproxEqAbs(rewardToken.balanceOf(user1), rewardToken.balanceOf(user2) + rewardToken.balanceOf(user3), 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 100); // some dust
    }

    function testDistributeTokenDonations() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // get some token.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // distribute and claim everything.
        token.swapCollectedTax(0);
        token.distribute(0);

        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), 0);
        assertGt(token.pendingRewards(user3), 0);

        vm.prank(user1);

        token.claim(user1);

        vm.prank(user2);

        token.claim(user2);

        vm.prank(user3);

        token.claim(user3);

        assertGt(rewardToken.balanceOf(user1), 0);
        assertGt(rewardToken.balanceOf(user2), 0);
        assertGt(rewardToken.balanceOf(user3), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 100); // some dust

        uint256 claimed1 = rewardToken.balanceOf(user1);
        uint256 claimed2 = rewardToken.balanceOf(user2);
        uint256 claimed3 = rewardToken.balanceOf(user3);

        // anyone can send tokens to the contract.
        uint256 balance1 = token.balanceOf(user1);

        vm.prank(user1);

        token.transfer(address(token), balance1 / 2);

        uint256 balance2 = token.balanceOf(user2);

        vm.prank(user2);

        token.transfer(address(token), balance2 / 2);

        uint256 balance3 = token.balanceOf(user3);

        vm.prank(user3);

        token.transfer(address(token), balance3 / 2);

        // token should have some tax.
        assertEq(token.balanceOf(address(token)), (balance1 / 2) + (balance2 / 2) + (balance3 / 2));

        // everything should be distributed.
        token.swapCollectedTax(0);
        token.distribute(0);

        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), 0);
        assertGt(token.pendingRewards(user3), 0);

        vm.prank(user1);

        token.claim(user1);

        vm.prank(user2);

        token.claim(user2);

        vm.prank(user3);

        token.claim(user3);

        assertGt(rewardToken.balanceOf(user1), claimed1);
        assertGt(rewardToken.balanceOf(user2), claimed2);
        assertGt(rewardToken.balanceOf(user3), claimed3);
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 100); // some dust
    }

    function testDistributeRewardDonations() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // get some token.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // distribute and claim everything.
        token.swapCollectedTax(0);
        token.distribute(0);

        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), 0);
        assertGt(token.pendingRewards(user3), 0);

        vm.prank(user1);

        token.claim(user1);

        vm.prank(user2);

        token.claim(user2);

        vm.prank(user3);

        token.claim(user3);

        assertGt(rewardToken.balanceOf(user1), 0);
        assertGt(rewardToken.balanceOf(user2), 0);
        assertGt(rewardToken.balanceOf(user3), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 100); // some dust

        uint256 claimed1 = rewardToken.balanceOf(user1);
        uint256 claimed2 = rewardToken.balanceOf(user2);
        uint256 claimed3 = rewardToken.balanceOf(user3);

        // add reward donations, distribute and claim.
        (, uint256 remaining) = addRewards(1 ether);

        token.distribute(0);

        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), 0);
        assertGt(token.pendingRewards(user3), 0);

        vm.prank(user1);

        token.claim(user1);

        vm.prank(user2);

        token.claim(user2);

        vm.prank(user3);

        token.claim(user3);

        assertGt(rewardToken.balanceOf(user1), claimed1);
        assertGt(rewardToken.balanceOf(user2), claimed2);
        assertGt(rewardToken.balanceOf(user3), claimed3);
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), remaining, 100); // some dust

        claimed1 = rewardToken.balanceOf(user1);
        claimed2 = rewardToken.balanceOf(user2);
        claimed3 = rewardToken.balanceOf(user3);

        // emit everything and claim.
        vm.roll(block.number + 9);

        token.distribute(0);

        assertGt(token.pendingRewards(user1), 0);
        assertGt(token.pendingRewards(user2), 0);
        assertGt(token.pendingRewards(user3), 0);

        vm.prank(user1);

        token.claim(user1);

        vm.prank(user2);

        token.claim(user2);

        vm.prank(user3);

        token.claim(user3);

        assertGt(rewardToken.balanceOf(user1), claimed1);
        assertGt(rewardToken.balanceOf(user2), claimed2);
        assertGt(rewardToken.balanceOf(user3), claimed3);
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 100); // some dust
    }

    function testDistributeLessThanAmountOutMinimumReverts() public {
        address user = vm.addr(1);

        buyToken(user, 1 ether);

        // 10 wTao is > than tax now.
        uint256 amountOutMinimum = 10 * 10 ** rewardToken.decimals();

        token.swapCollectedTax(0);

        vm.expectRevert("Too little received");

        token.distribute(amountOutMinimum);
    }
}
