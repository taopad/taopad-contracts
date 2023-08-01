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

        addLiquidity(1000 ether, token.totalSupply());

        token.enableTaxes();
    }

    function addLiquidity(uint256 ETHAmount, uint256 tokenAmount) private {
        vm.deal(address(this), ETHAmount);

        token.approve(address(router), tokenAmount);

        router.addLiquidityETH{value: ETHAmount}(
            address(token), tokenAmount, tokenAmount, ETHAmount, address(this), block.timestamp
        );
    }

    function buyToken(address addr, uint256 ETHAmount, uint256 minAmountOut) private {
        vm.deal(addr, ETHAmount);

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.prank(addr);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ETHAmount}(
            minAmountOut, path, addr, block.timestamp
        );
    }

    function sellToken(address addr, uint256 tokenAmount, uint256 minAmountOut) private {
        vm.prank(addr);

        token.approve(address(router), tokenAmount);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, minAmountOut, path, addr, block.timestamp
        );
    }

    function getAmountForETH(uint256 ETHAmount) private view returns (uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(router.WETH(), address(token)));

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        return (reserve0 * ETHAmount) / reserve1;
    }

    function getAmountForToken(uint256 tokenAmount) private view returns (uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(router.WETH(), address(token)));

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        return (reserve1 * tokenAmount) / reserve0;
    }

    function testTrue() public {
        assertTrue(true);
    }

    function testNoTaxCollectedAfterInitialLiq() public {
        assertEq(token.balanceOf(address(token)), 0);
    }

    function testSwapAreTaxed() public {
        address addr = vm.addr(1);

        vm.label(addr, "Buyer");

        // buy
        uint256 ethAmountToSell = 10 ether;

        uint256 tokenAmountForEth = getAmountForETH(ethAmountToSell);

        uint256 minTokenAmount = (tokenAmountForEth * 88) / 100;

        buyToken(addr, ethAmountToSell, minTokenAmount);

        // 10 eth should be worth 100 000 tokens.
        // minus taxes (10%) and slippage/swap fee then at least 89000 tokens.
        assertGe(minTokenAmount, 89000 * 10 * token.decimals());
        assertGe(token.balanceOf(addr), minTokenAmount);
        assertGe(token.balanceOf(address(token)), 8900 * 10 * token.decimals());

        // sell
        uint256 originalBalance = payable(addr).balance;

        uint256 tokenAmountToSell = 10000 * 10 ** token.decimals();

        uint256 ETHAmountForToken = getAmountForToken(tokenAmountToSell);

        uint256 minETHAmount = (ETHAmountForToken * 88) / 100;

        sellToken(addr, tokenAmountToSell, minETHAmount);

        assertGe(minTokenAmount, 0.88 ether);
        assertGe(payable(addr).balance, originalBalance + minETHAmount);
        assertGe(token.balanceOf(address(token)), 2 * 8900 * 10 * token.decimals());
    }
}
