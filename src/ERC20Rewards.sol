// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AccessControlDefaultAdminRules} from "openzeppelin/access/AccessControlDefaultAdminRules.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {IUniswapV2Pair} from "uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

contract ERC20Rewards is AccessControlDefaultAdminRules, ERC20 {
    // =========================================================================
    // dependencies.
    // =========================================================================

    IUniswapV2Router02 private constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // =========================================================================
    // rewards accounting.
    // =========================================================================

    // the amount of ETH per this token share.
    uint256 private _ETHR;

    // the amount of ETH distributed but not claimed yet.
    uint256 private _ETHRewardAmount;

    // total amount of ETH ever distributed.
    uint256 private _ETHTotalRewarded;

    // total shares of this token.
    // (different from total supply because of fees and excluded wallets).
    uint256 private _totalShares;

    // shareholders record.
    // (gets updated after transfer from/to a non excluded address).
    mapping(address => Share) private _shareholders;

    struct Share {
        uint256 amount; // recorded balance before last transfer.
        uint256 earned; // amount of ETH earned but not claimed yet.
        uint256 ETHRLast; // _ETHR value of the last time ETH was earned.
    }

    // numerator multiplier so _ETHR does not get rounded to 0.
    uint256 private constant precision = 1e18;

    // =========================================================================
    // marketing fee.
    // =========================================================================

    // only address allowed to view and withdraw marketing fees.
    address private _marketingAddress;

    // the amount of this token collected as marketing fee.
    uint256 private _marketingFeeAmount;

    // =========================================================================
    // taxes setting.
    // =========================================================================

    // bps denominator.
    uint256 private constant feeDenominator = 10000;

    // buy taxes bps.
    uint256 public buyRewardFee = 800;
    uint256 public buyMarketingFee = 200;
    uint256 public buyTotalFee = buyRewardFee + buyMarketingFee;

    // sell taxes bps.
    uint256 public sellRewardFee = 800;
    uint256 public sellMarketingFee = 200;
    uint256 public sellTotalFee = sellRewardFee + sellMarketingFee;

    // amm pair addresses the tranfers from/to are taxed.
    // (populated with WETH/this token pair address in the constructor).
    mapping(address => bool) public ammPairs;

    // addresses not receiving rewards.
    // (populated with this token address in the constructor).
    mapping(address => bool) public excludedFromRewards;

    // taxes are not enabled from the start for initial liq deposit.
    bool public taxesEnabled;

    // =========================================================================
    // constructor.
    // =========================================================================

    constructor(string memory name, string memory symbol, uint256 _totalSupply)
        AccessControlDefaultAdminRules(0, msg.sender)
        ERC20(name, symbol)
    {
        // mint total supply to deployer.
        _mint(msg.sender, _totalSupply * 10 ** decimals());

        // exclude this contract from rewards.
        _excludeFromRewards(address(this));

        // create an amm pair with WETH.
        _createAmmPairWith(router.WETH());

        // set deployer as original marketing address.
        _marketingAddress = msg.sender;
    }

    // =========================================================================
    // exposed view functions.
    // =========================================================================

    function rewardFeeAmount() external view returns (uint256) {
        return _rewardFeeAmount();
    }

    function rewardFeeAmount(address addr) external view returns (uint256) {
        return _rewardFeeAmount(_shareholders[addr]);
    }

    function approxRewardFeeAmountAsETH() external view returns (uint256) {
        return _approxValueAs(router.WETH(), _rewardFeeAmount());
    }

    function approxRewardFeeAmountAsETH(address addr) external view returns (uint256) {
        return _approxValueAs(router.WETH(), _rewardFeeAmount(_shareholders[addr]));
    }

    function extraETHAmount() external view returns (uint256) {
        return _extraETHAmount();
    }

    function pendingRewards(address addr) external view returns (uint256) {
        return _pendingRewards(_shareholders[addr]);
    }

    function totalRewarded() external view returns (uint256) {
        return _ETHTotalRewarded;
    }

    // =========================================================================
    // exposed user functions.
    // =========================================================================

    function claim() external {
        Share storage share = _shareholders[msg.sender];

        uint256 pending = _pendingRewards(share);

        if (pending == 0) return;

        share.earned = 0;
        share.ETHRLast = _ETHR;
        _ETHRewardAmount -= pending;

        payable(msg.sender).transfer(pending);
    }

    function distributeRewards() external {
        _distributeRewards();
    }

    function liquifyRewards() external {
        _liquifyRewards();
    }

    function burnRewards() external {
        _burnRewards();
    }

    function buybackExtra() external {
        _buybackExtra();
    }

    // =========================================================================
    // exposed admin functions.
    // =========================================================================

    function enableTaxes() external onlyRole(DEFAULT_ADMIN_ROLE) {
        taxesEnabled = true;
    }

    function disableTaxes() external onlyRole(DEFAULT_ADMIN_ROLE) {
        taxesEnabled = false;
    }

    function excludeFromRewards(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _excludeFromRewards(addr);
    }

    function createAmmPairWith(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _createAmmPairWith(addr);
    }

    function recordAmmPairWith(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _recordAmmPairWith(addr);
    }

    function setBuyFee(uint256 rewardFee, uint256 marketingFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(rewardFee + marketingFee <= 20000, "20% total buy fee max");

        buyRewardFee = rewardFee;
        buyMarketingFee = marketingFee;
        buyTotalFee = rewardFee + marketingFee;
    }

    function setSellFee(uint256 rewardFee, uint256 marketingFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(rewardFee + marketingFee <= 20000, "20% total sell fee max");

        sellRewardFee = rewardFee;
        sellMarketingFee = marketingFee;
        sellTotalFee = rewardFee + marketingFee;
    }

    function sweep(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this) != addr, "cant sweep reward token");

        IERC20 token = IERC20(addr);

        uint256 amount = token.balanceOf(address(this));

        token.transfer(msg.sender, amount);
    }

    // =========================================================================
    // exposed marketing functions.
    // =========================================================================

    function marketingFeeAmount() external view returns (uint256) {
        require(msg.sender == _marketingAddress, "sender must be marketing address");

        return _marketingFeeAmount;
    }

    function withdrawMarketing() external {
        require(msg.sender == _marketingAddress, "sender must be marketing address");

        uint256 amount = _marketingFeeAmount;

        _marketingFeeAmount = 0;

        transfer(msg.sender, amount);
    }

    function setMarketingAddress() external {
        require(msg.sender == _marketingAddress, "sender must be marketing address");

        _marketingAddress = msg.sender;
    }

    // =========================================================================
    // internal functions.
    // =========================================================================

    /**
     * compute the reward fee amount.
     *
     * it is the balance of this contract minus the fee collected for marketing.
     */
    function _rewardFeeAmount() internal view returns (uint256) {
        return balanceOf(address(this)) - _marketingFeeAmount;
    }

    /**
     * compute the reward fee amount of the given share.
     */
    function _rewardFeeAmount(Share memory share) internal view returns (uint256) {
        return (_rewardFeeAmount() * share.amount) / _totalShares;
    }

    /**
     * return the amount of ETH manually sent to this contract.
     *
     * this is the ETH balance not part of a reward distribution.
     */
    function _extraETHAmount() internal view returns (uint256) {
        return payable(address(this)).balance - _ETHRewardAmount;
    }

    /**
     * compute the pending rewards of the given share.
     *
     * the rewards earned since the last transfer are added to the already
     * earned rewards.
     */
    function _pendingRewards(Share memory share) internal view returns (uint256) {
        uint256 RDiff = _ETHR - share.ETHRLast;
        uint256 earned = (share.amount * RDiff) / precision;

        return share.earned + earned;
    }

    /**
     * compute the value of given amount in term of given token address.
     */
    function _approxValueAs(address addr, uint256 amount) internal view returns (uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(addr, address(this)));

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        uint256 tokenReserve = address(this) == pair.token0() ? reserve0 : reserve1;
        uint256 otherReserve = address(this) == pair.token0() ? reserve1 : reserve0;

        return (amount * otherReserve) / tokenReserve;
    }

    /**
     * Override the transfer method in order to take fee when transfer is from/to
     * a registered amm pair.
     *
     * - taxes must be enabled
     * - transfers from/to this contract are not taxed
     * - marketing fees are collected here
     * - taxes are sent to this very contract for later distribution
     * - updates the shares of both the from and to addresses
     */
    function _transfer(address from, address to, uint256 amount) internal override {
        // get whether it is a buy/sell that should be taxed.
        bool isSelf = address(this) == from || address(this) == to;
        bool isTaxedBuy = taxesEnabled && !isSelf && ammPairs[from];
        bool isTaxedSell = taxesEnabled && !isSelf && ammPairs[to];

        // compute the fees.
        uint256 rewardFee = (isTaxedBuy ? buyRewardFee : 0) + (isTaxedSell ? sellRewardFee : 0);
        uint256 marketingFee = (isTaxedBuy ? buyMarketingFee : 0) + (isTaxedSell ? sellMarketingFee : 0);

        // compute the fee amount.
        uint256 transferRewardFeeAmount = (amount * rewardFee) / feeDenominator;
        uint256 transferMarketingFeeAmount = (amount * marketingFee) / feeDenominator;
        uint256 transferTotalFeeAmount = transferRewardFeeAmount + transferMarketingFeeAmount;

        // accumulates the marketing fee amount.
        if (transferMarketingFeeAmount > 0) {
            _marketingFeeAmount += transferMarketingFeeAmount;
        }

        // actually transfer the tokens minus the fee.
        super._transfer(from, to, amount - transferTotalFeeAmount);

        // transfer the total fee amount to this contract.
        if (transferTotalFeeAmount > 0) {
            super._transfer(from, address(this), transferTotalFeeAmount);
        }

        // updates shareholders values.
        _updateShare(from);
        _updateShare(to);
    }

    /**
     * Update the total shares and the shares of the given address if it is not
     * excluded from rewards.
     */
    function _updateShare(address addr) internal {
        if (excludedFromRewards[addr]) return;

        // get the shareholder pending rewards.
        Share storage share = _shareholders[addr];

        uint256 pending = _pendingRewards(share);

        // update total shares and this shareholder data.
        uint256 balance = balanceOf(addr);

        _totalShares = _totalShares - share.amount + balance;

        share.amount = balance;
        share.earned = pending;
        share.ETHRLast = _ETHR;
    }

    /**
     * distribute fee amount as rewards by swapping it to ETH.
     */
    function _distributeRewards() internal {
        // ensure to not distribute if no fee collected or no shares.
        uint256 amountToSwap = _rewardFeeAmount();
        uint256 totalShares = _totalShares;

        if (amountToSwap == 0) return;
        if (totalShares == 0) return;

        // swapback for eth.
        uint256 ETHToDistribute = _swapback(amountToSwap);

        // update the distribution values.
        _ETHR += (ETHToDistribute * precision) / totalShares;
        _ETHRewardAmount += ETHToDistribute;
        _ETHTotalRewarded += ETHToDistribute;
    }

    /**
     * add the fee amount as liquidity by swapping half as eth.
     *
     * LP tokens are minted to the sender.
     */
    function _liquifyRewards() internal {
        // ensure to not liquify if no fee collected.
        uint256 amountToLP = _rewardFeeAmount();

        if (amountToLP == 0) return;

        // get two half.
        uint256 firstHalfToken = amountToLP / 2;
        uint256 secondHalfToken = amountToLP - firstHalfToken;

        // swapback second half.
        uint256 secondHalfETH = _swapback(secondHalfToken);

        // add liquidity by minting LP to sender.
        router.addLiquidityETH{value: secondHalfETH}(address(this), firstHalfToken, 0, 0, msg.sender, block.timestamp);
    }

    /**
     * burn the fee amount.
     */
    function _burnRewards() internal {
        // ensure to not burn if no fee collected.
        uint256 amountToBurn = _rewardFeeAmount();

        if (amountToBurn == 0) return;

        // actually burn.
        _burn(address(this), amountToBurn);
    }

    /**
     * buyback token using the ETH manually sent to this contract.
     */
    function _buybackExtra() internal {
        // ensure to not buyback if no extra ETH.
        uint256 amountToBuyback = _extraETHAmount();

        if (amountToBuyback == 0) return;

        // buyback the whole amount for this token.
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(this);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountToBuyback}(
            0, path, address(this), block.timestamp
        );
    }

    /**
     * Exclude the given wallet from rewards.
     *
     * What if it is a contract registered after getting rewards?
     * Should something be done with the pending rewards?
     */
    function _excludeFromRewards(address addr) internal {
        excludedFromRewards[addr] = true;
    }

    /**
     * Create an amm pair with the given token address, register it as an
     * amm and exclude it from rewards.
     */
    function _createAmmPairWith(address addr) internal {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.createPair(addr, address(this));

        ammPairs[pair] = true;

        _excludeFromRewards(pair);
    }

    /**
     * Record an existing amm pair with the given token address, register it
     * as an amm and exclude it from rewards.
     */
    function _recordAmmPairWith(address addr) internal {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.getPair(addr, address(this));

        ammPairs[pair] = true;

        _excludeFromRewards(pair);
    }

    /**
     * Sell the given amount of tokens for ETH.
     */
    function _swapback(uint256 amount) internal returns (uint256) {
        // approve router to spend tokens.
        _approve(address(this), address(router), amount);

        // keep the original ETH balance to compute the swapped amount.
        uint256 originalBalance = payable(address(this)).balance;

        // swapback the whole amount to eth.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);

        // return the swapped amount.
        return payable(address(this)).balance - originalBalance;
    }

    receive() external payable {}
}
