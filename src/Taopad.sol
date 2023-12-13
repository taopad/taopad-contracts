// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC20Rewards} from "./ERC20Rewards.sol";

/// @title Taopad
/// @author @niera26
/// @notice buy and sell tax on this token with rewardToken as wTao
/// @notice source: https://github.com/taopad/taopad-contracts
contract Taopad is ERC20Rewards {
    constructor() ERC20Rewards("Taopad", "TPAD", 1e6) {}
}
