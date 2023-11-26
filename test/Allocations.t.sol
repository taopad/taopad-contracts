// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";

contract AllocationsTest is Test {
    // setup allocations (250k tokens to test max wallet).
    address[] addrs = [vm.addr(1), vm.addr(2), vm.addr(3)];
    uint256[] allocs = [125_000, 100_000, 25_000];

    function testInitializeWithAllocations() public {
        vm.deal(address(this), 1000 ether);

        // deploy the contract.
        ERC20Rewards token = new ERC20Rewards("Reward token", "RTK");

        // initialize with 1m tokens.
        token.initialize{value: 1000 ether}(1e6, addrs, allocs);

        // test balances.
        uint256 decimalScale = 10 ** token.decimals();

        uint256 balance1 = token.balanceOf(addrs[0]);
        uint256 balance2 = token.balanceOf(addrs[1]);
        uint256 balance3 = token.balanceOf(addrs[2]);

        assertEq(balance1, allocs[0] * decimalScale);
        assertEq(balance2, allocs[1] * decimalScale);
        assertEq(balance3, allocs[2] * decimalScale);
        assertFalse(token.isBlacklisted(addrs[0]));
        assertFalse(token.isBlacklisted(addrs[1]));
        assertFalse(token.isBlacklisted(addrs[2]));
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalShares(), balance1 + balance2 + balance3);
    }
}
