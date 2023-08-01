// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";
import {IUniswapV2Pair} from "uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

contract SwapTest is Test {
    ERC20Rewards private token;
    IUniswapV2Router02 private router;

    function setUp() public {
        token = new ERC20Rewards("Reward token", "RTK", 1e7);

        router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    }

    function addLiquidity(uint256 ETHAmount, uint256 tokenAmount) private {
        vm.deal(address(this), ETHAmount);

        token.approve(address(router), tokenAmount);

        router.addLiquidityETH{value: ETHAmount}(
            address(token), tokenAmount, tokenAmount, ETHAmount, address(this), block.timestamp
        );
    }

    function buyToken(address addr, uint256 ETHAmountToSell) private {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.prank(addr);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ETHAmountToSell}(
            0, path, addr, block.timestamp
        );
    }

    function sellToken(address addr, uint256 tokenAmountToSell) private {
        vm.prank(addr);

        token.approve(address(router), tokenAmountToSell);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmountToSell, 0, path, addr, block.timestamp);
    }

    function getTokenAmountForETH(uint256 ETHAmount) private view returns (uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(router.WETH(), address(token)));

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        return (reserve0 * ETHAmount) / reserve1;
    }

    function getETHAmountForToken(uint256 tokenAmount) private view returns (uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(router.WETH(), address(token)));

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        return (reserve1 * tokenAmount) / reserve0;
    }

    // normalize given amount with token decimals.
    function norm(uint256 amount) private view returns (uint256) {
        return amount * 10 ** token.decimals();
    }

    function testNoTaxCollectedWhenTaxesAreNotEnabled() public {
        addLiquidity(1000 ether, token.totalSupply());

        assertEq(token.balanceOf(address(token)), 0);
    }

    function testBuyAreTaxed() public {
        // setup buyer.
        address buyer = vm.addr(1);

        vm.label(buyer, "Buyer");

        // give 1 ether to buyer.
        vm.deal(buyer, 1 ether);

        // add liq (1eth = 10 000 tokens) and enable taxes.
        addLiquidity(1000 ether, token.totalSupply());

        token.enableTaxes();

        // buy 10000 tokens (~ 1 eth).
        buyToken(buyer, 1 ether);

        // buyer should get 9000 tokens (10000 tokens minus 10% fee).
        // contract should collect 1000 tokens (10% of 10000 tokens).
        // 1000 as contract balance, 800 as rewards, 200 as marketing.
        // add 1% tolerance to account for swap fee/slippage.
        assertApproxEqRel(token.balanceOf(buyer), norm(9000), 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), norm(1000), 0.01e18);
        assertApproxEqRel(token.rewardFeeAmount(), norm(800), 0.01e18);
        assertApproxEqRel(token.marketingFeeAmount(), norm(200), 0.01e18);
    }

    function testSellAreTaxed() public {
        address seller = vm.addr(1);

        vm.label(seller, "Seller");

        // send some of the supply to seller so he can sell later.
        // (send 1 million so 9 million is put in liq)
        token.transfer(seller, norm(1e6));

        // add liq (1eth = 10 000 tokens) and enabled taxes.
        addLiquidity(900 ether, token.totalSupply() - norm(1e6));

        token.enableTaxes();

        // sell 10000 tokens (~ 1 eth).
        sellToken(seller, norm(10000));

        // seller should get 0.9 ethers (1 ether minus 10% fee).
        // contract should collect 1000 tokens (10% of 10000 tokens).
        // 1000 as contract balance, 800 as rewards, 200 as marketing.
        // add 1% tolerance to account for swap fee/slippage.
        assertApproxEqRel(payable(seller).balance, 0.9 ether, 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), norm(1000), 0.01e18);
        assertApproxEqRel(token.rewardFeeAmount(), norm(800), 0.01e18);
        assertApproxEqRel(token.marketingFeeAmount(), norm(200), 0.01e18);
    }
}
