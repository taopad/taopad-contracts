// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title ERC20 rewards
/// @author @niera26
/// @notice buy and sell tax on this token with rewardToken as rewards
/// @notice source: https://github.com/niera26/erc20-rewards-contracts
contract ERC20Rewards is Ownable, ERC20, ERC20Burnable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    // =========================================================================
    // dependencies.
    // =========================================================================

    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20Metadata public constant rewardToken = IERC20Metadata(0x77E06c9eCCf2E797fd462A92B6D7642EF85b0A44); // wTAO

    // =========================================================================
    // rewards management.
    // =========================================================================

    // numerator multiplier so tokenPerShare does not get rounded to 0.
    uint256 private constant PRECISION = 1e18;

    // scale factor so reward token scales to 18 decimals.
    uint256 private immutable SCALE_FACTOR;

    // the accumulated amount of reward token per share.
    uint256 private tokenPerShare;

    // total shares of this token.
    // (different from total supply because of fees and excluded wallets).
    uint256 public totalShares;

    // shareholders record.
    // (non excluded addresses are updated after they send/receive tokens).
    mapping(address => Share) private shareholders;

    struct Share {
        uint256 amount; // recorded balance after last transfer.
        uint256 earned; // amount of tokens earned but not claimed yet.
        uint256 tokenPerShareLast; // token per share value of the last earn occurrence.
    }

    // total amount of reward tokens ever claimed by holders.
    uint256 public totalRewardClaimed;

    // total amount of reward tokens ever distributed.
    uint256 public totalRewardDistributed;

    // amm pair addresses the tranfers from/to are taxed.
    // (populated with WETH/this token pair address in the constructor).
    mapping(address => bool) public pairs;

    // contract addresses that opted in for rewards.
    mapping(address => bool) public isOptin;

    // =========================================================================
    // reward donations.
    // =========================================================================

    // the number of reward tokens to emit per block.
    uint256 public rewardTokenPerBlock;

    // the amout of reward tokens already emitted.
    uint256 public emittedRewardsAcc;

    // last block reward tokens has been emitted.
    uint256 public lastEmittingBlock;

    // =========================================================================
    // operator address.
    // =========================================================================

    // the operator address receive marketing tax and can set pool fee.
    // only operator can update operator address. Allows to renounce ownership
    // while keep managing marketing wallet and update V3 poolFee.
    // deployer/owner address by default.
    address public operator;

    // =========================================================================
    // anti-bot and limitations.
    // =========================================================================

    mapping(address => bool) public isBlacklisted;

    uint256 public maxWallet = type(uint256).max; // set to 1% in initialize
    uint256 public startBlock = 0;
    uint8 public deadBlocks = 2;

    // =========================================================================
    // pool options.
    // =========================================================================

    uint24 public poolFee = 10000; // works for wTAO

    // =========================================================================
    // fees.
    // =========================================================================

    uint24 public constant maxSwapFee = 3000;
    uint24 public constant maxMarketingFee = 8000;
    uint24 public constant feeDenominator = 10000;

    uint24 public buyFee = 2400;
    uint24 public sellFee = 2400;
    uint24 public marketingFee = 8000;

    // =========================================================================
    // events.
    // =========================================================================

    event OptIn(address addr);
    event OptOut(address addr);
    event AddToBlacklist(address addr);
    event RemoveFromBlacklist(address addr);
    event Claim(address indexed addr, address indexed to, uint256 amount);
    event Distribute(address indexed addr, uint256 amount);
    event Sweep(address indexed addr, address indexed token, uint256 amount);

    // =========================================================================
    // constructor.
    // =========================================================================

    constructor(string memory name, string memory symbol, uint256 _totalSupply)
        Ownable(msg.sender)
        ERC20(name, symbol)
    {
        // operator is deployer by default.
        operator = msg.sender;

        // set the reward token scale factor.
        uint8 rewardTokenDecimals = rewardToken.decimals();

        require(rewardTokenDecimals <= 18, "reward token decimals must be <= 18");

        SCALE_FACTOR = 10 ** (18 - rewardTokenDecimals);

        // mint total supply to itself.
        _mint(address(this), _totalSupply * 10 ** decimals());
    }

    // =========================================================================
    // exposed contract values.
    // =========================================================================

    /**
     * Return the remaining rewards === reward balance - emitted rewards.
     */
    function remainingRewards() public view returns (uint256) {
        return rewardBalance() - emittedRewards();
    }

    /**
     * Return the reward balance === balance - what's remaining to claim.
     *
     * It is the amount that can be emitted in total.
     */
    function rewardBalance() public view returns (uint256) {
        uint256 toBeClaimed = totalRewardDistributed - totalRewardClaimed;

        return rewardToken.balanceOf(address(this)) - toBeClaimed;
    }

    /**
     * Return the amount of emitted reward since the last block rewards has
     * been emitted, according to the reward token per block.
     */
    function emittedRewards() public view returns (uint256) {
        if (lastEmittingBlock == 0) return 0;
        if (rewardTokenPerBlock == 0) return 0;

        uint256 balance = rewardBalance();

        if (balance == 0) return 0;

        uint256 emitted = emittedRewardsAcc + (rewardTokenPerBlock * (block.number - lastEmittingBlock));

        return emitted < balance ? emitted : balance;
    }

    /**
     * Return the amount of reward tokens the given address can claim.
     */
    function pendingRewards(address addr) external view returns (uint256) {
        return _pendingRewards(shareholders[addr]);
    }

    // =========================================================================
    // exposed user functions.
    // =========================================================================

    /**
     * Claim reward tokens and send them to given address.
     */
    function claim(address to) external nonReentrant {
        Share storage share = shareholders[msg.sender];

        _earn(share);

        uint256 amountToClaim = share.earned;

        if (amountToClaim == 0) return;

        share.earned = 0;

        totalRewardClaimed += amountToClaim;

        rewardToken.safeTransfer(to, amountToClaim);

        emit Claim(msg.sender, to, amountToClaim);
    }

    /**
     * Create a pair between this token and the given token.
     */
    function createAmmPairWith(address token) public {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.createPair(token, address(this));

        pairs[pair] = true;
    }

    /**
     * Register an existing pair between this token and the given token.
     */
    function recordAmmPairWith(address token) public {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.getPair(token, address(this));

        pairs[pair] = true;
    }

    /**
     * Optin for rewards when you are excluded from rewards (contracts).
     */
    function rewardOptin() external {
        _includeToRewards(msg.sender);

        isOptin[msg.sender] = true;

        emit OptIn(msg.sender);
    }

    /**
     * Optout for rewards when you are included to rewards (contracts).
     */
    function rewardOptout() external {
        _removeFromRewards(msg.sender);

        isOptin[msg.sender] = false;

        emit OptOut(msg.sender);
    }

    /**
     * Swap the collected tax to ETH.
     *
     * Pass minimal expected amount to prevent slippage/frontrun.
     */
    function swapCollectedTax(uint256 amountOutMin) public {
        // return if no tax collected.
        uint256 amountIn = balanceOf(address(this));

        if (amountIn == 0) return;

        // swap tax to eth.
        uint256 collectedEth = _swapTokenToETHV2(address(this), amountIn, amountOutMin);

        // collect marketing tax.
        uint256 marketingAmount = (collectedEth * marketingFee) / feeDenominator;

        if (marketingAmount > 0) {
            payable(operator).transfer(marketingAmount);
        }
    }

    /**
     * Distribute reward token.
     *
     * Pass minimal expected amount to prevent slippage/frontrun.
     */
    function distribute(uint256 amountOutMinimum) public nonReentrant {
        if (totalShares == 0) return;

        // distribute the rewards that was emitted since last update.
        uint256 amountToDistribute = emittedRewards();

        // swap eth balance to reward token and add it to amount to distribute.
        uint256 amountIn = address(this).balance;

        if (amountIn > 0) {
            amountToDistribute += _swapETHToRewardV3(address(this), amountIn, amountOutMinimum);
        }

        // stop when no rewards.
        if (amountToDistribute == 0) return;

        // distribute rewards.
        tokenPerShare += (amountToDistribute * SCALE_FACTOR * PRECISION) / totalShares;
        totalRewardDistributed += amountToDistribute;

        // reset emitted rewards.
        emittedRewardsAcc = 0;
        lastEmittingBlock = block.number;

        emit Distribute(msg.sender, amountToDistribute);
    }

    /**
     * Sweep any other ERC20 mistakenly sent to this contract.
     */
    function sweep(IERC20 otherToken) external {
        require(address(otherToken) != address(this), "!sweep");
        require(address(otherToken) != address(rewardToken), "!sweep");

        uint256 amount = otherToken.balanceOf(address(this));

        otherToken.safeTransfer(msg.sender, amount);

        emit Sweep(msg.sender, address(otherToken), amount);
    }

    // =========================================================================
    // exposed admin functions.
    // =========================================================================

    /**
     * Send initial allocations before trading started.
     */
    function allocate(address to, uint256 amount) external onlyOwner {
        require(startBlock == 0, "!initialized");

        this.transfer(to, amount);
    }

    /**
     * Remove max wallet limits, one shoot.
     */
    function removeLimits() external onlyOwner {
        maxWallet = type(uint256).max;
    }

    /**
     * Set the fees.
     */
    function setFee(uint24 _buyFee, uint24 _sellFee, uint24 _marketingFee) external onlyOwner {
        require(_buyFee <= maxSwapFee, "!buyFee");
        require(_sellFee <= maxSwapFee, "!sellFee");
        require(_marketingFee <= maxMarketingFee, "!marketingFee");

        buyFee = _buyFee;
        sellFee = _sellFee;
        marketingFee = _marketingFee;
    }

    /**
     * Remove the given address from the blacklist.
     */
    function removeFromBlacklist(address addr) external onlyOwner {
        _removeFromBlacklist(addr);
    }

    /**
     * Initialize the trading with the given eth and this contract balance.
     *
     * Starts trading, sets max wallet to 1% of the supply, create the uniswap V2 pair
     * with ETH, adds liquidity.
     *
     * LP tokens are sent to owner.
     */
    function initialize() external payable onlyOwner {
        require(msg.value > 0, "!liquidity");
        require(startBlock == 0, "!initialized");

        // start deadblocks from there.
        startBlock = block.number;

        // init max wallet to 1%.
        maxWallet = totalSupply() / 100;

        // the all balance will be put in the LP.
        uint256 balance = balanceOf(address(this));

        // create an amm pair with WETH.
        // as a contract, pair is automatically excluded from rewards.
        createAmmPairWith(router.WETH());

        // approve router to use total balance.
        _approve(address(this), address(router), balance);

        // add liquidity and send LP to owner.
        router.addLiquidityETH{value: msg.value}(address(this), balance, 0, 0, msg.sender, block.timestamp);
    }

    // =========================================================================
    // exposed operator functions.
    // =========================================================================

    /**
     * Operator can update itself.
     */
    function setOperator(address _operator) external {
        require(msg.sender == operator, "!operator");
        operator = _operator;
    }

    /**
     * Set the uniswapV3 pool fee.
     */
    function setPoolFee(uint24 _poolFee) external {
        require(msg.sender == operator, "!operator");
        poolFee = _poolFee;
    }

    /**
     * Set the reward token per block. Accumulates the emitted rewards until
     * now before updateing the value.
     */
    function setRewardTokenPerBlock(uint256 _rewardTokenPerBlock) external {
        require(msg.sender == operator, "!operator");
        emittedRewardsAcc = emittedRewards();
        rewardTokenPerBlock = _rewardTokenPerBlock;
        lastEmittingBlock = block.number;
    }

    /**
     * Set the reward token per block without accumulating what has been
     * emitted. Fallback is case of an error.
     */
    function setRewardTokenPerBlockUnsafe(uint256 _rewardTokenPerBlock) external {
        require(msg.sender == operator, "!operator");
        rewardTokenPerBlock = _rewardTokenPerBlock;
    }

    /**
     * Empty the emitted rewards. Fallback in case of error.
     */
    function resetEmittedRewardsUnsafe() external {
        require(msg.sender == operator, "!operator");
        emittedRewardsAcc = 0;
    }

    // =========================================================================
    // internal functions.
    // =========================================================================

    /**
     * Return whether current block is a dead block (= blacklisted when buying in a dead block).
     */
    function _isDeadBlock() private view returns (bool) {
        return block.number <= startBlock + deadBlocks;
    }

    /**
     * Return addresses excluded from max wallet limit (= this contract, router or pairs).
     *
     * Blacklisted addresses are excluded too so they can buy as much as they want.
     */
    function _isExcludedFromMaxWallet(address addr) private view returns (bool) {
        return address(this) == addr || address(router) == addr || pairs[addr] || isBlacklisted[addr];
    }

    /**
     * Return adresses excluded from taxes (= this contract or router).
     */
    function _isExcludedFromTaxes(address addr) private view returns (bool) {
        return address(this) == addr || address(router) == addr;
    }

    /**
     * Retrun addresses excluded from rewards.
     *
     * - addresses of contracts that didn't opted in for rewards.
     * - blacklisted addresses.
     * - zero address to save gas on mint/burn (its balance is always 0 so it would never get shares anyway)
     * - this contract address is removed too because address(this).code.length == 0 in the constructor.
     * - remove dead address because people are used to it.
     */
    function _isExcludedFromRewards(address addr) private view returns (bool) {
        return address(0) == addr || address(this) == addr || (addr.code.length > 0 && !isOptin[addr])
            || isBlacklisted[addr] || 0x000000000000000000000000000000000000dEaD == addr;
    }

    /**
     * Add the given address to blacklist.
     */
    function _addToBlacklist(address addr) private {
        _removeFromRewards(addr);

        isBlacklisted[addr] = true;

        emit AddToBlacklist(addr);
    }

    /**
     * Remove the given address from blacklist.
     */
    function _removeFromBlacklist(address addr) private {
        _includeToRewards(addr);

        isBlacklisted[addr] = false;

        emit RemoveFromBlacklist(addr);
    }

    /**
     * Include the given address to rewards. Should only concern:
     *
     * - addresses of contracts opting in for rewards.
     * - addresses being removed from blacklist.
     */
    function _includeToRewards(address addr) private {
        // ensure we dont update total shares twice.
        if (!_isExcludedFromRewards(addr)) return;

        // update total shares.
        uint256 balance = balanceOf(addr);

        totalShares += balance;

        // restart earning from now.
        Share storage share = shareholders[addr];

        share.amount = balance;
        share.tokenPerShareLast = tokenPerShare;
    }

    /**
     * Remove the given address from rewards. Should only concern:
     *
     * - addresses of contracts opting out of rewards.
     * - addresses being added to blacklist.
     */
    function _removeFromRewards(address addr) private {
        // ensure we dont update total shares twice.
        if (_isExcludedFromRewards(addr)) return;

        // update total shares.
        totalShares -= balanceOf(addr);

        // make sure pending rewards are earned and stop earning (share.amount = 0)
        Share storage share = shareholders[addr];

        _earn(share);

        share.amount = 0;
    }

    /**
     * Compute the pending rewards of the given share.
     *
     * The rewards earned since the last transfer are added to the already earned
     * rewards.
     */
    function _pendingRewards(Share memory share) private view returns (uint256) {
        uint256 RDiff = tokenPerShare - share.tokenPerShareLast;
        uint256 earned = (share.amount * RDiff) / (SCALE_FACTOR * PRECISION);

        return share.earned + earned;
    }

    /**
     * Earn the rewards of the given share.
     */
    function _earn(Share storage share) private {
        uint256 pending = _pendingRewards(share);

        share.earned = pending;
        share.tokenPerShareLast = tokenPerShare;
    }

    /**
     * Override the update method in order to take fee when transfer is from/to
     * a registered amm pair.
     *
     * - transfers from/to registered pairs are taxed.
     * - addresses buying in a deadblock are blacklisted and cant transfer tokens anymore.
     * - prevents receiving address to get more than max wallet.
     * - taxed tokens are sent to this very contract.
     * - on a taxed sell, the collected tax is swapped for eth.
     * - updates the shares of both the from and to addresses.
     */
    function _update(address from, address to, uint256 amount) internal override {
        // blacklisted addresses cant transfer tokens.
        require(!isBlacklisted[from], "blacklisted");

        // check if it is a taxed buy or sell.
        bool isTaxedBuy = pairs[from] && !_isExcludedFromTaxes(to);
        bool isTaxedSell = !_isExcludedFromTaxes(from) && pairs[to];

        // take the fee if it is a buy or sell.
        uint256 fee = (isTaxedBuy ? buyFee : 0) + (isTaxedSell ? sellFee : 0);

        uint256 taxAmount = (amount * fee) / feeDenominator;

        uint256 actualTransferAmount = amount - taxAmount;

        // add to blacklist while buying in dead block.
        if (isTaxedBuy && _isDeadBlock()) {
            _addToBlacklist(to);
        }

        // prevents max wallet for regular addresses.
        if (!_isExcludedFromMaxWallet(to)) {
            require(actualTransferAmount + balanceOf(to) <= maxWallet, "!maxWallet");
        }

        // transfer the tax to this contract if any.
        if (taxAmount > 0) {
            super._update(from, address(this), taxAmount);
        }

        // swaps the tax to eth if it is a taxed sell.
        if (isTaxedSell) {
            swapCollectedTax(0);
        }

        // transfer the actual amount.
        super._update(from, to, actualTransferAmount);

        // updates shareholders values.
        _updateShare(from);
        _updateShare(to);
    }

    /**
     * Update the total shares and the shares of the given address if it is not
     * excluded from rewards.
     *
     * Earn first with his current share amount then update shares according to
     * its new balance.
     */
    function _updateShare(address addr) private {
        if (_isExcludedFromRewards(addr)) return;

        uint256 balance = balanceOf(addr);

        Share storage share = shareholders[addr];

        totalShares = totalShares - share.amount + balance;

        _earn(share);

        share.amount = balance;
    }

    /**
     * Swap amount of this token for ETH to address and return the amount received.
     */
    function _swapTokenToETHV2(address to, uint256 amountIn, uint256 amountOutMin) private returns (uint256) {
        // return 0 if no amount given.
        if (amountIn == 0) return 0;

        // approve router to spend tokens.
        _approve(address(this), address(router), amountIn);

        // swap the whole amount to eth.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        uint256 originalETHbalance = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, amountOutMin, path, to, block.timestamp);

        return address(this).balance - originalETHbalance;
    }

    /**
     * Swap amount of ETH for reward tokens to address and return the amount received.
     */
    function _swapETHToRewardV3(address to, uint256 amountIn, uint256 amountOutMinimum) private returns (uint256) {
        // return 0 if no amount given.
        if (amountIn == 0) return 0;

        // build the swap parameter.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: router.WETH(),
            tokenOut: address(rewardToken),
            fee: poolFee,
            recipient: to,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // execute the swap and return the number of received tokens.
        return swapRouter.exactInputSingle{value: amountIn}(params);
    }

    receive() external payable {}
}
