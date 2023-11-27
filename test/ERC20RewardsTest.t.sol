// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";
import {ERC20RewardsCompounder} from "../src/ERC20RewardsCompounder.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract ERC20RewardsTest is Test {
    ERC20Rewards internal token;
    IUniswapV2Router02 internal router;
    IERC20Metadata internal rewardToken;
    ERC20RewardsCompounder internal compounder;

    function setUp() public {
        vm.deal(address(this), 1000 ether);

        token = new ERC20Rewards("Reward token", "RTK");
        compounder = new ERC20RewardsCompounder("Wrapped reward token", "wRTK", token);

        router = token.router();
        rewardToken = token.rewardToken();

        token.initialize{value: 1000 ether}(1e6);
        token.setBuyFee(400, 100);
        token.setSellFee(800, 200);

        vm.roll(block.number + token.deadBlocks() + 1);
    }

    function addLiquidity(address addr, uint256 amountETHDesired, uint256 amountTokenDesired) internal {
        vm.deal(addr, amountETHDesired);

        vm.prank(addr);

        token.approve(address(router), amountTokenDesired);

        vm.prank(addr);

        router.addLiquidityETH{value: amountETHDesired}(address(token), amountTokenDesired, 0, 0, addr, block.timestamp);
    }

    function removeLiquidity(address addr) internal {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(token), router.WETH()));

        uint256 liquidity = pair.balanceOf(addr);

        vm.prank(addr);

        pair.approve(address(router), liquidity);

        vm.prank(addr);

        router.removeLiquidityETHSupportingFeeOnTransferTokens(address(token), liquidity, 0, 0, addr, block.timestamp);
    }

    function buyToken(address addr, uint256 amountETHExact) internal {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.deal(addr, amountETHExact);

        vm.prank(addr);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountETHExact}(0, path, addr, block.timestamp);
    }

    function sellToken(address addr, uint256 exactTokenAmount) internal {
        vm.prank(addr);

        token.approve(address(router), exactTokenAmount);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(exactTokenAmount, 0, path, addr, block.timestamp);
    }

    // normalize given amount with token decimals.
    function norm(uint256 amount) internal view returns (uint256) {
        return amount * 10 ** token.decimals();
    }

    receive() external payable {}
}
