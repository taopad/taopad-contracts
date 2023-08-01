// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AccessControlDefaultAdminRules} from "openzeppelin/access/AccessControlDefaultAdminRules.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IUniswapV2Factory} from "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

contract ERC20Rewards is AccessControlDefaultAdminRules, ERC20 {
    uint256 private constant precision = 1e18;

    uint256 private constant feeDenominator = 10000;

    address private marketingAddress;

    IUniswapV2Router02 private constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // rewards system.
    uint256 private ETHRAcc;
    uint256 private ETHRewardAmountAcc;
    uint256 private ETHMarketingAmountAcc;

    uint256 private rewardFeeAmountAcc;
    uint256 private marketingFeeAmountAcc;

    // shares management of the token.
    uint256 private totalShares;

    mapping(address => Share) private shareholders;

    struct Share {
        uint256 amount;
        uint256 earned;
        uint256 ETHRLast;
    }

    // public information.
    uint256 public buyRewardFee = 800;
    uint256 public buyMarketingFee = 200;
    uint256 public buyTotalFee = buyRewardFee + buyMarketingFee;

    uint256 public sellRewardFee = 800;
    uint256 public sellMarketingFee = 200;
    uint256 public sellTotalFee = sellRewardFee + sellMarketingFee;

    uint256 public ETHTotalRewarded;

    mapping(address => bool) public ammPairs;
    mapping(address => bool) public excludedFromRewards;

    // taxes are not enabled from the start for initial liq.
    bool public taxesEnabled;

    constructor(string memory name, string memory symbol, uint256 _totalSupply)
        AccessControlDefaultAdminRules(0, msg.sender)
        ERC20(name, symbol)
    {
        // mint total supply to deployer.
        _mint(msg.sender, _totalSupply * 10 ** decimals());

        // deployer is original marketing fee receiver.
        marketingAddress = msg.sender;

        // exclude this contract from rewards.
        _excludeFromRewards(address(this));

        // create this pair and register it.
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.createPair(router.WETH(), address(this));

        _addAmmPair(pair);
    }

    function rewardFeeAmount() internal view returns (uint256) {
        return (balanceOf(address(this)) * rewardFeeAmountAcc) / (rewardFeeAmountAcc + marketingFeeAmountAcc);
    }

    function rewardFeeAmount(Share memory share) internal view returns (uint256) {
        return (rewardFeeAmount() * share.amount) / totalShares;
    }

    function pendingRewards(address addr) external view returns (uint256) {
        return _pendingRewards(shareholders[addr]);
    }

    function claim() external {
        Share storage share = shareholders[msg.sender];

        uint256 pending = _pendingRewards(share);

        if (pending == 0) return;

        share.earned = 0;
        share.ETHRLast = ETHRAcc;
        ETHRewardAmountAcc -= pending;

        payable(msg.sender).transfer(pending);
    }

    function marketingPendingRewards() external view returns (uint256) {
        require(msg.sender == marketingAddress, "sender must be marketing address");

        return ETHMarketingAmountAcc;
    }

    function withdrawMarketing() external {
        require(msg.sender == marketingAddress, "sender must be marketing address");

        uint256 amount = ETHMarketingAmountAcc;

        ETHMarketingAmountAcc = 0;

        payable(marketingAddress).transfer(amount);
    }

    function distribute() external {
        _distribute();
    }

    function enableTaxes() external onlyRole(DEFAULT_ADMIN_ROLE) {
        taxesEnabled = true;
    }

    function disableTaxes() external onlyRole(DEFAULT_ADMIN_ROLE) {
        taxesEnabled = false;
    }

    function _excludeFromRewards(address addr) internal {
        excludedFromRewards[addr] = true;
    }

    function _addAmmPair(address addr) internal {
        ammPairs[addr] = true;
        _excludeFromRewards(addr);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        // get whether it is a buy/sell that should be taxed.
        bool _isSelf = address(this) == from || address(this) == to;
        bool _isTaxedBuy = taxesEnabled && !_isSelf && ammPairs[from];
        bool _isTaxedSell = taxesEnabled && !_isSelf && ammPairs[to];

        // compute the fees.
        uint256 _rewardFee = (_isTaxedBuy ? buyRewardFee : 0) + (_isTaxedSell ? sellRewardFee : 0);
        uint256 _marketingFee = (_isTaxedBuy ? buyMarketingFee : 0) + (_isTaxedSell ? sellMarketingFee : 0);

        // compute the fee amount
        uint256 _rewardFeeAmount = (amount * _rewardFee) / feeDenominator;
        uint256 _marketingFeeAmount = (amount * _marketingFee) / feeDenominator;
        uint256 _totalFeeAmount = _rewardFeeAmount + _marketingFeeAmount;

        // accumulates total reward and marketing fee amount.
        if (_rewardFeeAmount > 0) rewardFeeAmountAcc += _rewardFeeAmount;
        if (_marketingFeeAmount > 0) marketingFeeAmountAcc += _marketingFeeAmount;

        super._transfer(from, to, amount - _totalFeeAmount);

        // transfer the total fee amount to this contract.
        if (_totalFeeAmount > 0) {
            super._transfer(from, address(this), _totalFeeAmount);
        }

        _updateShare(from);
        _updateShare(to);
    }

    function _updateShare(address addr) internal {
        // only reward addresses not excluded from rewards.
        if (excludedFromRewards[addr]) return;

        // compute how much shareholder earned since last update.
        Share storage share = shareholders[addr];

        uint256 balance = balanceOf(addr);
        uint256 originalShareAmount = share.amount;
        uint256 pending = _pendingRewards(share);

        // update shareholder data.
        share.amount = balance;
        share.earned = pending;
        share.ETHRLast = ETHRAcc;

        // update total shares.
        totalShares = totalShares - originalShareAmount + balance;
    }

    function _pendingRewards(Share memory share) internal view returns (uint256) {
        uint256 RDiff = ETHRAcc - share.ETHRLast;
        uint256 earned = (share.amount * RDiff) / precision;

        return share.earned + earned;
    }

    function _distribute() internal {
        // get the contract balance.
        uint256 balance = balanceOf(address(this));

        // nothing happen when nothing to distribute.
        if (balance == 0) return;

        // approve router to spend stored tokens.
        _approve(address(this), address(router), balance);

        // swapback the whole balance of this contract to eth.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(balance, 0, path, address(this), block.timestamp);

        // just ensure to not distribute if no shares or no fee yet.
        // in this case ETH is accumulated for next distribution.
        uint256 _totalShares = totalShares;
        uint256 _rewardFeeAmountAcc = rewardFeeAmountAcc;
        uint256 _totalFeeAmountAcc = _rewardFeeAmountAcc + marketingFeeAmountAcc;

        if (_totalShares == 0) return;
        if (_totalFeeAmountAcc == 0) return;

        // compute the eth to distribute = ETH balance - current pending rewards.
        uint256 ETHBalance = address(this).balance;
        uint256 ETHToDistribute = ETHBalance - ETHRewardAmountAcc - ETHMarketingAmountAcc;

        // accumulate ETH rewards according to the amount of fee accumulated.
        uint256 ETHRewardAmount = (ETHToDistribute * _rewardFeeAmountAcc) / _totalFeeAmountAcc;

        ETHRewardAmountAcc += ETHRewardAmount;
        ETHMarketingAmountAcc += (ETHToDistribute - ETHRewardAmount);
        ETHRAcc += (ETHRewardAmount * precision) / _totalShares;
        ETHTotalRewarded += ETHRewardAmount;

        // reset the accumulated fee.
        rewardFeeAmountAcc = 0;
        marketingFeeAmountAcc = 0;
    }

    receive() external payable {}
}
