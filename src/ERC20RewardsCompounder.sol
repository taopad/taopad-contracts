// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ERC20Rewards} from "./ERC20Rewards.sol";
import {IUniswapV3StaticQuoter} from "./IUniswapV3StaticQuoter.sol";

/// @title ERC20 rewards compounder
/// @author @niera26
/// @notice compounder for ERC20Rewards
/// @notice source: https://github.com/niera26/erc20-rewards-contracts
contract ERC20RewardsCompounder is Ownable, ERC4626, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // UniswapV3 Static Quoter (https://github.com/eden-network/uniswap-v3-static-quoter)
    IUniswapV3StaticQuoter public constant quoter = IUniswapV3StaticQuoter(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);

    // cache the ERC20Rewards values.
    ERC20Rewards private immutable token;
    IUniswapV2Router02 public immutable router;
    ISwapRouter public immutable swapRouter;
    IERC20 public immutable rewardToken;

    // Auto compound is triggered on deposit and redeem when pending rewards are
    // above this value. (Max value so it never triggers until owner sets it)
    uint256 public autocompoundThreshold = type(uint256).max;

    // events.
    event Compound(address indexed addr, uint256 rewards, uint256 assets);
    event Sweep(address indexed addr, address indexed token, uint256 amount);

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
     * Return pending rewards of this contract (take donations into account).
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
            _expected = _quoteRewardAsAsset(_rewardBalance);
        }

        return totalAssets() + _expected;
    }

    /**
     * Compound the rewards to more assets.
     *
     * Pass minimal expected amount to prevent slippage/frontrun.
     */
    function compound(uint256 amountOutMin) external nonReentrant {
        if (rewardBalance() == 0) return;

        _compound(amountOutMin);
    }

    /**
     * Override previewDeposit to take autocompounding into account.
     *
     * Same as original but with compoundedTotalAssets()
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), compoundedTotalAssets() + 1, Math.Rounding.Floor);
    }

    /**
     * Override previewRedeem to take autocompounding into account.
     *
     * Same as original but with compoundedTotalAssets()
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return shares.mulDiv(compoundedTotalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), Math.Rounding.Floor);
    }

    /**
     * Override deposit so it autocompounds when reward balance is above threshold.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        _compoundAboveThreshold();

        return super.deposit(assets, receiver);
    }

    /**
     * Override redeem so it autocompounds when reward balance is above threshold.
     */
    function redeem(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        _compoundAboveThreshold();

        return super.redeem(assets, receiver, owner);
    }

    /**
     * Sweep any other ERC20 mistakenly sent to this contract.
     */
    function sweep(IERC20 otherToken) external {
        require(address(otherToken) != address(token), "!sweep");
        require(address(otherToken) != address(rewardToken), "!sweep");

        uint256 amount = otherToken.balanceOf(address(this));

        otherToken.safeTransfer(msg.sender, amount);

        emit Sweep(msg.sender, address(otherToken), amount);
    }

    /**
     * Compound pending rewards when they are above threshold.
     */
    function _compoundAboveThreshold() private {
        if (rewardBalance() < autocompoundThreshold) return;

        _compound(0);
    }

    /**
     * Compound pending rewards into more assets.
     */
    function _compound(uint256 amountOutMin) private {
        token.claim(address(this));

        uint256 amountToCompound = rewardToken.balanceOf(address(this));

        if (amountToCompound == 0) return;

        _swapRewardToETHV3(address(this), amountToCompound, 0);

        uint256 ETHBalance = address(this).balance;

        if (ETHBalance == 0) return;

        uint256 swapped = _swapETHToAssetV2(address(this), ETHBalance, amountOutMin);

        if (swapped == 0) return;

        emit Compound(msg.sender, amountToCompound, swapped);
    }

    /**
     * Computes how many tokens will be swapped for the given amount of reward tokens.
     */
    function _quoteRewardAsAsset(uint256 amountIn) private view returns (uint256) {
        return _ETHAsAssetV2(_rewardAsETHV3(amountIn));
    }

    /**
     * Computes how many tokens will be swapped for the given amount of ETH.
     *
     * The current buy tax should be taken into account.
     */
    function _ETHAsAssetV2(uint256 amountIn) private view returns (uint256) {
        if (amountIn == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        uint256[] memory amountsOut = router.getAmountsOut(amountIn, path);

        uint256 taxAmount = (amountsOut[1] * token.buyFee()) / token.feeDenominator();

        return amountsOut[1] - taxAmount;
    }

    /**
     * Computes how many ETH will be swapped for the given amount of reward tokens.
     */
    function _rewardAsETHV3(uint256 amountIn) private view returns (uint256) {
        if (amountIn == 0) return 0;

        IUniswapV3StaticQuoter.QuoteExactInputSingleParams memory params = IUniswapV3StaticQuoter
            .QuoteExactInputSingleParams({
            tokenIn: address(rewardToken),
            tokenOut: router.WETH(),
            amountIn: amountIn,
            fee: token.poolFee(),
            sqrtPriceLimitX96: 0
        });

        return quoter.quoteExactInputSingle(params);
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
