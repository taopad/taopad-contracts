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
    uint256 private TokenPerShare;

    // total shares of this token.
    // (different from total supply because of fees and excluded wallets).
    uint256 public totalShares;

    // shareholders record.
    // (non excluded addresses are updated after they send/receive tokens).
    mapping(address => Share) private shareholders;

    struct Share {
        uint256 amount; // recorded balance after last transfer.
        uint256 earned; // amount of tokens earned but not claimed yet.
        uint256 TokenPerShareLast; // token per share value of the last earn occurrence.
        uint256 lastUpdateBlock; // last block the share was updated.
    }

    // total amount of reward tokens ever claimed by holders.
    uint256 public totalTokenClaimed;

    // total amount of reward tokens ever distributed.
    uint256 public totalTokenDistributed;

    // =========================================================================
    // fees.
    // =========================================================================

    // bps denominator.
    uint256 public constant feeDenominator = 10000;

    // buy taxes bps.
    uint256 public buyRewardFee = 500;
    uint256 public buyMarketingFee = 1900;
    uint256 public buyTotalFee = buyRewardFee + buyMarketingFee;
    uint256 public maxBuyFee = 3000;

    // sell taxes bps.
    uint256 public sellRewardFee = 500;
    uint256 public sellMarketingFee = 1900;
    uint256 public sellTotalFee = sellRewardFee + sellMarketingFee;
    uint256 public maxSellFee = 3000;

    // amm pair addresses the tranfers from/to are taxed.
    // (populated with WETH/this token pair address in the constructor).
    mapping(address => bool) public pairs;

    // contract addresses that opted in for rewards.
    mapping(address => bool) public isOptin;

    // =========================================================================
    // Anti-bot and limitations
    // =========================================================================

    uint256 public maxWallet = type(uint256).max; // set to 1% in ininitialize
    uint256 public startBlock = 0;
    uint256 public deadBlocks = 2;

    mapping(address => bool) public isBlacklisted;

    // =========================================================================
    // marketing.
    // =========================================================================

    // address where marketing tax is sent.
    address public marketingWallet;

    // amount of this token collected as marketing tax.
    uint256 private marketingAmount;

    // =========================================================================
    // pool options.
    // =========================================================================

    uint24 public poolFee = 10000; // works for wTAO

    // =========================================================================
    // Events.
    // =========================================================================

    event OptIn(address addr);
    event OptOut(address addr);
    event AddToBlacklist(address addr);
    event RemoveFromBlacklist(address addr);
    event Claim(address indexed to, uint256 amount);
    event Distribute(address indexed from, uint256 amount);

    // =========================================================================
    // constructor.
    // =========================================================================

    constructor(string memory name, string memory symbol) Ownable(msg.sender) ERC20(name, symbol) {
        // marketing wallet is deployer by default.
        marketingWallet = msg.sender;

        // set the reward token scale factor.
        uint8 rewardTokenDecimals = rewardToken.decimals();

        require(rewardTokenDecimals <= 18, "reward token decimals must be <= 18");

        SCALE_FACTOR = 10 ** (18 - rewardTokenDecimals);
    }

    // =========================================================================
    // init contract.
    // =========================================================================

    /**
     * Initialize the contract by creating the liquidy pool.
     *
     * It adds the total supply of the token with the sent ETH.
     *
     * LP tokens are sent to owner.
     */
    function initialize(uint256 _rawTotalSupply) external payable onlyOwner {
        address[] memory addrs = new address[](0);
        uint256[] memory allocs = new uint256[](0);

        _initialize(_rawTotalSupply, addrs, allocs);
    }

    function initialize(uint256 _rawTotalSupply, address[] memory addrs, uint256[] memory allocs)
        external
        payable
        onlyOwner
    {
        _initialize(_rawTotalSupply, addrs, allocs);
    }

    function _initialize(uint256 _rawTotalSupply, address[] memory addrs, uint256[] memory allocs) private {
        require(msg.value > 0, "!liquidity");
        require(startBlock == 0, "!initialized");
        require(addrs.length == allocs.length, "!allocations");

        // get the token decimal const.
        uint256 decimalConst = 10 ** decimals();

        // mint total supply to this contract.
        uint256 _totalSupply = _rawTotalSupply * decimalConst;

        _mint(address(this), _totalSupply);

        // distribute allocations.
        uint8 nbAllocs = uint8(addrs.length);

        for (uint8 i = 0; i < nbAllocs; i++) {
            _transfer(address(this), addrs[i], allocs[i] * decimalConst);
        }

        // the remaining balance will be put in the LP.
        uint256 balance = balanceOf(address(this));

        // create an amm pair with WETH.
        // as a contract, pair is automatically excluded from rewards.
        createAmmPairWith(router.WETH());

        // approve router to use total balance.
        _approve(address(this), address(router), balance);

        // add liquidity and send LP to owner.
        router.addLiquidityETH{value: msg.value}(address(this), balance, 0, 0, msg.sender, block.timestamp);

        // start deadblocks from there.
        startBlock = block.number;

        // init max wallet to 1%.
        maxWallet = _totalSupply / 100;
    }

    // =========================================================================
    // exposed user functions.
    // =========================================================================

    /**
     * Return the amount of reward token ready to be distributed.
     *
     * == balance of reward token minus what's not claimed yet.
     *
     * Allows to expose reward token donations to this contract.
     *
     * When a distribution occurs, the tax is swapped to reward token
     * and this value grows.
     */
    function rewardBalance() public view returns (uint256) {
        uint256 amountToClaim = totalTokenDistributed - totalTokenClaimed;

        return rewardToken.balanceOf(address(this)) - amountToClaim;
    }

    /**
     * Return the amount of reward tokens the given address can claim.
     */
    function pendingRewards(address addr) external view returns (uint256) {
        return _pendingRewards(shareholders[addr]);
    }

    /**
     * Claim reward tokens.
     */
    function claim() external nonReentrant {
        Share storage share = shareholders[msg.sender];

        _earn(share);

        uint256 amountToClaim = share.earned;

        if (amountToClaim == 0) return;

        share.earned = 0;

        totalTokenClaimed += amountToClaim;

        rewardToken.safeTransfer(msg.sender, amountToClaim);

        emit Claim(msg.sender, amountToClaim);
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
     * Distribute taxes as reward token.
     */
    function distribute() external nonReentrant {
        require(block.number > shareholders[msg.sender].lastUpdateBlock, "update and distribute in the same block");

        if (totalShares == 0) return;

        // get the collected tax.
        uint256 totalTaxAmount = balanceOf(address(this));

        // swap all tax for rewards if any.
        if (totalTaxAmount > 0) {
            // swap all tax to ETH and send it to this contract.
            _swapTokenToETHV2(address(this), totalTaxAmount, 0);

            // swap all this contract ETH to rewards and send it to this contract.
            uint256 swappedRewards = _swapETHToRewardV3(address(this), address(this).balance, 0);

            // collect marketing tax when something has been swapped.
            if (swappedRewards > 0) {
                // marketing amount is always <= total tax amount.
                uint256 marketing = (swappedRewards * marketingAmount) / totalTaxAmount;

                rewardToken.safeTransfer(marketingWallet, marketing);

                marketingAmount = 0; // reset collected marketing.
            }
        }

        // distribute the available rewards (swapped tax + reward token donations).
        uint256 amountToDistribute = rewardBalance();

        if (amountToDistribute == 0) return;

        TokenPerShare += (amountToDistribute * SCALE_FACTOR * PRECISION) / totalShares;
        totalTokenDistributed += amountToDistribute;

        emit Distribute(msg.sender, amountToDistribute);
    }

    /**
     * Sweep any other ERC20 mistakenly sent to this contract.
     */
    function sweep(IERC20 token) external {
        require(address(token) != address(this), "!sweep");
        require(address(token) != address(rewardToken), "!sweep");

        uint256 amount = token.balanceOf(address(this));

        token.safeTransfer(msg.sender, amount);
    }

    // =========================================================================
    // exposed admin functions.
    // =========================================================================

    function removeLimits() external onlyOwner {
        maxWallet = type(uint256).max;
    }

    function setBuyFee(uint256 rewardFee, uint256 marketingFee) external onlyOwner {
        require(rewardFee + marketingFee <= maxBuyFee, "!maxBuyFee");

        buyRewardFee = rewardFee;
        buyMarketingFee = marketingFee;
        buyTotalFee = rewardFee + marketingFee;
    }

    function setSellFee(uint256 rewardFee, uint256 marketingFee) external onlyOwner {
        require(rewardFee + marketingFee <= maxSellFee, "!maxSellFee");

        sellRewardFee = rewardFee;
        sellMarketingFee = marketingFee;
        sellTotalFee = rewardFee + marketingFee;
    }

    function setPoolFee(uint24 _poolFee) external onlyOwner {
        poolFee = _poolFee;
    }

    function setMarketingWallet(address _marketingWallet) external onlyOwner {
        marketingWallet = _marketingWallet;
    }

    function addToBlacklist(address addr) external onlyOwner {
        _addToBlacklist(addr);
    }

    function removeFromBlacklist(address addr) external onlyOwner {
        _removeFromBlacklist(addr);
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
     * Return addresses excluded from max wallet limit (= this contract, routers or pairs).
     *
     * Blacklisted addresses are excluded too so they can buy as much as they want.
     */
    function _isExcludedFromMaxWallet(address addr) private view returns (bool) {
        return addr == address(this) || addr == address(router) || addr == address(swapRouter) || pairs[addr]
            || isBlacklisted[addr];
    }

    /**
     * Return adresses excluded from taxes (= this contract or routers).
     */
    function _isExcludedFromTaxes(address addr) private view returns (bool) {
        return address(this) == addr || address(router) == addr || address(swapRouter) == addr;
    }

    /**
     * Retrun addresses excluded from rewards.
     *
     * - addresses of contracts that didn't opted in for rewards.
     * - blacklisted addresses.
     */
    function _isExcludedFromRewards(address addr) private view returns (bool) {
        return (addr.code.length > 0 && !isOptin[addr]) || isBlacklisted[addr];
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
        share.TokenPerShareLast = TokenPerShare;
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
        uint256 RDiff = TokenPerShare - share.TokenPerShareLast;
        uint256 earned = (share.amount * RDiff) / (SCALE_FACTOR * PRECISION);

        return share.earned + earned;
    }

    /**
     * Earn the rewards of the given share.
     */
    function _earn(Share storage share) private {
        uint256 pending = _pendingRewards(share);

        share.earned = pending;
        share.TokenPerShareLast = TokenPerShare;
    }

    /**
     * Override the update method in order to take fee when transfer is from/to
     * a registered amm pair.
     *
     * - transfers from/to this contract are not taxed.
     * - transfers from/to uniswap router are not taxed.
     * - addresses buying in a deadblock are blacklisted and cant transfer tokens anymore.
     * - prevent receiving address to get more than max wallet.
     * - marketing fees are accounted here.
     * - taxed tokens are sent to this very contract.
     * - updates the shares of both the from and to addresses.
     */
    function _update(address from, address to, uint256 amount) internal override {
        // blacklisted addresses cant transfer tokens.
        require(!isBlacklisted[from], "blacklisted");

        // check if it is a taxed buy or sell.
        bool isTaxedBuy = pairs[from] && !_isExcludedFromTaxes(to);
        bool isTaxedSell = !_isExcludedFromTaxes(from) && pairs[to];

        // compute the reward fees and the marketing fees.
        uint256 rewardFee = (isTaxedBuy ? buyRewardFee : 0) + (isTaxedSell ? sellRewardFee : 0);
        uint256 marketingFee = (isTaxedBuy ? buyMarketingFee : 0) + (isTaxedSell ? sellMarketingFee : 0);

        // compute the fee amount.
        uint256 transferRewardFeeAmount = (amount * rewardFee) / feeDenominator;
        uint256 transferMarketingFeeAmount = (amount * marketingFee) / feeDenominator;
        uint256 transferTotalFeeAmount = transferRewardFeeAmount + transferMarketingFeeAmount;

        // compute the actual amount sent to receiver.
        uint256 transferActualAmount = amount - transferTotalFeeAmount;

        // add to blacklist while buying in dead block.
        if (isTaxedBuy && _isDeadBlock()) {
            _addToBlacklist(to);
        }

        // prevents max wallet for regular addresses.
        if (!_isExcludedFromMaxWallet(to)) {
            require(transferActualAmount + balanceOf(to) <= maxWallet, "!maxWallet");
        }

        // transfer the actual amount.
        super._update(from, to, transferActualAmount);

        // accout for the marketing fee if any.
        if (transferMarketingFeeAmount > 0) {
            marketingAmount += transferMarketingFeeAmount;
        }

        // transfer the total fee amount to this contract if any.
        if (transferTotalFeeAmount > 0) {
            super._update(from, address(this), transferTotalFeeAmount);
        }

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
        share.lastUpdateBlock = block.number;
    }

    /**
     * Swap amount of tokens for ETH to address and return the amount received.
     */
    function _swapTokenToETHV2(address to, uint256 amountIn, uint256 amountOutMin) private returns (uint256) {
        // return 0 if no amount given.
        if (amountIn == 0) return 0;

        // approve router to spend tokens.
        _approve(address(this), address(router), amountIn);

        // keep the original ETH balance to compute the swapped amount.
        uint256 originalBalance = to.balance;

        // swap the whole amount to eth.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, amountOutMin, path, to, block.timestamp);

        // return the received amount.
        return to.balance - originalBalance;
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

    /**
     * This contract cant receive ETH except from routers and pairs.
     */
    receive() external payable {
        require(
            msg.sender == address(router) || msg.sender == address(swapRouter) || pairs[msg.sender],
            "cannot send eth to this contract"
        );
    }
}
