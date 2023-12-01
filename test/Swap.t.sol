// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract SwapTest is ERC20RewardsTest {
    function testSwap() public {
        address user = vm.addr(1);

        vm.label(user, "User");

        // base amount for 1 ether
        uint256 amountFor1Ether = 1000 * 10 ** token.decimals();

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
        assertEq(token.balanceOf(user), 0);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // must buy again otherwise theres 0 share and then 0 distribution.
        uint256 received2 = amountFor1Ether;

        buyToken(user, 1 ether);

        rewardFee += (received2 * token.buyRewardFee()) / token.feeDenominator();
        marketingFee += (received2 * token.buyMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // test distribute is not reverting.
        token.distribute(0);

        uint256 pendingRewards = token.pendingRewards(user);

        assertGt(pendingRewards, 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertGt(rewardToken.balanceOf(address(token)), 0);

        // test claim is not reverting.
        vm.prank(user);

        token.claim();

        assertEq(address(token).balance, 0);
        assertEq(rewardToken.balanceOf(user), pendingRewards);
        assertGt(rewardToken.balanceOf(token.marketingWallet()), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 1); // some dust
    }
}
