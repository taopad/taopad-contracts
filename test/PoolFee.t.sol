// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract PoolFeeTest is ERC20RewardsTest {
    function testSetPoolFee() public {
        address user = vm.addr(1);

        // by default the pool fee is 10000.
        assertEq(token.poolFee(), 10000);

        // owner can set a new pool fee.
        token.setPoolFee(5000);

        assertEq(token.poolFee(), 5000);

        // non owner reverts.
        vm.prank(user);

        vm.expectRevert();

        token.setPoolFee(100);
    }
}
