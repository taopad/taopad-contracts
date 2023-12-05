// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract LiquidityTest is ERC20RewardsTest {
    function testRemoveAllLiquidity() public {
        token.removeLimits(); // max wallet!

        removeLiquidity(address(this));

        assertApproxEqRel(address(this).balance, 1000 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(this)), withDecimals(1e6), 0.01e18);
    }

    function testProvideLiquidity() public {
        address provider = vm.addr(1);

        // buy some tokens and put them as liquidity.
        buyToken(provider, 1 ether);

        uint256 balance = token.balanceOf(provider);

        // ~ 760 tokens has been received.
        assertApproxEqRel(balance, withDecimals(760), 0.01e18);

        // So we send the 760 tokens with 0.76 eth. (1eth = 1000 tokens)
        addLiquidity(provider, 0.76 ether, balance);

        // all should be sent to the LP, only a few eth dust is send back.
        assertEq(token.balanceOf(provider), 0);
        assertApproxEqAbs(address(provider).balance, 0, 0.01 ether);

        // adding liquidity is like a sell so the tax should have been sold.
        // 24% tax by default: 1000 tokens * 0.76 (buy) * 0.76 (add liquidity) ~= 577.6.
        // 1000 - 577.6 = 422.4 tokens were collected as tax ~= 0.4224 eth.
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqRel(address(token).balance, 0.4224 ether, 0.01e18);

        uint256 originalTaxAmountEth = address(token).balance;

        // removing liquidity.
        removeLiquidity(provider);

        // no tax on removing liquidity so user should get back 577 tokens and 0.577 eth back.
        assertApproxEqRel(address(provider).balance, 0.577 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(provider), withDecimals(577), 0.01e18);

        // no tax was collected on removing liquidity.
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(address(token).balance, originalTaxAmountEth);
    }
}
