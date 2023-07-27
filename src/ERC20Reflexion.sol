// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AccessControlDefaultAdminRules} from "openzeppelin/access/AccessControlDefaultAdminRules.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IUniswapV2Factory} from "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

contract ERC20Reflexion is AccessControlDefaultAdminRules, ERC20 {
    IUniswapV2Router02 private constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 private constant feeDenominator = 10000;

    uint256 public buyReflectionFee = 600;
    uint256 public buyMarketingFee = 200;
    uint256 public buyTotalFee = 800;

    uint256 public sellReflectionFee = 600;
    uint256 public sellMarketingFee = 200;
    uint256 public sellTotalFee = 800;

    address private marketingFeeReceiver;

    mapping(address => bool) public pairs;

    constructor(string memory name, string memory symbol, uint256 totalSupply)
        AccessControlDefaultAdminRules(0, msg.sender)
        ERC20(name, symbol)
    {
        // mint total supply to deployer.
        _mint(msg.sender, totalSupply * 10 ** decimals());

        // deployer is original marketing fee receiver.
        marketingFeeReceiver = msg.sender;

        // create this pair and register it.
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.createPair(router.WETH(), address(this));

        pairs[pair] = true;
    }
}
