// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title AgentSentinel — AI 智能体授权哨兵（Lasna 测试网，Omni 版）
/// @notice 双通道守护：
///  通道 A（AI 在环）：RiskAlert 事件到达 → 记录为待裁决告警 →
///         链下 AI 判读服务读取事件与授权上下文，生成结构化 verdict →
///         submitVerdict() 提交 → 本合约规则引擎逐项校验（AI 声称的等级
///         必须与链上证据一致，不能自行突破规则）→ requestCallbackV_1_0
///         跨链处置（撤权+罚没）。
///  通道 B（AI 缺席/降级）：react() 收到 RiskAlert 后直接按确定性规则
///         走 L3（事件里 amount/maxSpend 就是合约算出的证据）——
///         「杀死 AI，守护还活着」的落点。
///  Cron 副线：订阅 Cron10 定时事件，每 tick 回调目标链留痕，
///         满 N 次 unsubscribe 自动停止（场景 5 辅助演示）。
contract AgentSentinel is AbstractReactive {
    // ---------- 常量 ----------
    address internal constant LEGACY_SYSTEM_ADDR = 0x0000000000000000000000000000000000fffFfF;
    uint256 internal constant CRON10_TOPIC_0 = 0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687;
    uint64 internal constant CALLBACK_GAS_LIMIT = 1_000_000;

    /// @dev RiskAlert(uint256,address,bytes32,uint256,uint256) 的事件签名 topic0
    uint256 internal constant RISK_TOPIC_0 = uint256(keccak256("RiskAlert(uint256,address,bytes32,uint256,uint256)"));

    // ---------- 部署参数 ----------
    address public immutable _OWNER;
    uint256 public immutable ORIGIN_CHAIN_ID;   // Sepolia = 11155111
    address public immutable EXECUTOR;          // Sepolia 上的 SentinelExecutor
    uint256 public immutable CRON_MAX;          // Cron 满 N 次自动停止

    // ---------- 状态 ----------
    address public recipient;   // 回调目标（部署后由 owner 设置）
    bool public aiMode = true;  // true=通道A(AI在环) false=通道B(纯规则)
    bool public cronStopped;

    uint256 public cronRuns;

    /// @notice react() 观测到的告警（通道 A 的待裁决队列 + 证据存证）
    struct Alert {
        address agent;
        bytes32 capId;
        uint256 amount;
        uint256 maxSpend;
        bool open;        // true=待裁决
        uint256 observedAt;
    }
    mapping(uint256 => Alert) public alerts;

    // ---------- 事件 ----------
    event AlertObserved(uint256 indexed receiptId, address indexed agent, bytes32 indexed capId, uint256 amount, uint256 maxSpend, bool aiMode);
    event VerdictAccepted(uint256 indexed receiptId, uint256 level, address indexed judge, string reason);
    event VerdictRejected(uint256 indexed receiptId, uint256 level, address indexed judge, string reason);
    event Dispatched(uint256 indexed receiptId, address indexed agent, uint256 level);
    event CronTick(uint256 indexed run);
    event CronAutoStopped(uint256 totalRuns);

    error NotOwner(address caller);
    error RecipientNotSet();
    error AlertNotFound(uint256 receiptId);
    error EvidenceMismatch(uint256 receiptId);

    modifier onlyOwner() {
        if (msg.sender != _OWNER) revert NotOwner(msg.sender);
        _;
    }

    constructor(uint256 originChainId_, address executor_, uint256 cronMax_) payable {
        _OWNER = msg.sender;
        ORIGIN_CHAIN_ID = originChainId_;
        EXECUTOR = executor_;
        CRON_MAX = cronMax_;

        // 订阅①：Sepolia 上的 RiskAlert 财务越界证据流（topic1-3 全放行）
        SYSTEM.subscribe(
            originChainId_,
            executor_,
            RISK_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // 订阅②：本链 legacy 系统合约的 Cron10 定时事件
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON10_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    // ---------- 管理员 ----------

    function setRecipient(address recipient_) external onlyOwner {
        recipient = recipient_;
    }

    /// @notice 通道切换：false = 纯规则引擎（AI 缺席降级演示）
    function setAiMode(bool aiMode_) external onlyOwner {
        aiMode = aiMode_;
    }

    function coverDebt() external onlyOwner {
        _coverDebt();
    }

    // ---------- 反应层 ----------

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // 注意：opCode 是 topic 数量判据（Transfer 3 个 topic→3，RiskAlert 4 个→4），
        // 不能用作日志类型守卫。topic0 精确匹配已足够，其余一律静默 return（绝不 revert）。
        if (log_.topic0 == RISK_TOPIC_0 && log_.contractAddress == EXECUTOR) {
            _handleRiskAlert(log_);
        } else if (log_.topic0 == CRON10_TOPIC_0 && cronStopped == false) {
            _handleCronTick();
        }
    }

    function _handleRiskAlert(LogRecord memory log_) internal {
        uint256 receiptId = log_.topic1;
        address agent = address(uint160(log_.topic2));
        bytes32 capId = bytes32(log_.topic3);
        (uint256 amount, uint256 maxSpend) = abi.decode(log_.data, (uint256, uint256));

        alerts[receiptId] = Alert({
            agent: agent,
            capId: capId,
            amount: amount,
            maxSpend: maxSpend,
            open: true,
            observedAt: block.timestamp
        });
        emit AlertObserved(receiptId, agent, capId, amount, maxSpend, aiMode);

        // 通道 B：AI 缺席时由确定性规则直接走 L3（证据已由源链合约算出）
        if (!aiMode) {
            _dispatchL3(receiptId);
        }
        // 通道 A：保持 open，等待 AI 的 submitVerdict
    }

    function _handleCronTick() internal {
        cronRuns += 1;
        emit CronTick(cronRuns);

        // 每 tick 也回调目标链留痕（证明定时链路活着）
        if (recipient != address(0)) {
            SYSTEM.requestCallbackV_1_0(
                ISystemContract.CallbackConfiguration_V_1_0({
                    chainId: ORIGIN_CHAIN_ID,
                    recipient: recipient,
                    gasLimit: CALLBACK_GAS_LIMIT,
                    payload: abi.encodeWithSignature("cronCallback(address,uint256)", address(0), cronRuns)
                })
            );
        }

        // ★ 满 N 次 → 自动退订（六参数必须与 subscribe 逐位一致）
        if (cronRuns >= CRON_MAX) {
            cronStopped = true;
            SYSTEM.unsubscribe(
                block.chainid,
                LEGACY_SYSTEM_ADDR,
                CRON10_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            emit CronAutoStopped(cronRuns);
        }
    }

    // ---------- 决策层：AI verdict 提交口（通道 A） ----------

    /// @notice AI 判读服务提交结构化裁决。规则引擎在此校验——
    ///         AI 只能解读与建议，不能突破链上证据自行支配资产。
    /// @param receiptId_ 告警回执号（必须已由 react() 观测到）
    /// @param level_     处置等级 0-3（L2 挂起 / L3 撤权+罚没）
    /// @param reason_    AI 白话判读理由（仅存证，不参与判定）
    function submitVerdict(uint256 receiptId_, uint256 level_, string calldata reason_) external onlyOwner {
        Alert storage a = alerts[receiptId_];
        if (a.observedAt == 0) revert AlertNotFound(receiptId_);
        if (!a.open) revert EvidenceMismatch(receiptId_);

        // 规则引擎校验①：声称 L3 必须有真实超额证据（amount > maxSpend）
        if (level_ >= 3 && a.amount <= a.maxSpend) {
            emit VerdictRejected(receiptId_, level_, msg.sender, reason_);
            revert EvidenceMismatch(receiptId_);
        }
        // 规则引擎校验②：等级必须是合法档位
        if (level_ > 3) {
            emit VerdictRejected(receiptId_, level_, msg.sender, reason_);
            revert EvidenceMismatch(receiptId_);
        }

        a.open = false;
        emit VerdictAccepted(receiptId_, level_, msg.sender, reason_);

        if (level_ >= 3) {
            _dispatchL3(receiptId_);
        } else if (level_ == 2) {
            _dispatchL2(receiptId_);
        }
        // L0/L1：只接受裁决记录，不动权限（过罚相当）
    }

    // ---------- 处置层 ----------

    function _dispatchL3(uint256 receiptId_) internal {
        if (recipient == address(0)) revert RecipientNotSet();
        Alert storage a = alerts[receiptId_];
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: ORIGIN_CHAIN_ID,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: abi.encodeWithSignature(
                    "onSentinelVerdict(address,address,bytes32,uint256,uint256)",
                    address(0),
                    a.agent,
                    a.capId,
                    receiptId_,
                    uint256(3)
                )
            })
        );
        emit Dispatched(receiptId_, a.agent, 3);
    }

    function _dispatchL2(uint256 receiptId_) internal {
        if (recipient == address(0)) revert RecipientNotSet();
        Alert storage a = alerts[receiptId_];
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: ORIGIN_CHAIN_ID,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: abi.encodeWithSignature(
                    "onSentinelVerdict(address,address,bytes32,uint256,uint256)",
                    address(0),
                    a.agent,
                    a.capId,
                    receiptId_,
                    uint256(2)
                )
            })
        );
        emit Dispatched(receiptId_, a.agent, 2);
    }
}
