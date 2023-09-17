// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";
import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

contract ERC20RewardsTest is Test {
    ERC20Rewards internal token;
    IUniswapV2Router02 internal router;

    function setUp() public {
        token = new ERC20Rewards("Reward token", "RTK", 1e7);

        router = token.router();
    }

    function addLiquidity(uint256 ETHAmount, uint256 tokenAmount) internal {
        vm.deal(address(this), ETHAmount);

        token.approve(address(router), tokenAmount);

        router.addLiquidityETH{value: ETHAmount}(
            address(token), tokenAmount, tokenAmount, ETHAmount, address(this), block.timestamp
        );
    }

    function buyToken(address addr, uint256 ETHAmountToSell) internal {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.prank(addr);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ETHAmountToSell}(
            0, path, addr, block.timestamp
        );
    }

    function sellToken(address addr, uint256 tokenAmountToSell) internal {
        vm.prank(addr);

        token.approve(address(router), tokenAmountToSell);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmountToSell, 0, path, addr, block.timestamp);
    }

    // normalize given amount with token decimals.
    function norm(uint256 amount) internal view returns (uint256) {
        return amount * 10 ** token.decimals();
    }
}
