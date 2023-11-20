// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20Rewards} from "../src/ERC20Rewards.sol";

contract Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        ERC20Rewards token = new ERC20Rewards("Niera Token", "NTKN");
        token.initialize{value: 1000 ether}(1e6);
        vm.stopBroadcast();
    }
}
