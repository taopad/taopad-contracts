// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Taopad} from "../src/Taopad.sol";

contract InitializeTest is Test {
    function testInitialize() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);
        address user4 = vm.addr(4);

        // deploy the contract.
        Taopad token = new Taopad();

        // contract has all supply.
        uint256 decimalConst = 10 ** token.decimals();

        uint256 totalSupply = 1e6 * decimalConst;

        assertEq(token.totalSupply(), totalSupply);
        assertEq(token.totalShares(), 0);
        assertEq(token.balanceOf(address(token)), totalSupply);

        // send allocations.
        uint256 alloc1 = 10_000 * decimalConst;
        uint256 alloc2 = 20_000 * decimalConst;
        uint256 alloc3 = 30_000 * decimalConst;

        token.allocate(user1, alloc1);
        token.allocate(user2, alloc2);
        token.allocate(user3, alloc3);

        assertEq(token.startBlock(), 0);
        assertEq(token.maxWallet(), type(uint256).max);
        assertEq(token.totalSupply(), totalSupply);
        assertEq(token.totalShares(), alloc1 + alloc2 + alloc3);
        assertEq(token.balanceOf(address(token)), totalSupply - alloc1 - alloc2 - alloc3);
        assertEq(token.balanceOf(user1), alloc1);
        assertEq(token.balanceOf(user2), alloc2);
        assertEq(token.balanceOf(user3), alloc3);
        assertFalse(token.isBlacklisted(user1));
        assertFalse(token.isBlacklisted(user2));
        assertFalse(token.isBlacklisted(user3));

        // allocate with non owner reverts.
        vm.prank(user1);

        vm.expectRevert();

        token.allocate(user4, 1);

        // initialize the trading.
        vm.roll(block.number + 1);

        vm.deal(address(this), 1000 ether);

        token.initialize{value: 1000 ether}();

        // check it is all fine.
        assertEq(token.startBlock(), block.number);
        assertEq(token.maxWallet(), totalSupply / 100);
        assertEq(token.totalSupply(), totalSupply);
        assertEq(token.totalShares(), alloc1 + alloc2 + alloc3);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(user1), alloc1);
        assertEq(token.balanceOf(user2), alloc2);
        assertEq(token.balanceOf(user3), alloc3);
        assertFalse(token.isBlacklisted(user1));
        assertFalse(token.isBlacklisted(user2));
        assertFalse(token.isBlacklisted(user3));

        // now allocate with owner reverts.
        vm.expectRevert("!initialized");

        token.allocate(user4, 1);
    }
}
