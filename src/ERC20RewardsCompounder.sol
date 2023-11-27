// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ERC20Rewards} from "./ERC20Rewards.sol";

contract ERC20RewardsCompounder is ERC4626, ReentrancyGuard {
    // cache the ERC20Rewards values.
    ERC20Rewards private immutable token;
    IUniswapV2Router02 public immutable router;
    ISwapRouter public immutable swapRouter;
    IERC20 public immutable rewardToken;

    // events.
    event Compound(address indexed addr, uint256 amount);

    /**
     * Cache ERC20Rewards values and optin for rewards so this contract earn rewards.
     */
    constructor(string memory name, string memory symbol, ERC20Rewards asset) ERC20(name, symbol) ERC4626(asset) {
        token = asset;
        router = token.router();
        swapRouter = token.swapRouter();
        rewardToken = token.rewardToken();

        token.rewardOptin();
    }

    /**
     * Return pending rewards of this contract.
     */
    function pendingRewards() public view returns (uint256) {
        return token.pendingRewards(address(this));
    }

    /**
     * Compound the rewards to more ERC20Rewards.
     */
    function compound() external nonReentrant {
        if (pendingRewards() == 0) return;

        // claim pending rewards.
        token.claim();

        // swap everyting back to ERC20Rewards.
        uint256 rewardBalance = rewardToken.balanceOf(address(this));

        if (rewardBalance == 0) return;

        _swapERC20ToETHV3(address(this), rewardBalance, 0);

        uint256 ETHBalance = address(this).balance;

        if (ETHBalance == 0) return;

        uint256 swapped = _swapETHToTokenV2(address(this), ETHBalance, 0);

        if (swapped == 0) return;

        emit Compound(msg.sender, swapped);
    }

    /**
     * Swap amount of ETH for assets to address and return the amount received.
     */
    function _swapETHToTokenV2(address to, uint256 amountIn, uint256 amountOutMin) private returns (uint256) {
        // return 0 if no amount given.
        if (amountIn == 0) return 0;

        // keep the original asset balance to compute the swapped amount.
        uint256 originalBalance = totalAssets();

        // swap the whole WETH amount to asset.
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutMin, path, to, block.timestamp
        );

        // return the received amount.
        return totalAssets() - originalBalance;
    }

    /**
     * Swap amount of reward tokens for ETH to address and return the amount received.
     */
    function _swapERC20ToETHV3(address to, uint256 amountIn, uint256 amountOutMinimum) private returns (uint256) {
        // return 0 if no amount given.
        if (amountIn == 0) return 0;

        // keep the original ETH balance to compute the swapped amount.
        uint256 originalBalance = address(this).balance;

        // approve router to spend reward tokens.
        rewardToken.approve(address(swapRouter), amountIn);

        // build the swap parameter.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(rewardToken),
            tokenOut: router.WETH(),
            fee: token.poolFee(),
            recipient: to,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // execute the swap.
        swapRouter.exactInputSingle(params);

        // unwrap the received WETH.
        uint256 WETHBalance = IERC20(router.WETH()).balanceOf(address(this));

        IWETH(router.WETH()).withdraw(WETHBalance);

        // return the amount of swapped ETH.
        return address(this).balance - originalBalance;
    }

    /**
     * This contract cant receive ETH except from WETH.
     */
    receive() external payable {
        require(msg.sender == router.WETH(), "cannot send eth to this contract");
    }
}
