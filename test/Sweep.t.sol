// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(uint256 _totalSupply) ERC20("R", "R") {
        _mint(msg.sender, _totalSupply);
    }
}

contract SweepTest is ERC20RewardsTest {
    function testSweep() public {
        IERC20 randomToken = new ERC20Mock(1000);

        address user = vm.addr(1);

        // put token and reward token in the contract.
        buyToken(user, 1 ether);

        token.distribute();

        buyToken(user, 1 ether);

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
