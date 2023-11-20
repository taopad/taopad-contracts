// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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

    // numerator multiplier so tokenPerShare does not get rounded to 0.
    uint256 private constant PRECISION = 1e18;

    // the accumulated amount of ETH per share.
    uint256 private ETHPerShare;

    // total shares of this token.
    // (different from total supply because of fees and excluded wallets).
    uint256 public totalShares;

    // shareholders record.
    // (non excluded addresses are updated after they send/receive tokens).
    mapping(address => Share) private shareholders;

    struct Share {
        uint256 amount; // recorded balance after last transfer.
        uint256 earned; // amount of tokens earned but not claimed yet.
        uint256 ETHPerShareLast; // token per share value of the last earn occurrence.
    }

    // amount of ETH ever claimed by holders.
    uint256 public totalETHClaimed;

    // total amount of ETH ever sent as rewards.
    uint256 public totalETHDistributed;

    // minimum amount of token to distribute on sell.
    uint256 private distributionThreshold;

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

    // contract addresses that opted in for rewards.
    mapping(address => bool) public isOptin;

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
    uint256 private _marketingAmount;

    // =========================================================================
    // Events.
    // =========================================================================

    event Claim(address indexed to, uint256 amount);
    event Distribute(address indexed from, uint256 amount);

    // =========================================================================
    // constructor.
    // =========================================================================

    constructor(string memory name, string memory symbol) Ownable(msg.sender) ERC20(name, symbol) {
        marketingWallet = msg.sender;
    }

    // =========================================================================
    // init contract.
    // =========================================================================

    /**
     * Initialize the contract by minting tokens and adding initial liquidity.
     *
     * It adds the total supply of the token with the sent ETH.
     *
     * LP tokens are sent to owner.
     */
    function initialize(uint256 _rawTotalSupply) external payable onlyOwner {
        require(startBlock == 0, "already initialized");

        startBlock = block.number;

        // get total supply.
        uint256 _totalSupply = _rawTotalSupply * 10 ** decimals();

        // init max wallet to 1%.
        maxWallet = _totalSupply / 100;

        // create an amm pair with WETH.
        // pair gets automatically excluded from rewards.
        createAmmPairWith(router.WETH());

        // mint total supply to this contract.
        _mint(address(this), _totalSupply);

        // approve router to use total supply.
        _approve(address(this), address(router), _totalSupply);

        // add liquidity and send LP to owner.
        router.addLiquidityETH{value: msg.value}(address(this), _totalSupply, 0, 0, msg.sender, block.timestamp);
    }

    // =========================================================================
    // exposed user functions.
    // =========================================================================

    /**
     * Return the user pending rewards.
     */
    function pendingRewards(address holder) external view returns (uint256) {
        return _pendingRewards(shareholders[holder]);
    }

    /**
     * Claim ETH rewards.
     */
    function claim() external nonReentrant {
        uint256 claimed = _claim(shareholders[msg.sender]);

        if (claimed == 0) return;

        totalETHClaimed += claimed;

        emit Claim(msg.sender, claimed);
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
        require(!isBlacklisted[msg.sender], "blacklisted");
        require(_isExcludedFromRewards(msg.sender), "sender already included to rewards");

        _includeToRewards(msg.sender);

        isOptin[msg.sender] = true;
    }

    /**
     * Optout for rewards when you are included to rewards (contracts).
     */
    function rewardOptout() external {
        require(!isBlacklisted[msg.sender], "blacklisted");
        require(_isExcludedFromRewards(msg.sender), "sender already excluded from rewards");

        _removeFromRewards(msg.sender);

        isOptin[msg.sender] = false;
    }

    /**
     * Distribute current rewards as ETH.
     */
    function distribute() external nonReentrant {
        uint256 balance = _rewardBalance();

        uint256 distributed = _distribute(balance);

        if (distributed == 0) return;

        emit Distribute(msg.sender, distributed);
    }

    /**
     * Sweep any other ERC20 mistakenly sent to this contract.
     */
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

    function setDistributionThreshold(uint256 _distributionThreshold) external onlyOwner {
        distributionThreshold = _distributionThreshold;
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

    function marketingAmount() external view onlyOwner returns (uint256) {
        return _marketingAmount;
    }

    function withdrawMarketing() external {
        require(msg.sender == marketingWallet, "not marketing wallet");

        _withdrawMarketing(_marketingAmount);
    }

    function withdrawMarketing(uint256 amountToWithdraw) external {
        require(msg.sender == marketingWallet, "not marketing wallet");
        require(amountToWithdraw <= _marketingAmount, "amount must be <= currentMarketingAmount()");

        _withdrawMarketing(amountToWithdraw);
    }

    function _withdrawMarketing(uint256 amountToWithdraw) private {
        _marketingAmount -= amountToWithdraw;

        transfer(marketingWallet, amountToWithdraw);
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
     * Return whether current block is a dead block (= get blacklisted when buying
     * in a dead block).
     */
    function _isDeadBlock() private view returns (bool) {
        return block.number <= startBlock + deadBlocks;
    }

    /**
     * Return addresses excluded from max wallet limit (= this contract, router or pairs).
     */
    function _isExcludedFromMaxWallet(address addr) private view returns (bool) {
        return addr == address(this) || addr == address(router) || pairs[addr];
    }

    /**
     * Return adresses excluded from taxes (= this contract address or router).
     */
    function _isExcludedFromTaxes(address addr) private view returns (bool) {
        return address(this) == addr || address(router) == addr;
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
        require(!isBlacklisted[addr], "already blacklisted");

        _removeFromRewards(addr);

        isBlacklisted[addr] = true;
    }

    /**
     * Remove the given address from blacklist.
     */
    function _removeFromBlacklist(address addr) private {
        require(isBlacklisted[addr], "not blacklisted");

        _includeToRewards(addr);

        isBlacklisted[addr] = false;
    }

    /**
     * Include the given address to rewards. Should only concern:
     *
     * - addresses of contracts opting in for rewards.
     * - addresses being removed from blacklist.
     */
    function _includeToRewards(address addr) private {
        uint256 balance = balanceOf(addr);

        Share storage share = shareholders[addr];

        share.amount = balance;
        share.earned = 0;
        share.ETHPerShareLast = ETHPerShare;

        totalShares += balance;
    }

    /**
     * Remove the given address from rewards. Should only concern:
     *
     * - addresses of contracts opting out of rewards.
     * - addresses being added to blacklist.
     */
    function _removeFromRewards(address addr) private {
        _earn(shareholders[addr]);

        totalShares -= balanceOf(addr);
    }

    /**
     * Return the reward amount as token amount.
     */
    function _rewardBalance() private view returns (uint256) {
        return balanceOf(address(this)) - _marketingAmount;
    }

    /**
     * Compute the pending rewards of the given share.
     *
     * The rewards earned since the last transfer are added to the already earned
     * rewards.
     */
    function _pendingRewards(Share memory share) private view returns (uint256) {
        uint256 RDiff = ETHPerShare - share.ETHPerShareLast;
        uint256 earned = (share.amount * RDiff) / PRECISION;

        return share.earned + earned;
    }

    /**
     * Earn the rewards of the given share.
     */
    function _earn(Share storage share) private {
        uint256 pending = _pendingRewards(share);

        share.earned = pending;
        share.ETHPerShareLast = ETHPerShare;
    }

    /**
     * Claim the rewards of the given share and return the claim amount.
     */
    function _claim(Share storage share) private returns (uint256) {
        uint256 pending = _pendingRewards(share);

        share.earned = 0;
        share.ETHPerShareLast = ETHPerShare;

        return pending;
    }

    /**
     * Override the update method in order to take fee when transfer is from/to
     * a registered amm pair.
     *
     * - transfers from/to this contract are not taxed.
     * - transfers from/to uniswap router are not taxed.
     * - addresses buying in a deadblock are blacklisted and cant transfer tokens anymore.
     * - prevent receiving address to get more than max wallet.
     * - marketing fees are collected and distributed here.
     * - taxes are sent to this very contract for later claim.
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

        // prevents max wallet on transfer to a non pair address.
        if (!_isExcludedFromMaxWallet(to)) {
            require(transferActualAmount + balanceOf(to) <= maxWallet, "max-wallet-reached");
        }

        // add to blacklist while buying in dead block.
        if (isTaxedBuy && _isDeadBlock()) {
            _addToBlacklist(to);
        }

        // transfer the actual amount.
        super._update(from, to, transferActualAmount);

        // accout for the marketing fee if any.
        if (transferMarketingFeeAmount > 0) {
            _marketingAmount += transferMarketingFeeAmount;
        }

        // transfer the total fee amount to this contract if any.
        if (transferTotalFeeAmount > 0) {
            super._update(from, address(this), transferTotalFeeAmount);
        }

        // updates shareholders values.
        _updateShare(from);
        _updateShare(to);

        // on sell we distribute when balance is above threshold.
        if (isTaxedSell) {
            _distributeIfAboveThreshold(from);
        }
    }

    /**
     * Update the total shares and the shares of the given address if it is not
     * excluded from rewards.
     *
     * Earn first with his current share amount then update shares according to
     * its new balance.
     */
    function _updateShare(address holder) private {
        if (_isExcludedFromRewards(holder)) return;

        Share storage share = shareholders[holder];

        _earn(share);

        uint256 balance = balanceOf(holder);

        totalShares = totalShares - share.amount + balance;

        share.amount = balance;
    }

    /**
     * Distribute the given amount of tokens as rewards.
     */
    function _distribute(uint256 amount) private returns (uint256) {
        if (totalShares == 0) return 0;

        uint256 distributed = _swapToETH(address(this), amount, 0);

        ETHPerShare += (distributed * PRECISION) / totalShares;

        totalETHDistributed += distributed;

        return distributed;
    }

    /**
     * Distribute from addr when above distribution threshold.
     */
    function _distributeIfAboveThreshold(address from) private {
        uint256 balance = _rewardBalance();
        if (balance > distributionThreshold) {
            uint256 distributed = _distribute(balance);

            if (distributed == 0) return;

            emit Distribute(from, distributed);
        }
    }

    /**
     * Sell amount of tokens for ETH to the given address and return the amount it received.
     */
    function _swapToETH(address to, uint256 amountIn, uint256 amountOutMin) private returns (uint256) {
        // approve router to spend tokens.
        _approve(address(this), address(router), amountIn);

        // keep the original ETH balance to compute the swapped amount.
        uint256 originalBalance = payable(to).balance;

        // swapback the whole amount to eth.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, amountOutMin, path, to, block.timestamp);

        // return the received amount.
        return payable(to).balance - originalBalance;
    }

    /**
     * This contract cant receive ETH.
     */
    receive() external payable {
        require(msg.sender == address(router) || pairs[msg.sender], "cant send eth to this contract");
    }
}
