// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract ERC20Rewards is ERC20, Ownable, ReentrancyGuard {
    // =========================================================================
    // dependencies.
    // =========================================================================

    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // =========================================================================
    // rewards management.
    // =========================================================================

    // numerator multiplier so ETHR does not get rounded to 0.
    uint256 private constant precision = 1e18;

    // the amount of ETH per share.
    uint256 private ETHR;

    // total shares of this token.
    // (different from total supply because of fees and excluded wallets).
    uint256 public totalShares;

    // total amount of ETH ever distributed.
    uint256 public totalETHRewards;

    // shareholders record.
    // (non excluded addresses are updated after they send/receive tokens).
    mapping(address => Share) private shareholders;

    struct Share {
        uint256 amount; // recorded balance after last transfer.
        uint256 earned; // amount of ETH earned but not claimed yet.
        uint256 ETHRLast; // ETHR value of the last time ETH was earned.
        uint256 lastBlockUpdate; // last block share was updated.
    }

    // =========================================================================
    // fees.
    // =========================================================================

    // bps denominator.
    uint256 public constant feeDenominator = 10000;

    // buy taxes bps.
    uint256 public buyRewardFee = 0;
    uint256 public buyMarketingFee = 2000;
    uint256 public buyTotalFee = buyRewardFee + buyMarketingFee;
    uint256 public maxBuyFee = 3000;

    // sell taxes bps.
    uint256 public sellRewardFee = 0;
    uint256 public sellMarketingFee = 3000;
    uint256 public sellTotalFee = sellRewardFee + sellMarketingFee;
    uint256 public maxSellFee = 3000;

    // amm pair addresses the tranfers from/to are taxed.
    // (populated with WETH/this token pair address in the constructor).
    mapping(address => bool) public pairs;

    // addresses not receiving rewards.
    // (populated with this token address in the constructor).
    mapping(address => bool) public isExcludedFromRewards;

    // =========================================================================
    // claims.
    // =========================================================================

    // amount of ETH ever claimed by holders.
    uint256 public totalClaimedETH;

    // ERC20 token address to its amount ever claimed by holders.
    mapping(address => uint256) public totalClaimedERC20;

    // =========================================================================
    // Anti-bot and limitations
    // =========================================================================

    uint256 public maxWallet;
    uint256 public startBlock = 0;
    uint256 public deadBlocks = 2;

    mapping(address => bool) public isBlacklisted;

    // =========================================================================
    // marketing.
    // =========================================================================

    // address where collected marketing fees are sent.
    address public marketingWallet;

    // amount of this token collected as marketing fee.
    uint256 private marketingAmount;

    // =========================================================================
    // Events.
    // =========================================================================

    event ClaimETH(address indexed to, uint256 amount);
    event ClaimERC20(address indexed to, address indexed token, uint256 amount);
    event Distribute(address indexed from, uint256 amountTokens, uint256 amountETH);

    // =========================================================================
    // constructor.
    // =========================================================================

    constructor(string memory name, string memory symbol, uint256 rawTotalSupply) ERC20(name, symbol) {
        // get total supply.
        uint256 _totalSupply = rawTotalSupply * 10 ** decimals();

        // init max wallet to 1%.
        maxWallet = _totalSupply / 100;

        // create an amm pair with WETH.
        // pair gets automatically excluded from rewards.
        createAmmPairWith(router.WETH());

        // exclude this contract and router from rewards.
        _excludeFromRewards(address(this));
        _excludeFromRewards(address(router));

        // mint total supply to this contract.
        _mint(address(this), _totalSupply);

        // set deployer as marketing wallet.
        marketingWallet = msg.sender;
    }

    // =========================================================================
    // init contract.
    // =========================================================================

    /**
     * Init the contract by adding initial liquidity.
     *
     * It adds the total supply of the token (= this contract balance) with the sent ETH.
     *
     * Send LP tokens to owner.
     */
    function init() external payable onlyOwner {
        require(startBlock == 0, "already initialized");

        startBlock = block.number;

        uint256 amountETH = msg.value;
        uint256 amountToken = balanceOf(address(this));

        _approve(address(this), address(router), amountToken);

        router.addLiquidityETH{value: amountETH}(address(this), amountToken, 0, 0, msg.sender, block.timestamp);
    }

    // =========================================================================
    // exposed view functions.
    // =========================================================================

    function currentRewards() public view returns (uint256) {
        uint256 balance = balanceOf(address(this));

        if (balance > marketingAmount) {
            return balance - marketingAmount;
        }

        return 0;
    }

    function currentRewards(address holder) public view returns (uint256) {
        uint256 currentTotalShares = totalShares;

        if (currentTotalShares > 0) {
            return (currentRewards() * shareholders[holder].amount) / currentTotalShares;
        }

        return 0;
    }

    function pendingRewards(address holder) external view returns (uint256) {
        return _pendingRewards(shareholders[holder]);
    }

    // =========================================================================
    // exposed user functions.
    // =========================================================================

    function claim() external nonReentrant {
        uint256 claimedETH = _claim(msg.sender);

        if (claimedETH == 0) return;

        payable(msg.sender).transfer(claimedETH);

        totalClaimedETH += claimedETH;

        emit ClaimETH(msg.sender, claimedETH);
    }

    function claim(address token, uint256 minAmountOut) external nonReentrant {
        uint256 claimedETH = _claim(msg.sender);

        if (claimedETH == 0) return;

        uint256 claimedERC20 = _swapETHToERC20(claimedETH, token, msg.sender, minAmountOut);

        totalClaimedERC20[token] += claimedERC20;

        emit ClaimERC20(msg.sender, token, claimedERC20);
    }

    function distribute() external {
        uint256 currentTotalShares = totalShares;
        uint256 rewardsToDistribute = currentRewards();

        require(rewardsToDistribute > 0, "no reward to distribute");
        require(currentTotalShares > 0, "no one to distribute");
        require(shareholders[msg.sender].lastBlockUpdate < block.number, "transfer and distribute not allowed");

        uint256 swappedETH = _swapback(rewardsToDistribute);

        ETHR += (swappedETH * precision) / currentTotalShares;

        totalETHRewards += swappedETH;

        emit Distribute(msg.sender, rewardsToDistribute, swappedETH);
    }

    function createAmmPairWith(address token) public {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.createPair(token, address(this));

        pairs[pair] = true;

        _excludeFromRewards(pair);
    }

    function recordAmmPairWith(address token) public {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.getPair(token, address(this));

        pairs[pair] = true;

        _excludeFromRewards(pair);
    }

    function sweep(address _token) external {
        require(address(this) != _token, "cant sweep this token");

        IERC20 token = IERC20(_token);

        uint256 amount = token.balanceOf(address(this));

        token.transfer(msg.sender, amount);
    }

    // =========================================================================
    // exposed admin functions.
    // =========================================================================

    function removeLimits() external onlyOwner {
        maxWallet = type(uint256).max;
    }

    function excludeFromRewards(address addr) external onlyOwner {
        _excludeFromRewards(addr);
    }

    function includeToRewards(address addr) external onlyOwner {
        _includeToRewards(addr);
    }

    function addToBlacklist(address addr) external onlyOwner {
        _addToBlacklist(addr);
    }

    function removeFromBlacklist(address addr) external onlyOwner {
        _removeFromBlacklist(addr);
    }

    function setBuyFee(uint256 rewardFee, uint256 marketingFee) external onlyOwner {
        require(rewardFee + marketingFee <= maxBuyFee, "30% total buy fee max");

        buyRewardFee = rewardFee;
        buyMarketingFee = marketingFee;
        buyTotalFee = rewardFee + marketingFee;
    }

    function setSellFee(uint256 rewardFee, uint256 marketingFee) external onlyOwner {
        require(rewardFee + marketingFee <= maxSellFee, "30% total sell fee max");

        sellRewardFee = rewardFee;
        sellMarketingFee = marketingFee;
        sellTotalFee = rewardFee + marketingFee;
    }

    function setMarketingWallet(address _marketingWallet) external onlyOwner {
        marketingWallet = _marketingWallet;
    }

    function currentMarketingAmount() external view onlyOwner returns (uint256) {
        return marketingAmount;
    }

    function withdrawMarketing() external {
        require(msg.sender == marketingWallet, "sender is not marketing wallet");

        _withdrawMarketing(marketingAmount);
    }

    function withdrawMarketing(uint256 amountToWithdraw) external {
        require(msg.sender == marketingWallet, "sender is not marketing wallet");
        require(amountToWithdraw <= marketingAmount, "amount must be <= currentMarketingAmount()");

        _withdrawMarketing(amountToWithdraw);
    }

    // =========================================================================
    // internal functions.
    // =========================================================================

    /**
     * Override the transfer method in order to take fee when transfer is from/to
     * a registered amm pair.
     *
     * - transfers from/to this contract are not taxed.
     * - transfers from/to uniswap router are not taxed.
     * - wallets buying in a deadblock are blacklisted and cant transfer tokens.
     * - prevent receiving address to get more than max wallet.
     * - marketing fees are collected here.
     * - taxes are sent to this very contract for later distribution.
     * - updates the shares of both the from and to addresses.
     */

    function _transfer(address from, address to, uint256 amount) internal override {
        // blacklisted addresses cant transfer tokens.
        require(!isBlacklisted[from], "blacklisted");

        // get the addresses excluded from taxes.
        bool isExcludedFromTaxes = _isExcludedFromTaxes(from) || _isExcludedFromTaxes(to);

        // check if it is a taxed buy or sell.
        bool isTaxedBuy = !isExcludedFromTaxes && pairs[from];
        bool isTaxedSell = !isExcludedFromTaxes && pairs[to];

        // compute the reward fees and the marketing fees.
        uint256 rewardFee = (isTaxedBuy ? buyRewardFee : 0) + (isTaxedSell ? sellRewardFee : 0);
        uint256 marketingFee = (isTaxedBuy ? buyMarketingFee : 0) + (isTaxedSell ? sellMarketingFee : 0);

        // compute the fee amount.
        uint256 transferRewardFeeAmount = (amount * rewardFee) / feeDenominator;
        uint256 transferMarketingFeeAmount = (amount * marketingFee) / feeDenominator;
        uint256 transferTotalFeeAmount = transferRewardFeeAmount + transferMarketingFeeAmount;

        // compute the actual amount sent to receiver.
        uint256 transferActualAmount = amount - transferTotalFeeAmount;

        // prevents max wallet on transfer to a non pair address.
        if (!isExcludedFromTaxes && !pairs[to]) {
            require(transferActualAmount + balanceOf(to) <= maxWallet, "max-wallet-reached");
        }

        // add to blacklist while buying in dead block.
        if (isTaxedBuy && _isDeadBlock()) {
            _addToBlacklist(to);
        }

        // transfer the actual amount.
        super._transfer(from, to, transferActualAmount);

        // accout fot the marketing fee if any.
        if (transferMarketingFeeAmount > 0) {
            marketingAmount += transferMarketingFeeAmount;
        }

        // transfer the total fee amount to this contract if any.
        if (transferTotalFeeAmount > 0) {
            super._transfer(from, address(this), transferTotalFeeAmount);
        }

        // updates shareholders values.
        _updateShare(from);
        _updateShare(to);
    }

    /**
     * Return whether current block is a dead block (= get blacklisted when buying
     * in a dead block).
     */
    function _isDeadBlock() private view returns (bool) {
        return block.number <= startBlock + deadBlocks;
    }

    /**
     * Return adresses excluded from taxes (= this contract address or router).
     */
    function _isExcludedFromTaxes(address addr) private view returns (bool) {
        return address(this) == addr || address(router) == addr;
    }

    /**
     * Exclude the given address from rewards.
     *
     * Earn its rewards then remove it from total shares.
     */
    function _excludeFromRewards(address addr) private {
        isExcludedFromRewards[addr] = true;

        Share storage share = shareholders[addr];

        _earn(share);

        totalShares -= share.amount;

        share.amount = 0;
    }

    /**
     * Include the given address to rewards.
     *
     * It must be excluded first.
     *
     * Add its balance to totalShares and record current ETHR.
     */
    function _includeToRewards(address addr) private {
        require(isExcludedFromRewards[addr], "the given address must be excluded");

        isExcludedFromRewards[addr] = false;

        Share storage share = shareholders[addr];

        uint256 balance = balanceOf(addr);

        totalShares += balance;

        share.amount = balance;
        share.ETHRLast = ETHR;
    }

    /**
     * Blacklist the given address and remove it from rewards.
     */
    function _addToBlacklist(address addr) private {
        isBlacklisted[addr] = true;

        _excludeFromRewards(addr);
    }

    /**
     * Remove the given address from blacklist and include it to rewards.
     *
     * It must be blacklisted first.
     */
    function _removeFromBlacklist(address addr) private {
        require(isBlacklisted[addr], "the given address must be blacklisted");

        isBlacklisted[addr] = false;

        _includeToRewards(addr);
    }

    /**
     * Compute the pending rewards of the given share.
     *
     * The rewards earned since the last transfer are added to the already earned
     * rewards.
     */
    function _pendingRewards(Share memory share) private view returns (uint256) {
        uint256 RDiff = ETHR - share.ETHRLast;
        uint256 earned = (share.amount * RDiff) / precision;

        return share.earned + earned;
    }

    /**
     * Earn the rewards of the given share.
     */
    function _earn(Share storage share) private {
        uint256 pending = _pendingRewards(share);

        share.earned = pending;
        share.ETHRLast = ETHR;
    }

    /**
     * Claim the ETH rewards of user and returns the amount.
     */
    function _claim(address addr) private returns (uint256) {
        Share storage share = shareholders[addr];

        _earn(share);

        uint256 earned = share.earned;

        share.earned = 0;

        return earned;
    }

    /**
     * withdraw given amount of collected marketing tokens.
     */
    function _withdrawMarketing(uint256 amountToWithdraw) private {
        marketingAmount = 0;

        uint256 amountOut = _swapback(amountToWithdraw);

        payable(marketingWallet).transfer(amountOut);
    }

    /**
     * Update the total shares and the shares of the given address if it is not
     * excluded from rewards.
     *
     * Earn first with his current share amount then update shares according to
     * its new balance.
     */
    function _updateShare(address holder) private {
        if (isExcludedFromRewards[holder]) return;

        Share storage share = shareholders[holder];

        _earn(share);

        uint256 balance = balanceOf(holder);

        totalShares = totalShares - share.amount + balance;

        share.amount = balance;
        share.lastBlockUpdate = block.number;
    }

    /**
     * Sell the given amount of tokens for ETH and return the amount received.
     */
    function _swapback(uint256 amount) private returns (uint256) {
        // approve router to spend tokens.
        _approve(address(this), address(router), amount);

        // keep the original ETH balance to compute the swapped amount.
        uint256 originalBalance = payable(address(this)).balance;

        // swapback the whole amount to eth.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);

        // return the received amount.
        return payable(address(this)).balance - originalBalance;
    }

    /**
     * Sell the given amount of ETH for given ERC20 address to a given address and returns
     * the amount it received.
     */
    function _swapETHToERC20(uint256 ETHAmount, address token, address to, uint256 minAmountOut)
        private
        returns (uint256)
    {
        uint256 originalBalance = IERC20(token).balanceOf(to);

        // swapback the given ETHAmount to token.
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = token;

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ETHAmount}(
            minAmountOut, path, to, block.timestamp
        );

        return IERC20(token).balanceOf(to) - originalBalance;
    }

    /**
     * Only receive ETH from uniswap (router or pair).
     */
    receive() external payable {
        require(msg.sender == address(router) || pairs[msg.sender], "cant send eth to this address");
    }
}
