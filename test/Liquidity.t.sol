// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract LiquidityTest is ERC20RewardsTest {
    function testOwnerAddsAndRemovesLiquidity() public {
        uint256 originalSupply = token.totalSupply();

        // no tax collected from owner when adding liq.
        addLiquidity(address(this), 1000 ether, originalSupply);

        assertEq(token.balanceOf(address(token)), 0);

        // no tax collected from owner when removing liq.
        removeLiquidity(address(this));

        assertEq(token.balanceOf(address(token)), 0);

        // owner get everything back minus some dex fees.
        assertApproxEqRel(payable(address(this)).balance, 1000 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(this)), originalSupply, 0.01e18);
    }

    function testUserAddsAndRemovesLiquidity() public {
        address provider = vm.addr(1);

        vm.label(provider, "Provider");

        // compute values and transfer needed tokens to provider.
        uint256 amount = norm(1e6);

        token.transfer(provider, amount * 2);

        // we set initial ratio of 1 = 1.
        // 10% tax is collected when liquidity is added.
        // it means the pool gets 900eth = 900k tokens.
        // theres more flexibility when adding initial liq because theres no ratio.
        addLiquidity(provider, 900 ether, amount);

        assertApproxEqRel(token.balanceOf(address(token)), (amount * 10) / 100, 0.01e18);

        // add liquidity a second time, with the 1 = 1 ratio we set previously.
        // we must send the same ratio, but slippage is allowed.
        // it means all eth send by provider is sent to the pool, even it it gets 90% of the sent tokens.
        // the pool will end with 1900 eth and 1900k tokens.
        addLiquidity(provider, 1000 ether, amount);

        assertEq(payable(provider).balance, 0);
        assertApproxEqRel(token.balanceOf(address(token)), (amount * 20) / 100, 0.01e18);

        // no tax is collected from removing liquidity.
        removeLiquidity(provider);

        assertApproxEqRel(token.balanceOf(address(token)), (amount * 20) / 100, 0.01e18);

        // provider must have 1900 ethers back minus some dex fees.
        // he must also have 80% of amount back minus some dex fees.
        assertApproxEqRel(payable(provider).balance, 1900 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(provider), ((amount * 90) / 100) * 2, 0.01e18);
    }
}
