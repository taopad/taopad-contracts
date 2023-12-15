// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Taopad} from "../src/Taopad.sol";

contract Initialize is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address taopadAddress = vm.envAddress("TAOPAD_ADDRESS");

        Taopad taopad = Taopad(payable(taopadAddress));

        vm.startBroadcast(deployerPrivateKey);
        taopad.initialize{value: 1.6 ether}();
        vm.stopBroadcast();
    }
}
