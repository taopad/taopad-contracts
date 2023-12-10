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
        assertApproxEqRel(token.marketingWallet().balance, 0.02 ether, 0.01e18); // tax is 100 tokens ~= 0.1 eth, marketing is 1/5

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
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 10); // some dust
    }

    function testDistributeTokenDonations() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // get some token.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // token has some taxes already.
        uint256 originalTaxAmount = token.balanceOf(address(token));

        assertGt(originalTaxAmount, 0);

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

        // token should have more than original tax amount.
        assertGt(token.balanceOf(address(token)), originalTaxAmount);

        // everything should be distributed.
        token.swapCollectedTax(0);
        token.distribute(0);

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
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 10); // some dust
    }

    function testDistributeRewardDonations() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // get some token.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // get some reward token.
        buyRewardToken(user1, 1 ether);
        buyRewardToken(user2, 1 ether);
        buyRewardToken(user3, 1 ether);

        // anyone can send reward tokens to the contract.
        uint256 rewardTokenBalance1 = rewardToken.balanceOf(user1);

        vm.prank(user1);

        rewardToken.transfer(address(token), rewardTokenBalance1);

        uint256 rewardTokenBalance2 = rewardToken.balanceOf(user2);

        vm.prank(user2);

        rewardToken.transfer(address(token), rewardTokenBalance2);

        uint256 rewardTokenBalance3 = rewardToken.balanceOf(user3);

        vm.prank(user3);

        rewardToken.transfer(address(token), rewardTokenBalance3);

        // rewards should be distributed.
        token.swapCollectedTax(0);
        token.distribute(0);

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
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 10); // some dust

        // collect more taxes.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);
        buyToken(user3, 1 ether);

        // send on top of taxes.
        rewardTokenBalance1 = rewardToken.balanceOf(user1);

        vm.prank(user1);

        rewardToken.transfer(address(token), rewardTokenBalance1);

        rewardTokenBalance2 = rewardToken.balanceOf(user2);

        vm.prank(user2);

        rewardToken.transfer(address(token), rewardTokenBalance2);

        rewardTokenBalance3 = rewardToken.balanceOf(user3);

        vm.prank(user3);

        rewardToken.transfer(address(token), rewardTokenBalance3);

        // taxes and sent rewards should be distributed.
        token.swapCollectedTax(0);
        token.distribute(0);

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
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 10); // some dust
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
