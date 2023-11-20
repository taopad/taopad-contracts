// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract SwapTest is ERC20RewardsTest {
    function testBuyAndSell() public {
        address user = vm.addr(1);

        vm.label(user, "User");

        // compute expected tax after buying 1 ether.
        uint256 amount = norm(10000);
        uint256 rewardFee = (amount * token.buyRewardFee()) / token.feeDenominator();
        uint256 marketingFee = (amount * token.buyMarketingFee()) / token.feeDenominator();

        // buy 1 ether of token.
        buyToken(user, 1 ether);

        uint256 received = token.balanceOf(user);

        // for 10% tax:
        // buyer should get 9000 tokens (10000 tokens minus 10% fee).
        // contract should collect 1000 tokens (10% of 10000 tokens).
        // 1000 as contract balance, 800 as rewards, 200 as marketing.
        // add 1% tolerance to account for swap fee/slippage.
        assertApproxEqRel(received, amount - rewardFee - marketingFee, 0.01e18);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);

        // sell balance.
        sellToken(user, received);

        // compute expected tax after selling whole balance.
        rewardFee += (received * token.sellRewardFee()) / token.feeDenominator();
        marketingFee += (received * token.sellMarketingFee()) / token.feeDenominator();

        // ensure collected taxes have the excpected values.
        assertEq(token.balanceOf(user), 0);
        assertApproxEqRel(token.marketingAmount(), marketingFee, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), rewardFee + marketingFee, 0.01e18);
    }
}
