// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {BoundedCronReactive} from "../src/BoundedCronReactive.sol";
import {BoundedCronCallback} from "../src/BoundedCronCallback.sol";

contract DeployBoundedCronReactive is Script {
    function run() external {
        require(block.chainid == 5318007, "expected Lasna");
        uint256 destinationChainId = vm.envUint("CRON_DESTINATION_CHAIN_ID");
        uint256 maxRuns = vm.envUint("CRON_MAX_RUNS");
        uint256 funding = vm.envUint("CRON_REACTIVE_FUNDING_WEI");

        vm.startBroadcast();
        BoundedCronReactive reactive = new BoundedCronReactive{value: funding}(destinationChainId, maxRuns);
        vm.stopBroadcast();
        console2.log("CRON_REACTIVE_ADDR", address(reactive));
    }
}

contract DeployBoundedCronCallback is Script {
    address internal constant SEPOLIA_CALLBACK_PROXY = 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4;

    function run() external {
        uint256 destinationChainId = vm.envUint("CRON_DESTINATION_CHAIN_ID");
        require(block.chainid == destinationChainId, "wrong destination chain");
        require(destinationChainId == 11155111, "only Sepolia is configured");
        address proxy = vm.envAddress("CRON_CALLBACK_PROXY_ADDR");
        require(proxy == SEPOLIA_CALLBACK_PROXY, "wrong Sepolia callback proxy");
        require(proxy.code.length > 0, "callback proxy has no code");
        address reactive = vm.envAddress("CRON_REACTIVE_ADDR");
        uint256 maxRuns = vm.envUint("CRON_MAX_RUNS");
        uint256 funding = vm.envUint("CRON_CALLBACK_FUNDING_WEI");

        vm.startBroadcast();
        BoundedCronCallback callback =
            new BoundedCronCallback{value: funding}(IPayable(payable(proxy)), reactive, maxRuns);
        vm.stopBroadcast();
        console2.log("CRON_CALLBACK_ADDR", address(callback));
    }
}

contract StartBoundedCron is Script {
    function run() external {
        require(block.chainid == 5318007, "expected Lasna");
        BoundedCronReactive reactive = BoundedCronReactive(payable(vm.envAddress("CRON_REACTIVE_ADDR")));
        address callback = vm.envAddress("CRON_CALLBACK_ADDR");

        vm.startBroadcast();
        reactive.setRecipient(callback);
        reactive.start();
        vm.stopBroadcast();
        console2.log("CRON_STARTED", address(reactive));
    }
}
