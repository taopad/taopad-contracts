// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";
import {ERC20RewardsCompounder} from "../src/ERC20RewardsCompounder.sol";

contract DeployCompounder is Script {
    address[] addrs;
    uint256[] allocs;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ERC20RewardsAddress = vm.envAddress("ERC20_REWARDS_ADDRESS");

        ERC20Rewards token = ERC20Rewards(payable(ERC20RewardsAddress));

        vm.startBroadcast(deployerPrivateKey);
        new ERC20RewardsCompounder("Reward token share", "sRTK", token);
        vm.stopBroadcast();
    }
}
