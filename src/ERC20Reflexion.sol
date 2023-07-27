// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AccessControlDefaultAdminRules} from "openzeppelin/access/AccessControlDefaultAdminRules.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MyToken is AccessControlDefaultAdminRules, ERC20 {
    constructor(string memory name, string memory symbol, uint256 totalSupply)
        AccessControlDefaultAdminRules(0, msg.sender)
        ERC20(name, symbol)
    {
        _mint(msg.sender, totalSupply * 10 ** decimals());
    }
}
