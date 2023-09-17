// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract SwapTest is ERC20RewardsTest {
    function testBuyAreTaxed() public {
        address buyer = vm.addr(1);

        vm.label(buyer, "Buyer");

        // add liq (1eth = 10 000 tokens) and enable taxes.
        addLiquidity(address(this), 1000 ether, token.totalSupply());

        // buy 10000 tokens (~ 1 eth).
        buyToken(buyer, 1 ether);

        // buyer should get 9000 tokens (10000 tokens minus 10% fee).
        // contract should collect 1000 tokens (10% of 10000 tokens).
        // 1000 as contract balance, 800 as rewards, 200 as marketing.
        // add 1% tolerance to account for swap fee/slippage.
        assertApproxEqRel(token.balanceOf(buyer), norm(9000), 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), norm(1000), 0.01e18);
        assertApproxEqRel(token.currentRewards(), norm(800), 0.01e18);
        assertApproxEqRel(token.marketingFeeAmount(), norm(200), 0.01e18);
    }

    function testSellAreTaxed() public {
        address seller = vm.addr(1);

        vm.label(seller, "Seller");

        // add liq (1eth = 10 000 tokens) and enabled taxes.
        addLiquidity(address(this), 900 ether, token.totalSupply() - norm(1e6));

        // sell 10000 tokens (~ 1 eth).
        sellToken(seller, norm(10000));

        // seller should get 0.9 ethers (1 ether minus 10% fee).
        // contract should collect 1000 tokens (10% of 10000 tokens).
        // 1000 as contract balance, 800 as rewards, 200 as marketing.
        // add 1% tolerance to account for swap fee/slippage.
        assertApproxEqRel(payable(seller).balance, 0.9 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), norm(1000), 0.01e18);
        assertApproxEqRel(token.currentRewards(), norm(800), 0.01e18);
        assertApproxEqRel(token.marketingFeeAmount(), norm(200), 0.01e18);
    }
}
