// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";

contract DummyContract {
    ERC20Rewards private token;

    constructor(ERC20Rewards _token) {
        token = _token;
    }

    function rewardOptin() external {
        token.rewardOptin();
    }

    function rewardOptout() external {
        token.rewardOptout();
    }

    function claim(address to) external {
        token.claim(to);
    }
}

contract ContractsTest is ERC20RewardsTest {
    function testContractOptinOptout() public {
        address user = vm.addr(1);

        DummyContract dummy = new DummyContract(token);

        // contracts have no shares by default.
        buyToken(user, 1 ether);

        uint256 balance = token.balanceOf(user);

        vm.prank(user);

        token.transfer(address(dummy), balance / 2);

        assertEq(token.totalShares(), token.balanceOf(user));

        token.swapCollectedTax(0);
        token.distribute(0);

        uint256 userPendingRewards = token.pendingRewards(user);
        uint256 contractPendingRewards = token.pendingRewards(address(dummy));

        assertGt(userPendingRewards, 0);
        assertEq(contractPendingRewards, 0);

        // contracts can optin for rewards.
        dummy.rewardOptin();

        assertEq(token.totalShares(), token.balanceOf(user) + token.balanceOf(address(dummy)));

        // contracts can optin twice with no problem.
        dummy.rewardOptin();

        assertEq(token.totalShares(), token.balanceOf(user) + token.balanceOf(address(dummy)));

        // distribute more, contract gets rewards.
        buyToken(user, 1 ether);

        token.swapCollectedTax(0);
        token.distribute(0);

        assertGt(token.pendingRewards(user), userPendingRewards);
        assertGt(token.pendingRewards(address(dummy)), 0);

        userPendingRewards = token.pendingRewards(user);
        contractPendingRewards = token.pendingRewards(address(dummy));

        // contracts can optout of rewards.
        dummy.rewardOptout();

        assertEq(token.totalShares(), token.balanceOf(user));

        // contracts can optin twice with no problem.
        dummy.rewardOptout();

        assertEq(token.totalShares(), token.balanceOf(user));

        // distribute more, contract gets no rewards anymore.
        buyToken(user, 1 ether);

        token.swapCollectedTax(0);
        token.distribute(0);

        assertGt(token.pendingRewards(user), userPendingRewards);
        assertEq(token.pendingRewards(address(dummy)), contractPendingRewards);

        userPendingRewards = token.pendingRewards(user);

        // ensure both can claim.
        vm.prank(user);

        token.claim(user);

        dummy.claim(address(dummy));

        assertEq(rewardToken.balanceOf(user), userPendingRewards);
        assertEq(rewardToken.balanceOf(address(dummy)), contractPendingRewards);
    }
}
