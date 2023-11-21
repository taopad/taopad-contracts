// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract SwapTest is ERC20RewardsTest {
    function testBuyAndSell() public {
        address user = vm.addr(1);

        vm.label(user, "User");

        // amount for 1 ether
        uint256 amountFor1Ether = norm(10000);

        // compute amount tax after buying 1 ether.
        uint256 rewardFee;
        uint256 marketingFee;

        // buy 1 ether of tokens.
        uint256 received1 = amountFor1Ether;

        buyToken(user, 1 ether);

        // compute the expected tax after buying 1 ether of tokens.
        rewardFee += (received1 * token.buyRewardFee()) / token.feeDenominator();
        marketingFee += (received1 * token.buyMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.rewardBalance(), rewardFee, 0.01e18);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(user), received1 - rewardFee - marketingFee, 0.01e18);

        // sell balance.
        uint256 sent = token.balanceOf(user);

        sellToken(user, sent);

        // compute expected tax after selling whole balance.
        rewardFee += (sent * token.sellRewardFee()) / token.feeDenominator();
        marketingFee += (sent * token.sellMarketingFee()) / token.feeDenominator();

        // ensure collected taxes have the excpected values.
        assertApproxEqRel(token.rewardBalance(), rewardFee, 0.01e18);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);
        assertEq(token.balanceOf(user), 0);

        // must buy again otherwise theres 0 share and then 0 distribution.
        uint256 received2 = amountFor1Ether;

        buyToken(user, 1 ether);

        rewardFee += (received2 * token.buyRewardFee()) / token.feeDenominator();
        marketingFee += (received2 * token.buyMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.rewardBalance(), rewardFee, 0.01e18);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // test distribute is not reverting.
        vm.roll(block.number + 1);

        vm.prank(user);

        token.distribute();

        assertEq(token.rewardBalance(), 0);
        assertGt(token.pendingRewards(user), 0);
        assertEq(token.balanceOf(address(token)), token.marketingAmount());

        // test claim is not reverting.
        uint256 pendingRewards = token.pendingRewards(user);
        uint256 originalBalance = user.balance;

        vm.prank(user);

        token.claim();

        assertEq(user.balance, originalBalance + pendingRewards);
    }
}
