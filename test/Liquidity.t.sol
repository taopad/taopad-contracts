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

        addLiquidity(provider, 1 ether, token.balanceOf(provider));

        // ~0.24 eth has been refunded to the provider because
        // only 760 tokens has been put as liq.
        assertEq(token.balanceOf(provider), 0);
        assertApproxEqRel(address(provider).balance, 0.24 ether, 0.01e18);

        // adding liquidity is like a sell so the tax should have been sold.
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqRel(address(token).balance, 0.422 ether, 0.01e18); // same computation as testSwap

        uint256 originalTaxAmountEth = address(token).balance;

        // removing liquidity.
        removeLiquidity(provider);

        // so user end up with 0.81 ethers and 577 tokens ?
        assertApproxEqRel(address(provider).balance, 0.57 ether + 0.24 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(provider), withDecimals(577), 0.01e18);

        // no tax was collected on removing liquidity.
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(address(token).balance, originalTaxAmountEth);
    }
}
