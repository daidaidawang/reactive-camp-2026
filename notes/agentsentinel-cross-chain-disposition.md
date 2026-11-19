# AgentSentinel 跨链回调处置

在 Sepolia 记录一次超出授权额度的操作。Reactive 合约在 Lasna 接收告警、校验裁决，再通过跨链回调在 Sepolia 撤销授权、罚没保证金并吊销 Agent 身份。

## 合约

- `SentinelExecutor`：检查 Agent 和能力授权，记录操作回执；金额超过上限时发出 `RiskAlert`。
- `AgentSentinel`：订阅 `RiskAlert` 和 Lasna 的 Cron10 事件，保存告警并处理裁决。
- `SentinelCallbackTarget`：接收跨链回调，在 Sepolia 执行处置。
- `CapabilityRegistry`、`AccountabilityVault`、`AgentRegistry`：分别管理能力授权、保证金和 Agent 身份。

## 流程

1. Sepolia 上的 Agent 调用 `SentinelExecutor.executeOrder()`，提交 60 ETH 的模拟订单金额。合约读取该 Agent 的能力上限 10 ETH，发出 `ActionReceipt` 和 `RiskAlert`。这里记录的是订单金额，不会实际转出 60 ETH。
2. Lasna 上的 `AgentSentinel` 订阅到 `RiskAlert` 后，`react()` 将证据写入告警记录。
3. 链下判读服务读取事件和授权上下文，生成 level 3 裁决，并调用 `AgentSentinel.submitVerdict()`。
4. `submitVerdict()` 检查告警是否存在、是否仍待处理，以及请求金额是否确实大于授权上限。校验通过后，合约调用 SYSTEM 的 `requestCallbackV_1_0()`。
5. Sepolia 回调代理调用 `SentinelCallbackTarget.onSentinelVerdict()`。回调目标依次撤销能力、罚没保证金、将 Agent 状态改为 `Revoked`。

## 验证

| 环节 | 结果 |
|---|---|
| Sepolia 超额操作 | 60 ETH，大于 10 ETH 授权上限；交易 `0x7dc980df...d4d113b` |
| Lasna 提交裁决 | level 3；交易 `0x4eebdfba...4ea0dd` |
| Sepolia 执行处置 | 交易 `0xf3681773...d8476d` |
| 能力授权 | `trade.v3` 状态变为 inactive |
| 保证金 | 0.02 ETH 全额罚没，余额变为 0 |
| Agent 身份 | 状态变为 `Revoked` |
| Cron | 累计 3 次后自动退订，`cronRuns = 3`、`cronStopped = true` |

## 复现时注意

- `SentinelCallbackTarget` 的回调入口同时检查 callback proxy 和发起回调的 Reactive 合约。
- 回调目标必须分别获得 `CapabilityRegistry` 的 revoker、`AccountabilityVault` 的 slasher、`AgentRegistry` 的 operator 权限，否则对应外部调用会回滚。
- `AgentSentinel` 构造函数订阅的源合约地址固定；更换 `SentinelExecutor` 后要重新部署或重新配置订阅。
- callback 投递失败时，代理交易可能仍成功并发出失败事件；需要检查代理事件中的目标调用数据。
- Lasna 执行费使用 lREACT，Sepolia callback 使用 Sepolia ETH。部署和运行前分别检查余额与欠费。

记录日期：2026-11-19


