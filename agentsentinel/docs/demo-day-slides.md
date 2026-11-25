# AgentSentinel：受限付款与可核对的跨链处置

Demo Day 演示稿｜Track 3：Reactive Meets AI｜口播约 2 分 45 秒

## 第 1 页｜让 Agent 只能按授权采购

**画面文字**

- 固定商户
- 单笔授权上限
- Executor 预存 ETH 预算
- 超额请求：源链拒付、保存回执、锁定保证金

**讲词**

“给链上 Agent 一笔预算时，项目方需要限制它能向谁付款、每次最多花多少，并在超额请求发生后留下能核对的证据。AgentSentinel 把付款入口限制在一个 Executor 和固定商户。额度内订单可以记为商户待领取的债权；超额订单在源链就被拒绝，不会转成商户付款。”

## 第 2 页｜一个风险请求怎样走到处置

**画面文字**

```text
Agent
  │ executeOrder(capId, amount)
  ▼
Sepolia Executor ── RiskAlert + ActionReceipt ──▶ Lasna AgentSentinel
      │                                               │
      └─ 拦付款 / 锁保证金                          核验来源 / 去重
                                                      │ requestCallback
                                                      ▼
Sepolia Callback ── 撤销授权 / 吊销身份 / 罚没 / settle 回执
```

**讲词**

“Executor 会检查 Agent 身份、能力授权、保证金、可用预算和全局累计支出上限。对于超额请求，它保存 ActionReceipt 并发出 RiskAlert。Reactive 只接受来自指定 Sepolia Executor 的指定 topic，核验金额确实大于授权上限，再向 Sepolia Callback 请求处置。目标合约还会回读源链 Executor 保存的回执，确认信息匹配后才执行状态变化。”

## 第 3 页｜确定性规则和 AI 的分工

**画面文字**

```text
输入：agent / merchant / amount / maxSpend / receiptId
判定：amount > maxSpend
AI 输出：面向人工的自然语言解释
合约执行：固定 level 3；AI 不可降级或改罚没金额
```

**讲词**

“这里不让模型决定什么叫违规。金额超过授权额度是一个确定性比较，合约和 Reactive 规则负责拦截与处置。AI 路径只读取已核对的 Agent、商户、金额、额度和回执，生成供人审阅的解释；它不能把违规改成通过，也不能决定罚没多少。本次没有真实模型调用，因此实际演示明确标记为规则模式。”

## 第 4 页｜链上和本地验证结果

**画面文字**

| 已验证内容 | 结果 |
| --- | --- |
| Foundry AgentSentinel 与 Cron100 | 34 项通过，0 失败 |
| Node.js 判读服务 | 12 项通过，0 失败 |
| 本地 fuzz 边界与资金守恒 | 2 个 fuzz 用例，各 256 轮 |
| 最新版公开测试网地址和跨链交易 | 尚未部署 / 尚无交易 |

**讲词**

“本地 Foundry 覆盖来源过滤、单笔和累计上限、重复处理、超额拦截、回调鉴权、失败回滚与恢复；两个 fuzz 测试各跑 256 轮。Node.js 服务有 12 项测试。本地使用 SYSTEM 和 Callback Proxy 替身，所以这些测试不能当作公开链交易，也不能证明跨链网络已经投递。”

## 第 5 页｜失败时怎样判断和恢复

**画面文字**

- Executor 预算不足：订单回滚；项目方补充预算后再试
- Reactive/Callback 费用欠费：暂停；向对应系统/代理 `depositTo(address)` 补费
- 目标回调失败：整笔处置回滚，保证金仍锁定；修复后按等待时间重试
- 完成判断：目标端 `processed=true` 且源链 `settled=true`

**讲词**

“失败不会被说成成功。预算不够时付款不会发生；Reactive 或 Callback 欠费时网络会停止对应执行，必须给正确的系统或代理为目标合约补费。目标回调如果失败，撤权、罚没和回执结算原子回滚，保证金仍锁定，修复后才能重试。最终要同时查到目标端 processed 和源链 settled。”

## 第 6 页｜范围和当前交付状态

**画面文字**

- 保护范围：进入 Executor 的 ETH 订单、单一固定商户
- 未覆盖：任意 EOA、Safe、DEX、ERC-20、生产资金、多链权限同步
- 最新版尚未部署；旧地址和旧交易不代表当前版本
- 测试环境：Sepolia + Reactive Lasna；等待部署账户与测试币配置

**讲词**

“这是测试网原型，不是生产钱包保护层。现在只处理进入 Executor 的 ETH 订单和一个固定商户，没有接管任意钱包、DEX 或通用跨链资产，也没有完成多条目的链权限同步。最新版尚未部署，所以我不把旧版本地址或交易拿来证明新代码。下一步是在 Sepolia 和 Reactive Lasna 部署当前提交，按同一回执核对源链事件、Reactive 交易和目标链完成状态后，再录制实链视频。谢谢。”

## 2 分钟问答答词

**为什么要用 Reactive？**
“它用于验证独立事件处理和异步目标链回调。就当前只在 Sepolia 的资产而言，单链直接撤权更简单；Reactive 会增加费用、延迟和活性依赖，所以我们不声称它对这个单链案例是必需的。”

**AI 的作用是什么？**
“模型只解释已核对的证据。`amount > maxSpend` 决定是否违规，规则决定处置；模型不能降级或改变金额。当前没有真实 LLM 调用。”

**重复事件会怎样？**
“Reactive 用 receiptId 记录已见告警，Callback 用 receiptId 记录已处理结果；重复通知不会重复请求处置，重复回调不会再次撤权或罚没。”

**怎样证明目标链真的完成了？**
“把 Sepolia 的 RiskAlert/ActionReceipt、Lasna 的 react()、Sepolia 的 DispositionExecuted 关联到同一个 receiptId，并读取 Callback 的 processed 和 Executor 的 settled。只看 Dispatched 不算完成。”

**这版已经部署或审计了吗？**
“没有。最新版本目前只有本地测试结果，还没有新版测试网交易，也没有第三方审计；我会按实际状态提交，不把旧版或模拟数据冒充新版证据。”

日期：2026-11-25
