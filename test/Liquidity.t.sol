// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract LiquidityTest is ERC20RewardsTest {
    function testAddsAndRemovesLiquidity() public {
        address provider = vm.addr(1);

        vm.label(provider, "Buyer");

        // amount for 1 ether
        uint256 amountFor1Ether = norm(10000);

        // compute amount tax after buying 1 ether.
        uint256 rewardFee;
        uint256 marketingFee;

        // buy 1 ether of tokens.
        uint256 expected = amountFor1Ether;

        buyToken(provider, 1 ether);

        rewardFee += (expected * token.buyRewardFee()) / token.feeDenominator();
        marketingFee += (expected * token.buyMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.rewardBalance(), rewardFee, 0.01e18);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(provider), expected - rewardFee - marketingFee, 0.01e18);

        // add the received tokens as liquidity.
        uint256 sent = token.balanceOf(provider);

        addLiquidity(provider, 1 ether, sent);

        rewardFee += (sent * token.sellRewardFee()) / token.feeDenominator();
        marketingFee += (sent * token.sellMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.rewardBalance(), rewardFee, 0.01e18);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);
        assertEq(token.balanceOf(provider), 0);

        // no tax is collected from removing liquidity.
        removeLiquidity(provider);

        assertApproxEqRel(token.rewardBalance(), rewardFee, 0.01e18);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);

        // provider must have 0.9 ethers back minus some dex fees.
        // he must also have the token he sent to he pool minus the token fee and dex fee.
        assertApproxEqRel(provider.balance, 0.9 ether, 0.02e18);
        assertApproxEqRel(token.balanceOf(provider), amountFor1Ether - rewardFee - marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // test distribute is not reverting.
        vm.roll(block.number + 1);

        vm.prank(provider);

        token.distribute();

        assertEq(token.rewardBalance(), 0);
        assertGt(token.pendingRewards(provider), 0);
        assertEq(token.balanceOf(address(token)), token.marketingAmount());

        // test claim is not reverting.
        uint256 pendingRewards = token.pendingRewards(provider);

        vm.prank(provider);

        token.claim();

        assertEq(address(token).balance, 0);
        assertEq(rewardToken.balanceOf(provider), pendingRewards);
    }
}
