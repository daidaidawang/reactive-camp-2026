# AgentSentinel 规则模式下的跨链处置

## 知识点

Reactive 订阅源链事件后，会把日志交给 Lasna 上的 `AgentSentinel.react()`。合约根据事件中的 `amount` 和 `maxSpend` 判断是否越额；满足条件后调用 Reactive SYSTEM 发起目标链 Callback。

## 过程

这次使用的是 AgentSentinel 自己的合约，没有用示例合约改名。

1. 源链是 Sepolia。测试 Agent 调用 `SentinelExecutor.executeOrder()`，请求金额为 60 ETH，授权上限为 10 ETH。合约没有转出 60 ETH，只记录请求金额，并发出 `ActionReceipt` 和 `RiskAlert`。
2. Reactive 链是 Lasna。`AgentSentinel` 收到 `RiskAlert` 后执行 `react()`。这次临时把 `aiMode` 设为 `false`，所以合约按规则检查 `60 > 10`，记录告警并发送 level 3 Callback。Lasna 交易里可以看到 `AlertObserved(aiMode=false)` 和 `Dispatched(level=3)`。
3. 目标链是 Sepolia。Callback Proxy 调用 `SentinelCallbackTarget.onSentinelVerdict()`。回调检查来源后执行 L3 处置：撤销 `trade.v3` 能力、罚没测试质押、把 Agent 状态改为 `Revoked`。

目标链只发生了一笔 Callback 交易；AgentSentinel 当前的 L3 实现会在这笔交易里执行三项处置。测试后已把 `aiMode` 恢复为 `true`。

## 交易记录

| 环节 | 交易 |
|---|---|
| Sepolia 源链事件：`RiskAlert`，60 ETH 请求高于 10 ETH 上限 | [查看交易](https://sepolia.etherscan.io/tx/0xb80aa0ef41421f14ce818a44f05afbbb7881c54a8619b2eda74e6b84ce993666) |
| Lasna Reactive：`react()` 记录越额并发起 Callback | [查看交易](https://lasna-omni.reactscan.net/tx/0xdfced36065c24b9c1b810703c74e893295be6ee3aa0b24955bc98e82bf6a6717) |
| Sepolia 目标链：Callback Proxy 调用处置合约 | [查看交易](https://sepolia.etherscan.io/tx/0x1a516f8f5cc18935be4c89731e77946754621797f02c5c45a5fc89cd4be4efeb) |
| 测试后恢复 AI 模式 | [查看交易](https://lasna-omni.reactscan.net/tx/0xaa19dbff8a2d39b78ae00967b737e943c370fc13140795fea3f29f1618a8a214) |

链上结果：Agent 状态为 `Revoked`，`trade.v3` 已撤销，测试质押余额为 0。

## 时序图

```text
测试 Agent（Sepolia）
    │ executeOrder(trade.v3, 60 ETH)
    ▼
SentinelExecutor（Sepolia）
    │ 检查上限：60 ETH > 10 ETH
    │ 发出 RiskAlert(receiptId=5)
    ▼
Reactive SYSTEM
    │ 把 RiskAlert 交给 react()
    ▼
AgentSentinel（Lasna）
    │ 按规则判断越额
    │ requestCallbackV_1_0()
    ▼
Sepolia Callback Proxy
    │ 调用 onSentinelVerdict(..., level=3)
    ▼
SentinelCallbackTarget（Sepolia）
    ├─ 撤销 trade.v3
    ├─ 罚没测试质押
    └─ Agent 状态改为 Revoked
```

## 代码位置

- [SentinelExecutor.sol](../agentsentinel/src/SentinelExecutor.sol)：检查额度并发出 `RiskAlert`。
- [AgentSentinel.sol](../agentsentinel/src/AgentSentinel.sol)：订阅事件，在 `react()` 中判断并发起 Callback。
- [SentinelCallbackTarget.sol](../agentsentinel/src/SentinelCallbackTarget.sol)：校验 Callback 来源并执行处置。

记录日期：2026-11-25
