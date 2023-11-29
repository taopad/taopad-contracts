// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";

contract Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        new ERC20Rewards("Reward token", "RTK");
        vm.stopBroadcast();
    }
}
