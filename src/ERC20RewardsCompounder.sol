// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ERC20Rewards} from "./ERC20Rewards.sol";

/// @title ERC20 rewards compounder
/// @author @niera26
/// @notice compounder for ERC20Rewards
/// @notice source: https://github.com/niera26/erc20-rewards-contracts
contract ERC20RewardsCompounder is Ownable, ERC4626, ReentrancyGuard {
    using Math for uint256;

    // UniswapV3 Quoter
    IQuoter public constant quoter = IQuoter(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    // cache the ERC20Rewards values.
    ERC20Rewards private immutable token;
    IUniswapV2Router02 public immutable router;
    ISwapRouter public immutable swapRouter;
    IERC20 public immutable rewardToken;

    // Auto compound is triggered on deposit and redeem when pending rewards are
    // above this value.
    // Max value so it does not trigger until owner sets it.
    uint256 public autocompoundThreshold = type(uint256).max;

    // events.
    event Compound(address indexed addr, uint256 rewards, uint256 assets);

    /**
     * Cache ERC20Rewards values and optin for rewards so this contract earn rewards.
     */
    constructor(string memory name, string memory symbol, ERC20Rewards asset)
        Ownable(msg.sender)
        ERC20(name, symbol)
        ERC4626(asset)
    {
        token = asset;
        router = token.router();
        swapRouter = token.swapRouter();
        rewardToken = token.rewardToken();

        token.rewardOptin();
    }

    /**
     * Set the autocompound threshold.
     */
    function setAutocompoundTheshold(uint256 _autocompoundThreshold) external onlyOwner {
        autocompoundThreshold = _autocompoundThreshold;
    }

    /**
     * Return pending rewards of this contract (take account of the donations to this contract).
     */
    function rewardBalance() public view returns (uint256) {
        return token.pendingRewards(address(this)) + rewardToken.balanceOf(address(this));
    }

    /**
     * Return totalAssets in the vault + amount to be received on autocompound.
     */
    function compoundedTotalAssets() public view returns (uint256) {
        uint256 _expected;
        uint256 _rewardBalance = rewardBalance();

        if (_rewardBalance >= autocompoundThreshold) {
            _expected = _quoteRewardTokenAsAsset(_rewardBalance);
        }

        return totalAssets() + _expected;
    }

    /**
     * Compound the rewards to more ERC20Rewards.
     */
    function compound() external nonReentrant {
        if (rewardBalance() == 0) return;

        _compound();
    }

    /**
     * Override previewDeposit to take autocompounding into account.
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToSharesCompound(assets, Math.Rounding.Floor);
    }

    /**
     * Override previewRedeem to take autocompounding into account.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _convertToAssetsCompound(shares, Math.Rounding.Floor);
    }

    /**
     * Override deposit so it auto compounds when pending rewards are above threshold.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        _compoundAboveThreshold();

        return super.deposit(assets, receiver);
    }

    /**
     * Override redeem so it auto compounds when pending rewards are above threshold.
     */
    function redeem(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        _compoundAboveThreshold();

        return super.redeem(assets, receiver, owner);
    }

    /**
     * Convert assets to shares accounting for autocompounding.
     */
    function _convertToSharesCompound(uint256 assets, Math.Rounding rounding) private view returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), compoundedTotalAssets() + 1, rounding);
    }

    /**
     * Convert shares to assets accounting for autocompounding.
     */
    function _convertToAssetsCompound(uint256 shares, Math.Rounding rounding) private view returns (uint256) {
        return shares.mulDiv(compoundedTotalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /**
     * Compound pending rewards when they are above threshold.
     */
    function _compoundAboveThreshold() private {
        if (rewardBalance() < autocompoundThreshold) return;

        _compound();
    }

    /**
     * Compound pending rewards into more assets.
     */
    function _compound() private {
        token.claim();

        uint256 amountToCompound = rewardToken.balanceOf(address(this));

        if (amountToCompound == 0) return;

        _swapRewardToETHV3(address(this), amountToCompound, 0);

        uint256 ETHBalance = address(this).balance;

        if (ETHBalance == 0) return;

        uint256 swapped = _swapETHToAssetV2(address(this), ETHBalance, 0);

        if (swapped == 0) return;

        emit Compound(msg.sender, amountToCompound, swapped);
    }

    /**
     * Computes how many tokens will be swapped for the given amount of reward tokens.
     */
    function _quoteRewardTokenAsAsset(uint256 amountIn) private view returns (uint256) {
        return _ETHAsAssetV2(_rewardAsETHV3(amountIn));
    }

    /**
     * Computes how many tokens will be swapped for the given amount of ETH.
     */
    function _ETHAsAssetV2(uint256 amountIn) private view returns (uint256) {
        if (amountIn == 0) return 0;

        // path from WETH to asset.
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        uint256[] memory amountsOut = router.getAmountsOut(amountIn, path);

        return amountsOut[0];
    }

    /**
     * Computes how many ETH will be swapped for the given amount of reward tokens.
     */
    function _rewardAsETHV3(uint256 amountIn) private pure returns (uint256) {
        if (amountIn == 0) return 0;

        return 0;
    }

    /**
     * Swap amount of ETH for assets to address and return the amount received.
     */
    function _swapETHToAssetV2(address to, uint256 amountIn, uint256 amountOutMin) private returns (uint256) {
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
    function _swapRewardToETHV3(address to, uint256 amountIn, uint256 amountOutMinimum) private returns (uint256) {
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
