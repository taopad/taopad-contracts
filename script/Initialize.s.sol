// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";

contract Initialize is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ERC20RewardsAddress = vm.envAddress("ERC20_REWARDS_ADDRESS");

        ERC20Rewards token = ERC20Rewards(payable(ERC20RewardsAddress));

        vm.startBroadcast(deployerPrivateKey);
        token.initialize{value: 1000 ether}(1e6);
        vm.stopBroadcast();
    }
}
