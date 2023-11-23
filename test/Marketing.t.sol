// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract MarketingTest is ERC20RewardsTest {
    function testSetMarketingWallet() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // by default the marketing wallet is deployer.
        assertEq(token.marketingWallet(), address(this));

        // owner can set a new marketing wallet.
        token.setMarketingWallet(user1);

        assertEq(token.marketingWallet(), user1);

        // non owner reverts.
        vm.prank(user2);

        vm.expectRevert();

        token.setMarketingWallet(user3);
    }
}
