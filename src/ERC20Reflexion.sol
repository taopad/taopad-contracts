// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AccessControlDefaultAdminRules} from "openzeppelin/access/AccessControlDefaultAdminRules.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IUniswapV2Factory} from "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

contract ERC20Reflexion is AccessControlDefaultAdminRules, ERC20 {
    IUniswapV2Router02 private constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address private marketingFeeReceiver;

    uint256 private constant feeDenominator = 10000;

    uint256 public buyReflectionFee = 600;
    uint256 public buyMarketingFee = 200;
    uint256 public buyTotalFee = buyReflectionFee + sellReflectionFee;

    uint256 public sellReflectionFee = 600;
    uint256 public sellMarketingFee = 200;
    uint256 public sellTotalFee = sellReflectionFee + sellMarketingFee;

    uint256 public buybackThreshold;

    mapping(address => bool) public pairs;

    constructor(string memory name, string memory symbol, uint256 _totalSupply)
        AccessControlDefaultAdminRules(0, msg.sender)
        ERC20(name, symbol)
    {
        // mint total supply to deployer.
        _mint(msg.sender, _totalSupply * 10 ** decimals());

        // deployer is original marketing fee receiver.
        marketingFeeReceiver = msg.sender;

        // set the buyback threshold to 0.1% of supply.
        buybackThreshold = totalSupply() / 1000;

        // create this pair and register it.
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.createPair(router.WETH(), address(this));

        pairs[pair] = true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee;

        // buy tax when from pair or router.
        if (pairs[from] || address(router) == from) {
            fee = (amount * buyReflectionFee) / feeDenominator;
        }

        // sell tax when to pair or router.
        if (pairs[to] || address(router) == to) {
            fee = (amount * sellReflectionFee) / feeDenominator;
        }

        if (fee > 0) {
            _transfer(from, address(this), fee);
        }

        if (balanceOf(address(this)) > buybackThreshold) {
            // perform buyback.
            // contract must exempt itself.
        }

        return super.transferFrom(from, to, amount - fee);
    }
}
