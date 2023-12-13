// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20RewardsTest, ERC20Mock} from "./ERC20RewardsTest.t.sol";

contract MiscTest is ERC20RewardsTest {
    function testSetOperator() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        // by default operator is owner.
        assertEq(token.operator(), address(this));

        // by default owner can set operator.
        token.setOperator(user1);

        assertEq(token.operator(), user1);

        // operator can set operator.
        vm.prank(user1);

        token.setOperator(user2);

        assertEq(token.operator(), user2);

        // owner now reverts.
        vm.expectRevert("!operator");

        token.setOperator(user3);

        // user reverts.
        vm.prank(user1);

        vm.expectRevert("!operator");

        token.setOperator(user3);

        // zero address reverts.
        vm.prank(user2);

        vm.expectRevert("!address");

        token.setOperator(address(0));
    }

    function testSetPoolFee() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        // by default the pool fee is 10000.
        assertEq(token.poolFee(), 10000);

        // by default owner can set pool fee.
        token.setPoolFee(5000);

        assertEq(token.poolFee(), 5000);

        // set new operator.
        token.setOperator(user1);

        // operator can set pool fee.
        vm.prank(user1);

        token.setPoolFee(4000);

        assertEq(token.poolFee(), 4000);

        // owner now revert.
        vm.expectRevert("!operator");

        token.setPoolFee(3000);

        // non operator reverts.
        vm.prank(user2);

        vm.expectRevert("!operator");

        token.setPoolFee(3000);
    }

    function testSetFee() public {
        address user = vm.addr(1);

        uint24 maxSwapFee = token.maxSwapFee();
        uint24 maxMarketingFee = token.maxMarketingFee();

        // default fee is 24%, 24%, 80%
        assertEq(token.buyFee(), 2400);
        assertEq(token.sellFee(), 2400);
        assertEq(token.marketingFee(), 8000);

        // owner can set fee.
        token.setFee(101, 102, 103);

        assertEq(token.buyFee(), 101);
        assertEq(token.sellFee(), 102);
        assertEq(token.marketingFee(), 103);

        // non owner reverts.
        vm.prank(user);

        vm.expectRevert();

        token.setFee(101, 102, 103);

        // more than max fee reverts.
        vm.expectRevert("!buyFee");
        token.setFee(maxSwapFee + 1, 0, 0);
        vm.expectRevert("!sellFee");
        token.setFee(0, maxSwapFee + 1, 0);
        vm.expectRevert("!marketingFee");
        token.setFee(0, 0, maxMarketingFee + 1);
    }

    function testBuySellTax() public {
        address user = vm.addr(1);

        // put random taxes.
        token.setFee(1000, 2000, 0);

        buyToken(user, 1 ether);

        uint256 balance = token.balanceOf(user);

        // 10% was taken on buy (so we have 90% of tokens).
        uint256 buyTax = balance / 9;

        // 20% will be taken on sell.
        uint256 sellTax = balance / 5;

        assertApproxEqRel(token.balanceOf(address(token)), buyTax, 0.01e18);

        sellToken(user, balance);

        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqRel(address(token).balance, (buyTax + sellTax) / 1000, 0.01e18);
    }

    function testMaxWallet() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);
        address user4 = vm.addr(4);

        // cant buy more than 1% of supply by default.
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.deal(user1, 14 ether);

        vm.prank(user1);

        vm.expectRevert("UniswapV2: TRANSFER_FAILED");

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 14 ether}(0, path, user1, block.timestamp);

        // user cant be transfered more than 1% of supply.
        buyToken(user2, 1 ether);
        buyToken(user3, 13 ether);

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

        buyToken(user1, 14 ether);

        assertGt(token.balanceOf(user1), token.totalSupply() / 100);

        vm.prank(user3);

        token.transfer(user4, balance2);

        assertGt(token.balanceOf(user4), token.totalSupply() / 100);
    }

    function testClaimToAnotherAddress() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        // both users buy tokens.
        buyToken(user1, 1 ether);
        buyToken(user2, 2 ether);

        // distribute the rewards.
        token.swapCollectedTax(0);
        token.distribute(0);

        // users have pending rewards.
        uint256 pendingRewards1 = token.pendingRewards(user1);
        uint256 pendingRewards2 = token.pendingRewards(user2);

        assertGt(pendingRewards1, 0);
        assertGt(pendingRewards2, 0);

        // user1 claims
        vm.prank(user1);

        token.claim(user1);

        assertEq(rewardToken.balanceOf(user1), pendingRewards1);

        // user2 claims to user1.
        vm.prank(user2);

        token.claim(user1);

        assertEq(rewardToken.balanceOf(user1), pendingRewards1 + pendingRewards2);
        assertEq(rewardToken.balanceOf(user2), 0);
    }

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
        uint256 amountToBurn = user2Balance / 2;
        uint256 remainingAmount = user2Balance - amountToBurn;

        vm.prank(user2);

        token.burn(amountToBurn);

        assertEq(token.balanceOf(address(user2)), remainingAmount);
        assertEq(token.balanceOf(address(token)), contractBalance);
        assertEq(token.totalSupply(), totalSupply - amountToBurn);
        assertEq(token.totalShares(), user1Balance + remainingAmount);

        // total burn.
        vm.prank(user2);

        token.burn(remainingAmount);

        assertEq(token.balanceOf(address(user2)), 0);
        assertEq(token.balanceOf(address(token)), contractBalance);
        assertEq(token.totalSupply(), totalSupply - user2Balance);
        assertEq(token.totalShares(), user1Balance);
    }

    function testTokenSweep() public {
        IERC20 randomToken = new ERC20Mock(1000);

        address user = vm.addr(1);

        // put token and reward token in the contract.
        buyToken(user, 1 ether);
        buyRewardToken(user, 1 ether);

        vm.startPrank(user);
        token.transfer(address(token), token.balanceOf(address(user)));
        rewardToken.transfer(address(token), rewardToken.balanceOf(address(user)));
        vm.stopPrank();

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

    function testDeadWalletDoesNotGetShares() public {
        address user = vm.addr(1);

        address dead = 0x000000000000000000000000000000000000dEaD;

        buyToken(user, 1 ether);

        uint256 balance = token.balanceOf(user);

        assertGt(balance, 0);
        assertEq(token.totalShares(), balance);

        vm.prank(user);

        token.transfer(dead, balance);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalShares(), 0);
        assertEq(token.balanceOf(dead), balance);
    }
}
