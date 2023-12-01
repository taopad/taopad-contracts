// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20RewardsTest, ERC20Mock} from "./ERC20RewardsTest.t.sol";

contract MiscTest is ERC20RewardsTest {
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

        // user dant be transfered more than 1% of supply.
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

    function testLastUpdateBlock() public {
        address user = vm.addr(1);

        uint256 newBlock1 = block.number + 1000;
        uint256 newBlock2 = block.number + 2000;

        vm.roll(newBlock1);

        buyToken(user, 1 ether);

        assertEq(token.lastUpdateBlock(user), newBlock1);

        vm.roll(newBlock2);

        buyToken(user, 1 ether);

        assertEq(token.lastUpdateBlock(user), newBlock2);
    }
}
