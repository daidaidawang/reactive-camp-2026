# Reactive Builder Camp 2026 — 学习仓库

> Reactive Network Omni 版跨链自动化训练营（2026-11-16 → 12/5）
> 课程页：https://web3career.build/zh/programs/reactive-builder-camp
> 黑客松：Reactive Omni Buildathon（DoraHacks，总奖金 $5,500）

## 仓库结构

```
reactive-camp-2026/
├── README.md            # 本文件：进度总览
├── notes/               # 每日打卡笔记
│   ├── 2026-11-16.md    # Day 1：开营，为什么需要 Reactive
│   ├── 2026-11-17.md    # Day 2：源链、目标链与费用模型
│   └── 2026-11-18.md    # Day 3：第一个 Reactive 合约（本日产出）
└── reactive-monitor/    # Day 3 练习代码（Foundry 项目）
    ├── src/CampXfersMonitor.sol   # 监控合约（Omni 版）
    ├── src/MockERC20.sol          # 测试代币
    └── ...
```

## 环境要求

- Foundry（forge / cast / anvil）
- 依赖库：`forge install Reactive-Network/reactive-lib-omni --branch master`
  （如 clone 本仓库，请手动执行此命令；remappings 已配置 `@reactive/=lib/reactive-lib-omni/`）
- 私钥等敏感信息一律放在 `.env` / `*.env`，**已被 .gitignore 排除，绝不入库**

## 关键网络参数（Omni 版）

| 项 | 值 |
|---|---|
| Lasna 测试网 RPC | https://lasna-rpc.rnk.dev/ |
| Lasna chainId | 5318007 |
| Sepolia chainId | 11155111 |
| SYSTEM 合约 | 0x8888888888888888888888888888888888888888 |
| Sepolia faucet 合约 | 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434（1 ETH → 100 lREACT） |

## 进度总览

| 日期 | 内容 | 状态 |
|---|---|---|
| 11/16（一） | 开营 · 为什么需要 Reactive | ✅ |
| 11/17（二） | 源链、目标链与费用模型 | ✅ |
| 11/18（三） | 第一个 Reactive 合约：监控 Sepolia ERC-20 Transfer | ✅ 见 notes/2026-11-18.md |
| 11/19（四） | 跨链回调（requestCallbackV_1_0） | ⏳ |
| 11/20（五） | 定时任务与动态订阅 | ⏳ |
| 11/21（六） | 选题 + DoraHacks 报名 | ⏳ |
| 11/22（日） | 缓冲日 | ⏳ |

## Day 3 成果速览

- **Lasna 监控合约**：`0x1E3b32cB9F31868212b9938c57d76d3fC2Af12dd`
- **Sepolia 测试代币 CTT**：`0xeD2f9C6Be45d8287515428B5FA60E0f2FcEb2e51`
- **react() 已触发 2 次**，reactive 交易：`0x43acedd363cca1d8c225f31020697323e575d5d2be9cbc044592d7988939515b`（Lasna 区块 8624019）
- 订阅条件：CTT 的 Transfer，单笔 ≥ 5 CTT 才计数，上限 3 次自动退订
