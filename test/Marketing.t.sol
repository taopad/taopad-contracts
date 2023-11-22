// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract MarketingTest is ERC20RewardsTest {
    function testMarketingAmount() public {
        address user = vm.addr(1);

        buyToken(user, 1 ether);

        // owner is marketing wallet by default.
        uint256 amount1 = token.marketingAmount();

        assertGt(amount1, 0);

        // non marketing wallet reverts.
        vm.prank(user);

        vm.expectRevert("!marketingWallet");

        token.marketingAmount();

        // set new marketing wallet.
        address newMarketingWallet = vm.addr(2);

        token.setMarketingWallet(newMarketingWallet);

        // owner is still ok.
        uint256 amount2 = token.marketingAmount();

        assertEq(amount1, amount2);

        // new marketing wallet is ok.
        vm.prank(newMarketingWallet);

        uint256 amount3 = token.marketingAmount();

        assertEq(amount1, amount3);
    }

    function testWithdrawMarketing() public {
        address user = vm.addr(1);

        // test withdraw nothing.
        token.withdrawMarketing();

        assertEq(token.balanceOf(address(this)), 0);

        // test limits.
        buyToken(user, 1 ether);

        uint256 amount1 = token.marketingAmount();

        token.withdrawMarketing(0);

        assertEq(token.balanceOf(address(this)), 0);

        vm.expectRevert("!marketingAmount");

        token.withdrawMarketing(amount1 + 1);

        token.withdrawMarketing(amount1);

        assertEq(token.marketingAmount(), 0);
        assertEq(token.balanceOf(address(this)), amount1);

        // test full withdraw.
        buyToken(user, 1 ether);

        uint256 amount2 = token.marketingAmount();

        token.withdrawMarketing();

        assertEq(token.marketingAmount(), 0);
        assertEq(token.balanceOf(address(this)), amount1 + amount2);

        // test partial withdraw.
        buyToken(user, 1 ether);

        uint256 amount3 = token.marketingAmount();

        token.withdrawMarketing(amount3 / 2);

        assertEq(token.marketingAmount(), amount3 - (amount3 / 2));
        assertEq(token.balanceOf(address(this)), amount1 + amount2 + (amount3 / 2));

        // test non marketing wallet reverts.
        vm.prank(user);

        vm.expectRevert("!marketingWallet");

        token.withdrawMarketing();

        // set new marketing wallet.
        address newMarketingWallet = vm.addr(2);

        token.setMarketingWallet(newMarketingWallet);

        // test new marketing wallet withdraw.
        uint256 amount4 = token.marketingAmount();

        vm.prank(newMarketingWallet);

        token.withdrawMarketing();

        assertEq(token.marketingAmount(), 0);
        assertEq(token.balanceOf(newMarketingWallet), amount4);
    }
}
