// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract SwapTest is ERC20RewardsTest {
    function testBuyAndSell() public {
        address user = vm.addr(1);

        vm.label(user, "User");

        // amount for 1 ether
        uint256 amountFor1Ether = norm(1000);

        // compute amount tax after buying 1 ether.
        uint256 rewardFee;
        uint256 marketingFee;

        // buy 1 ether of tokens.
        uint256 received1 = amountFor1Ether;

        buyToken(user, 1 ether);

        // compute the expected tax after buying 1 ether of tokens.
        rewardFee += (received1 * token.buyRewardFee()) / token.feeDenominator();
        marketingFee += (received1 * token.buyMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(user), received1 - rewardFee - marketingFee, 0.01e18);

        // sell balance.
        uint256 sent = token.balanceOf(user);

        sellToken(user, sent);

        // compute expected tax after selling whole balance.
        rewardFee += (sent * token.sellRewardFee()) / token.feeDenominator();
        marketingFee += (sent * token.sellMarketingFee()) / token.feeDenominator();

        // ensure collected taxes have the excpected values.
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);
        assertEq(token.balanceOf(user), 0);

        // must buy again otherwise theres 0 share and then 0 distribution.
        uint256 received2 = amountFor1Ether;

        buyToken(user, 1 ether);

        rewardFee += (received2 * token.buyRewardFee()) / token.feeDenominator();
        marketingFee += (received2 * token.buyMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // test distribute is not reverting.
        vm.roll(block.number + 1);

        vm.prank(user);

        token.distribute();

        uint256 pendingRewards = token.pendingRewards(user);

        assertGt(pendingRewards, 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertGt(rewardToken.balanceOf(address(token)), 0);

        // test claim is not reverting.
        vm.prank(user);

        token.claim();

        assertEq(address(token).balance, 0);
        assertEq(rewardToken.balanceOf(user), pendingRewards);
        assertLt(rewardToken.balanceOf(address(token)), 10); // some dust
        assertGt(rewardToken.balanceOf(token.marketingWallet()), 0);
        assertGt(pendingRewards, rewardToken.balanceOf(token.marketingWallet()));
    }
}
