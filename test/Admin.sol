// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract AdminTest is ERC20RewardsTest {
    function testWithdrawMarketing() public {
        token.setBuyFee(1000, 0);

        buyToken(vm.addr(1), 1 ether);

        token.withdrawMarketing();

        assertEq(token.balanceOf(address(this)), 0);

        token.setBuyFee(1000, 1000);

        buyToken(vm.addr(1), 1 ether);

        token.withdrawMarketing(0);

        assertEq(token.balanceOf(address(this)), 0);

        buyToken(vm.addr(1), 1 ether);

        uint256 amount1 = token.marketingAmount();

        token.withdrawMarketing();

        assertEq(token.balanceOf(address(this)), amount1);

        buyToken(vm.addr(1), 1 ether);

        uint256 amount2 = token.marketingAmount();

        token.withdrawMarketing(amount2 / 2);

        assertEq(token.balanceOf(address(this)), amount1 + (amount2 / 2));
        assertEq(token.marketingAmount(), amount2 - (amount2 / 2));
    }
}
