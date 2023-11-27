// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";
import {ERC20RewardsCompounder} from "../src/ERC20RewardsCompounder.sol";

contract CompounderTest is ERC20RewardsTest {
    function testCompounder() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        ERC20RewardsCompounder compounder = new ERC20RewardsCompounder("Wrapped reward token", "wRTK", token);

        assertTrue(token.isOptin(address(compounder)));

        uint256 pendingRewards = compounder.pendingRewards();

        assertEq(pendingRewards, 0);

        // buy some tokens, distribute and claim.
        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);

        token.distribute();

        vm.prank(user1);

        token.claim();

        vm.prank(user2);

        token.claim();

        assertGt(rewardToken.balanceOf(user1), 0);
        assertGt(rewardToken.balanceOf(user2), 0);

        // stack in the compounder.
        uint256 balance1 = token.balanceOf(user1);
        uint256 balance2 = token.balanceOf(user2);

        vm.startPrank(user1);
        token.approve(address(compounder), balance1);
        compounder.deposit(balance1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(compounder), balance2);
        compounder.deposit(balance2, user2);
        vm.stopPrank();

        assertGt(compounder.balanceOf(user1), 0);
        assertGt(compounder.balanceOf(user2), 0);
        assertEq(compounder.pendingRewards(), 0);
        assertEq(compounder.totalAssets(), balance1 + balance2);

        // distribute more rewards.
        buyToken(user3, 1 ether);

        token.distribute();

        assertGt(compounder.pendingRewards(), 0);

        // compound the rewards.
        compounder.compound();

        assertEq(compounder.pendingRewards(), 0);
        assertEq(rewardToken.balanceOf(address(compounder)), 0);
        assertEq(IERC20(router.WETH()).balanceOf(address(compounder)), 0);
        assertGt(compounder.totalAssets(), balance1 + balance2);

        // user can now redeem more tokens.
        uint256 shareBalance1 = compounder.balanceOf(user1);
        uint256 shareBalance2 = compounder.balanceOf(user2);

        vm.startPrank(user1);
        compounder.approve(address(compounder), shareBalance1);
        compounder.redeem(shareBalance1, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        compounder.approve(address(compounder), shareBalance2);
        compounder.redeem(shareBalance2, user2, user2);
        vm.stopPrank();

        assertGt(token.balanceOf(user1), balance1);
        assertGt(token.balanceOf(user2), balance2);
        assertApproxEqAbs(compounder.totalAssets(), 0, 1); // account for dust
    }
}
