// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {CapabilityRegistry} from "../src/CapabilityRegistry.sol";
import {AccountabilityVault} from "../src/AccountabilityVault.sol";
import {SentinelExecutor} from "../src/SentinelExecutor.sol";
import {SentinelCallbackTarget} from "../src/SentinelCallbackTarget.sol";
import {AgentSentinel} from "../src/AgentSentinel.sol";

// Use --account with an encrypted Foundry keystore. No key is loaded by this script.
contract DeployCore is Script {
    function run() external {
        require(block.chainid == 11155111, "expected Sepolia");
        address payable merchant = payable(vm.envAddress("MERCHANT_ADDR"));
        uint256 minimumBond = vm.envUint("MINIMUM_BOND_WEI");
        uint256 totalSpendLimit = vm.envUint("TOTAL_SPEND_LIMIT_WEI");
        vm.startBroadcast();
        AgentRegistry registry = new AgentRegistry();
        CapabilityRegistry caps = new CapabilityRegistry();
        AccountabilityVault vault = new AccountabilityVault();
        SentinelExecutor executor = new SentinelExecutor(
            address(registry), address(caps), address(vault), merchant, minimumBond, totalSpendLimit
        );
        vault.setExecutor(address(executor));
        vm.stopBroadcast();
        console2.log("REGISTRY_ADDR", address(registry));
        console2.log("CAPABILITY_ADDR", address(caps));
        console2.log("VAULT_ADDR", address(vault));
        console2.log("EXECUTOR_ADDR", address(executor));
    }
}

contract DeployReactive is Script {
    function run() external {
        require(block.chainid == 5318007, "expected Lasna");
        address executor = vm.envAddress("EXECUTOR_ADDR");
        uint256 funding = vm.envUint("REACTIVE_FUNDING_WEI");
        vm.startBroadcast();
        AgentSentinel sentinel = new AgentSentinel{value: funding}(11155111, executor);
        vm.stopBroadcast();
        console2.log("SENTINEL_ADDR", address(sentinel));
    }
}

contract DeployCallback is Script {
    function run() external {
        require(block.chainid == 11155111, "expected Sepolia");
        address sentinel = vm.envAddress("SENTINEL_ADDR");
        SentinelExecutor executor = SentinelExecutor(vm.envAddress("EXECUTOR_ADDR"));
        IPayable proxy = IPayable(payable(vm.envAddress("CALLBACK_PROXY_ADDR")));
        uint256 funding = vm.envUint("CALLBACK_FUNDING_WEI");
        require(executor.resolver() == address(0), "already wired");
        vm.startBroadcast();
        SentinelCallbackTarget callback = new SentinelCallbackTarget{value: funding}(proxy, sentinel, address(executor));
        executor.agentRegistry().setOperator(address(callback));
        executor.capabilityRegistry().setRevoker(address(callback));
        executor.vault().setSlasher(address(callback));
        executor.setResolver(address(callback));
        vm.stopBroadcast();
        console2.log("CALLBACK_ADDR", address(callback));
    }
}

contract ConnectReactive is Script {
    function run() external {
        require(block.chainid == 5318007, "expected Lasna");
        AgentSentinel sentinel = AgentSentinel(payable(vm.envAddress("SENTINEL_ADDR")));
        address callback = vm.envAddress("CALLBACK_ADDR");
        vm.startBroadcast();
        sentinel.setRecipient(callback);
        vm.stopBroadcast();
    }
}
