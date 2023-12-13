// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {Taopad} from "../src/Taopad.sol";

contract ERC20Mock is ERC20 {
    constructor(uint256 _totalSupply) ERC20("R", "R") {
        _mint(msg.sender, _totalSupply);
    }
}

contract ERC20RewardsTest is Test {
    Taopad internal token;
    IUniswapV2Router02 internal router;
    ISwapRouter internal swapRouter;
    IERC20Metadata internal rewardToken;

    function setUp() public {
        vm.deal(address(this), 1000 ether);

        token = new Taopad();

        router = token.router();
        swapRouter = token.swapRouter();
        rewardToken = token.rewardToken();

        token.initialize{value: 1000 ether}();

        vm.roll(block.number + token.deadBlocks() + 1);
    }

    function withDecimals(uint256 amount) internal view returns (uint256) {
        return amount * 10 ** token.decimals();
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

    function buyRewardToken(address addr, uint256 amountIn) internal {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: router.WETH(),
            tokenOut: address(rewardToken),
            fee: token.poolFee(),
            recipient: addr,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.deal(addr, amountIn);

        vm.prank(addr);

        swapRouter.exactInputSingle{value: amountIn}(params);
    }

    function addRewards(uint256 amountIn) internal returns (uint256, uint256) {
        buyRewardToken(address(this), amountIn);

        uint256 balance = rewardToken.balanceOf(address(this));
        uint256 donated = balance / 10;
        uint256 remaining = balance - donated;

        token.setRewardTokenPerBlock(donated);

        rewardToken.transfer(address(token), rewardToken.balanceOf(address(this)));

        vm.roll(block.number + 1);

        return (donated, remaining);
    }

    receive() external payable {}
}
