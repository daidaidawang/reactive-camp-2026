// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AgentRegistry } from "./AgentRegistry.sol";
import { CapabilityRegistry } from "./CapabilityRegistry.sol";

/// @title SentinelExecutor — Agent 敏感操作的唯一入口 + 回执锚定
/// @notice 回应评委追问②③：
///  ② 「违规操作能否绕过回执」——下单唯一入口是本合约，回执由合约计算
///     requestedAmount 与 allowance 的对比结果，不是 Agent 自报；
///  ③ 「跨链回调前还能否继续操作」——窗口期内每次操作都留回执
///     （事后可追罚保证金），撤权落地后本合约立刻拒绝。
contract SentinelExecutor {
    AgentRegistry public immutable agentRegistry;
    CapabilityRegistry public immutable capabilityRegistry;

    uint256 public receiptSeq;

    event ActionReceipt(
        uint256 indexed receiptId,
        address indexed agent,
        bytes32 indexed capId,
        uint256 amount,
        uint256 maxSpend,
        bool overLimit,
        uint256 at
    );
    /// @notice 财务越界风险证据。topic1=receiptId topic2=agent topic3=capId，
    ///         非索引 data=(amount, maxSpend)——证据由合约算出上链。
    event RiskAlert(uint256 indexed receiptId, address indexed agent, bytes32 indexed capId, uint256 amount, uint256 maxSpend);

    error AgentNotActive(address agent);
    error CapabilityNotActive(bytes32 capId);
    error WindowExpired(uint256 validUntil, uint256 nowTs);

    constructor(address agentRegistry_, address capabilityRegistry_) {
        agentRegistry = AgentRegistry(agentRegistry_);
        capabilityRegistry = CapabilityRegistry(capabilityRegistry_);
    }

    /// @notice Agent 执行一次敏感操作（demo 语义：一笔订单）。
    ///         msg.sender 必须是被注册且 Active 的 Agent。
    function executeOrder(bytes32 capId_, uint256 amount_) external returns (uint256 receiptId_) {
        // ① 身份检查：被注册且处于 Active（Suspended/Revoked 即拒）
        if (!agentRegistry.isActive(msg.sender)) revert AgentNotActive(msg.sender);

        // ② 授权边界检查：能力激活且在有效期内（block.timestamp）
        (uint256 maxSpend, uint256 validUntil,, bool capActive) = capabilityRegistry.getCapability(msg.sender, capId_);
        if (!capActive) revert CapabilityNotActive(capId_);
        if (block.timestamp > validUntil) revert WindowExpired(validUntil, block.timestamp);

        // ③ 回执锚定：超额与否由合约判定并写入回执（不可由 Agent 自报）
        bool overLimit = amount_ > maxSpend;
        receiptId_ = ++receiptSeq;

        emit ActionReceipt(receiptId_, msg.sender, capId_, amount_, maxSpend, overLimit, block.timestamp);

        // ④ 财务越界 → 发出结构化风险证据事件（Reactive 网络订阅的就是它）
        if (overLimit) {
            emit RiskAlert(receiptId_, msg.sender, capId_, amount_, maxSpend);
        }
        // 注意：超额不 revert——操作已留痕，走「事后跨链处置+罚没」路线，
        // 这正是「窗口期操作可追责」的语义。
    }
}
