// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20RewardsTest} from "./ERC20RewardsTest.t.sol";

contract FeeTest is ERC20RewardsTest {
    function testSetFee() public {
        address user = vm.addr(1);

        uint256 maxBuyFee = token.maxBuyFee();
        uint256 maxSellFee = token.maxBuyFee();

        // non owner reverts.
        vm.prank(user);

        vm.expectRevert();

        token.setBuyFee(100, 100);

        vm.prank(user);

        vm.expectRevert();

        token.setSellFee(100, 100);

        // more than max fee reverts.
        vm.expectRevert("!maxBuyFee");
        token.setBuyFee(maxBuyFee + 1, 0);
        vm.expectRevert("!maxBuyFee");
        token.setBuyFee(0, maxBuyFee + 1);
        vm.expectRevert("!maxBuyFee");
        token.setBuyFee(maxBuyFee / 2, (maxBuyFee / 2) + 1);
        vm.expectRevert("!maxSellFee");
        token.setSellFee(maxSellFee + 1, 0);
        vm.expectRevert("!maxSellFee");
        token.setSellFee(0, maxSellFee + 1);
        vm.expectRevert("!maxSellFee");
        token.setSellFee(maxSellFee / 2, (maxSellFee / 2) + 1);
    }

    function testBuySellTax() public {
        address user = vm.addr(1);

        // put random taxes.
        token.setBuyFee(721, 279); // 1000
        token.setSellFee(1356, 644); // 2000

        buyToken(user, 1 ether);

        uint256 balance = token.balanceOf(user);

        // 10% was taken on buy (so we have 90% of tokens).
        uint256 buyTax = balance / 9;

        // 20% will be taken on sell.
        uint256 sellTax = balance / 5;

        assertApproxEqRel(token.balanceOf(address(token)), buyTax, 0.01e18);

        sellToken(user, balance);

        assertApproxEqRel(token.balanceOf(address(token)), buyTax + sellTax, 0.01e18);
    }
}
