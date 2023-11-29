// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20RewardsTest, ERC20Mock} from "./ERC20RewardsTest.t.sol";

contract SweepTest is ERC20RewardsTest {
    function testTokenSweep() public {
        IERC20 randomToken = new ERC20Mock(1000);

        address user = vm.addr(1);

        // put token and reward token in the contract.
        buyToken(user, 1 ether);
        buyRewardToken(user, 1 ether);

        vm.startPrank(user);
        token.transfer(address(token), token.balanceOf(address(user)));
        rewardToken.transfer(address(token), rewardToken.balanceOf(address(user)));
        vm.stopPrank();

        assertGt(token.balanceOf(address(token)), 0);
        assertGt(rewardToken.balanceOf(address(token)), 0);

        // owner cant sweep token.
        vm.expectRevert("!sweep");

        token.sweep(token);

        // owner cant sweep reward token.
        vm.expectRevert("!sweep");

        token.sweep(rewardToken);

        // user cant sweep token.
        vm.prank(user);

        vm.expectRevert("!sweep");

        token.sweep(token);

        // user cant sweep reward token.
        vm.prank(user);

        vm.expectRevert("!sweep");

        token.sweep(rewardToken);

        // owner can sweep random token.
        randomToken.transfer(address(token), 1000);

        assertEq(randomToken.balanceOf(address(this)), 0);
        assertEq(randomToken.balanceOf(address(token)), 1000);

        token.sweep(randomToken);

        assertEq(randomToken.balanceOf(address(this)), 1000);
        assertEq(randomToken.balanceOf(address(token)), 0);

        // user can sweep random token.
        randomToken.transfer(address(token), 1000);

        assertEq(randomToken.balanceOf(address(user)), 0);
        assertEq(randomToken.balanceOf(address(token)), 1000);

        vm.prank(user);

        token.sweep(randomToken);

        assertEq(randomToken.balanceOf(address(user)), 1000);
        assertEq(randomToken.balanceOf(address(token)), 0);
    }
}
