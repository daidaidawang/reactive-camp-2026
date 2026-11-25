// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {CapabilityRegistry} from "../src/CapabilityRegistry.sol";
import {AccountabilityVault} from "../src/AccountabilityVault.sol";
import {SentinelExecutor} from "../src/SentinelExecutor.sol";

/// @notice Testnet-only, single-account walkthrough. Use a fresh deployment.
contract DemoOrders is Script {
    bytes32 internal constant CAP_ID = keccak256("AGENTSENTINEL_DEMO_2026");

    function run() external {
        require(block.chainid == 11155111, "expected Sepolia");
        address account = vm.envAddress("DEMO_ACCOUNT_ADDR");
        AgentRegistry registry = AgentRegistry(vm.envAddress("REGISTRY_ADDR"));
        CapabilityRegistry caps = CapabilityRegistry(vm.envAddress("CAPABILITY_ADDR"));
        AccountabilityVault vault = AccountabilityVault(vm.envAddress("VAULT_ADDR"));
        SentinelExecutor executor = SentinelExecutor(vm.envAddress("EXECUTOR_ADDR"));
        require(executor.merchant() == account, "merchant differs from demo account");
        require(executor.resolver() != address(0), "not wired");

        vm.startBroadcast();
        registry.registerAgent(account, "did:agentsentinel:demo-2026");
        caps.grantCapability(account, CAP_ID, 0.003 ether, block.timestamp + 1 days, "fixed-merchant-demo");
        executor.fund{value: 0.01 ether}();
        vault.stake{value: 0.005 ether}();
        executor.executeOrder(CAP_ID, 0.002 ether);
        executor.claimPayment();
        executor.executeOrder(CAP_ID, 0.004 ether);
        vm.stopBroadcast();

        console2.log("CAP_ID");
        console2.logBytes32(CAP_ID);
        console2.log("EXPECTED_NORMAL_RECEIPT", uint256(1));
        console2.log("EXPECTED_BLOCKED_RECEIPT", uint256(2));
    }
}
