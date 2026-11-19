// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { AgentRegistry } from "./AgentRegistry.sol";
import { CapabilityRegistry } from "./CapabilityRegistry.sol";
import { AccountabilityVault } from "./AccountabilityVault.sol";

/// @title SentinelCallbackTarget — Reactive 跨链回调的处置落点（Sepolia 侧）
/// @notice 继承 AbstractCallback：双重闸门（onlyServiceProvider + onlyCallbackSender）
///         保证回调确实来自我们部署的 Sentinel。回调费由本合约以 Sepolia ETH 支付。
contract SentinelCallbackTarget is AbstractCallback {
    AgentRegistry public immutable agentRegistry;
    CapabilityRegistry public immutable capabilityRegistry;
    AccountabilityVault public immutable vault;

    event DispositionExecuted(uint256 indexed receiptId, address indexed agent, bytes32 indexed capId, uint256 level, string action);
    event CronHandled(address indexed sender, uint256 tick);

    constructor(
        IPayable callbackProxy_,
        address callbackSender_,
        address agentRegistry_,
        address capabilityRegistry_,
        address vault_
    ) payable AbstractCallback(callbackProxy_, callbackSender_) {
        agentRegistry = AgentRegistry(agentRegistry_);
        capabilityRegistry = CapabilityRegistry(capabilityRegistry_);
        vault = AccountabilityVault(vault_);
    }

    /// @notice Sentinel 的跨链处置入口。
    ///         第一个参数会被回调代理覆写为发起回调的 Reactive 合约地址。
    function onSentinelVerdict(address reactive_, address agent_, bytes32 capId_, uint256 receiptId_, uint256 level_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        if (level_ >= 3) {
            // L3 终止：撤权 + 罚没 + 身份吊销，不可逆
            capabilityRegistry.revokeCapability(agent_, capId_, "L3: overspend revoked by Sentinel");
            vault.slash(agent_, "L3: stake forfeited for overspend");
            agentRegistry.setStatus(agent_, AgentRegistry.Status.Revoked, "L3: agent terminated");
            emit DispositionExecuted(receiptId_, agent_, capId_, level_, "revoke+slash+revokeIdentity");
        } else if (level_ == 2) {
            // L2 冻结：只降级身份，不动保证金（可恢复）
            agentRegistry.setStatus(agent_, AgentRegistry.Status.Suspended, "L2: suspended by Sentinel");
            emit DispositionExecuted(receiptId_, agent_, capId_, level_, "suspend");
        } else {
            // L0/L1：只留处置记录，不动权限（过罚相当）
            emit DispositionExecuted(receiptId_, agent_, capId_, level_, "log-only");
        }
    }

    /// @notice Cron 定时任务回调：证明「到期自动执行」链路（场景 5 辅助演示）。
    function cronCallback(address reactive_, uint256 tick_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        emit CronHandled(reactive_, tick_);
    }
}
