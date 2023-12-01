// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract LiquidityTest is ERC20RewardsTest {
    function testLiquidity() public {
        address provider = vm.addr(1);

        vm.label(provider, "Buyer");

        // amount for 1 ether
        uint256 amountFor1Ether = 1000 * 10 ** token.decimals();

        // compute amount tax after buying 1 ether.
        uint256 rewardFee;
        uint256 marketingFee;

        // buy 1 ether of tokens.
        uint256 expected = amountFor1Ether;

        buyToken(provider, 1 ether);

        rewardFee += (expected * token.buyRewardFee()) / token.feeDenominator();
        marketingFee += (expected * token.buyMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.balanceOf(provider), expected - rewardFee - marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // add the received tokens as liquidity.
        uint256 sent = token.balanceOf(provider);

        addLiquidity(provider, 1 ether, sent);

        rewardFee += (sent * token.sellRewardFee()) / token.feeDenominator();
        marketingFee += (sent * token.sellMarketingFee()) / token.feeDenominator();

        // some of the ethers are send back because the sell tax on token (~ 24% with default taxes).
        uint256 remainingETH = provider.balance;

        assertEq(token.balanceOf(provider), 0);
        assertApproxEqRel(remainingETH, 0.24 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // no tax is collected from removing liquidity.
        removeLiquidity(provider);

        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // Maths looks ok. After adding removing liq the provider ends with ~760 tokend and > 0.76 eth.
        uint256 removedEth = provider.balance - remainingETH;

        assertGt(removedEth, 0.57 ether);
        assertGt(provider.balance, 0.76 ether);
        assertApproxEqRel(token.balanceOf(provider), amountFor1Ether - rewardFee - marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // test distribute is not reverting.
        token.distribute(0);

        uint256 pendingRewards = token.pendingRewards(provider);

        assertGt(pendingRewards, 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertGt(rewardToken.balanceOf(address(token)), 0);

        // test claim is not reverting.
        vm.prank(provider);

        token.claim();

        assertEq(address(token).balance, 0);
        assertEq(rewardToken.balanceOf(provider), pendingRewards);
        assertGt(rewardToken.balanceOf(token.marketingWallet()), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(token)), 0, 1); // some dust
    }
}
