// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract SwapTest is ERC20RewardsTest {
    function testSwap() public {
        address user = vm.addr(1);

        // buy 1 ether of tokens.
        buyToken(user, 1 ether);

        // we must have received ~ 760 tokens and ~ 240 should be collected as tax.
        assertApproxEqRel(token.balanceOf(user), withDecimals(760), 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), withDecimals(240), 0.01e18);

        // sell everything, should swapback taxes to eth.
        uint256 balance = token.balanceOf(user);

        sellToken(user, balance);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqRel(address(token).balance, 0.084 ether, 0.01e18);
        assertApproxEqRel(address(token.operator()).balance, 0.337 ether, 0.01e18);
        assertApproxEqRel(address(token).balance + address(token.operator()).balance, 0.422 ether, 0.01e18);

        // (total tax is 240 + (760 * 0.24) = 422 and 1000 tokens =~ 1 eth)
        // 20% is in the contract as rewards (0.084) and 80% in marketing wallet (0.337)
    }
}
