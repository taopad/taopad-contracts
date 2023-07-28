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

    // amount of accumulated fees since last swapback.
    uint256 private rewardFeeAmountAcc;
    uint256 private marketingFeeAmountAcc;

    // rewards system.
    uint256 private ETHRAcc;
    uint256 private ETHRewardAmountAcc;
    uint256 private ETHMarketingAmountAcc;

    uint256 private totalShares;

    mapping(address => Share) private shareholders;

    struct Share {
        uint256 amount;
        uint256 earned;
        uint256 ETHRLast;
    }

    // public information.
    uint256 public buyRewardFee = 600;
    uint256 public buyMarketingFee = 200;
    uint256 public buyTotalFee = buyRewardFee + buyMarketingFee;

    uint256 public sellRewardFee = 600;
    uint256 public sellMarketingFee = 200;
    uint256 public sellTotalFee = sellRewardFee + sellMarketingFee;

    uint256 public ETHTotalRewarded;

    uint256 public swapbackThreshold;

    mapping(address => bool) public ammPairs;
    mapping(address => bool) public excludedFromRewards;

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

    function pendingRewards() external view returns (uint256) {
        return _pendingRewards(shareholders[msg.sender]);
    }

    function claim() external {
        Share storage share = shareholders[msg.sender];

        uint256 pending = _pendingRewards(share);

        if (pending == 0) return;

        share.earned = 0;
        share.ETHRLast = ETHRAcc;
        ETHRewardAmountAcc -= pending;

        // should so a swap here.
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

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // get whether it is a buy/sell that should be taxed.
        bool isSelf = address(this) == from || address(this) == to;
        bool isTaxedBuy = isSelf && ammPairs[from];
        bool isTaxedSell = isSelf && ammPairs[to];

        // compute the fees.
        uint256 rewardFee = (isTaxedBuy ? buyRewardFee : 0) + (isTaxedSell ? sellRewardFee : 0);
        uint256 marketingFee = (isTaxedBuy ? buyMarketingFee : 0) + (isTaxedSell ? sellMarketingFee : 0);

        // compute the fee amount
        uint256 rewardFeeAmount = (amount * rewardFee) / feeDenominator;
        uint256 marketingFeeAmount = (amount * marketingFee) / feeDenominator;
        uint256 totalFeeAmount = rewardFeeAmount + marketingFeeAmount;

        // accumulates total reward and marketing fee amount.
        if (rewardFeeAmount > 0) rewardFeeAmountAcc += rewardFeeAmount;
        if (marketingFeeAmount > 0) marketingFeeAmountAcc += marketingFeeAmount;

        // transfer the total fee amount to this contract.
        if (totalFeeAmount > 0) _transfer(from, address(this), totalFeeAmount);

        return super.transferFrom(from, to, amount - totalFeeAmount);
    }

    function _excludeFromRewards(address addr) internal {
        excludedFromRewards[addr] = true;
    }

    function _addAmmPair(address addr) internal {
        ammPairs[addr] = true;
        _excludeFromRewards(addr);
    }

    function _afterTokenTransfer(address from, address to, uint256) internal virtual override {
        // do nothing on minting or burning.
        if (from == address(0)) return;
        if (to == address(0)) return;

        // preform swpaback and update sender/receiver shares.
        _swapBack();
        _updateShare(from);
        _updateShare(to);
    }

    function _swapBack() internal {
        // get the balance of this contract and swapback if needed.
        uint256 balance = balanceOf(address(this));

        if (balance < swapbackThreshold) return;

        // swapback the whole amount held by this contract to eth.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(balance, 0, path, address(this), block.timestamp);

        // if no shares yet we dont distribute anything.
        if (totalShares == 0) return;

        // if no fee accumulated we dont distribute (someone sent to the contract directly?)
        uint256 totalFeeAmountAcc = rewardFeeAmountAcc + marketingFeeAmountAcc;

        if (totalFeeAmountAcc == 0) return;

        // compute the eth to distribute = ETH balance - current pending rewards.
        uint256 ETHBalance = address(this).balance;
        uint256 ETHTotalAmountAcc = ETHRewardAmountAcc + ETHMarketingAmountAcc;
        uint256 ETHToDistribute = ETHBalance - ETHTotalAmountAcc;

        // accumulate ETH rewards according to the amount of fee accumulated.
        uint256 ETHRewardAmount = (ETHToDistribute * rewardFeeAmountAcc) / totalFeeAmountAcc;

        ETHRewardAmountAcc += ETHRewardAmount;
        ETHMarketingAmountAcc += ETHToDistribute - ETHRewardAmount;
        ETHRAcc += (ETHRewardAmount * precision) / totalShares;
        ETHTotalRewarded += ETHRewardAmount;

        // reset the accumulated fee.
        rewardFeeAmountAcc = 0;
        marketingFeeAmountAcc = 0;
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

    receive() external payable {}
}
