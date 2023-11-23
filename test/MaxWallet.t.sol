// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract MaxWalletTest is ERC20RewardsTest {
    function testMaxWallet() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);
        address user4 = vm.addr(4);

        // cant buy more than 1% of supply by default.
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.deal(user1, 11 ether);

        vm.prank(user1);

        vm.expectRevert("UniswapV2: TRANSFER_FAILED");

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 11 ether}(0, path, user1, block.timestamp);

        // user dant be transfered more than 1% of supply.
        buyToken(user2, 1 ether);
        buyToken(user3, 10 ether);

        uint256 balance1 = token.balanceOf(user2);
        uint256 balance2 = token.balanceOf(user3);

        vm.prank(user2);

        token.transfer(user4, balance1);

        vm.prank(user3);

        vm.expectRevert("!maxWallet");

        token.transfer(user4, balance2);

        // non owner cant remove limits.
        vm.prank(user1);

        vm.expectRevert();

        token.removeLimits();

        // owner can remove limits.
        token.removeLimits();

        buyToken(user1, 11 ether);

        assertGt(token.balanceOf(user1), token.totalSupply() / 100);

        vm.prank(user3);

        token.transfer(user4, balance2);

        assertGt(token.balanceOf(user4), token.totalSupply() / 100);
    }
}
