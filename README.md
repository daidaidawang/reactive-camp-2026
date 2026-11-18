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

- **Lasna 监控合约**：[Reactscan](https://lasna-omni.reactscan.net/address/0x1E3b32cB9F31868212b9938c57d76d3fC2Af12dd)（`0x1E3b32cB9F31868212b9938c57d76d3fC2Af12dd`）
- **Sepolia 测试代币 CTT**：`0xeD2f9C6Be45d8287515428B5FA60E0f2FcEb2e51`
- **react() 已触发并完成 3 次命中**：此前的 [Reactive 交易](https://lasna-omni.reactscan.net/tx/0x43acedd363cca1d8c225f31020697323e575d5d2be9cbc044592d7988939515b)（区块 8624019，count=2）；最后一次命中的 [Sepolia 转账](https://sepolia.etherscan.io/tx/0x26037056d061a72af9855112e9dd1c5bff7bbda0f056d8e12ce3ddd3639a3827) → [Reactive 交易](https://lasna-omni.reactscan.net/tx/0x51f23ac799e83c3a90257f904db7a324cd3d2a25dce9013acce0e8006c8050a4)（区块 8642323，count=3）
- **自动退订已验证**：最终 `_matchedCount = 3`、`_limit = 0`、SYSTEM debt = 0，当前 filter index 中已无 CTT 的 Transfer 订阅。
- **订阅条件**：监控 Sepolia 上 CTT 的 `Transfer`；只统计单笔 ≥ 5 CTT 的转账，命中 3 次后自动退订。
- **部署交易**：[Reactscan](https://lasna-omni.reactscan.net/tx/0x12154d80c18dd2e2b809cd2fea45b69f270b2060b246744df9e3ee51a8ab393e)

