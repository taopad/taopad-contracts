// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract BurnTest is ERC20RewardsTest {
    function testBurn() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        uint256 totalSupply = token.totalSupply();

        buyToken(user1, 1 ether);
        buyToken(user2, 1 ether);

        uint256 user1Balance = token.balanceOf(user1);
        uint256 user2Balance = token.balanceOf(user2);
        uint256 contractBalance = token.balanceOf(address(token));

        assertEq(token.totalShares(), user1Balance + user2Balance);

        // partial burn.
        vm.prank(user2);

        token.burn(user2Balance / 2);

        assertEq(token.balanceOf(address(token)), contractBalance);
        assertEq(token.totalSupply(), totalSupply - (user2Balance / 2));
        assertEq(token.totalShares(), user1Balance + user2Balance - (user2Balance / 2));

        // total burn.
        uint256 newUser2Balance = token.balanceOf(user2);

        vm.prank(user2);

        token.burn(newUser2Balance);

        assertEq(token.balanceOf(address(token)), contractBalance);
        assertEq(token.totalSupply(), totalSupply - user2Balance);
        assertEq(token.totalShares(), user1Balance);
    }
}
