// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract LiquidityTest is ERC20RewardsTest {
    function testAddsAndRemovesLiquidity() public {
        address provider = vm.addr(1);

        vm.label(provider, "Buyer");

        // compute expected tax after buying 1 ether.
        uint256 amount = norm(10000);
        uint256 rewardFee = (amount * token.buyRewardFee()) / token.feeDenominator();
        uint256 marketingFee = (amount * token.buyMarketingFee()) / token.feeDenominator();

        // buy 1 ether of tokens and add it back as liquidity.
        buyToken(provider, 1 ether);

        uint256 received = token.balanceOf(provider);

        addLiquidity(provider, 1 ether, received);

        rewardFee += (received * token.sellRewardFee()) / token.feeDenominator();
        marketingFee += (received * token.sellMarketingFee()) / token.feeDenominator();

        assertApproxEqRel(token.currentRewards(), rewardFee, 0.01e18);
        assertApproxEqRel(token.currentMarketingAmount(), marketingFee, 0.01e18);

        // no tax is collected from removing liquidity.
        removeLiquidity(provider);

        assertApproxEqRel(token.currentRewards(), rewardFee, 0.01e18);
        assertApproxEqRel(token.currentMarketingAmount(), marketingFee, 0.01e18);

        // provider must have 0.9 ethers back minus some dex fees.
        // he must also have the token he bought back minus some dex fees.
        assertApproxEqRel(provider.balance, 0.9 ether, 0.02e18);
        assertApproxEqRel(token.balanceOf(provider), amount - rewardFee - marketingFee, 0.01e18);
    }
}
