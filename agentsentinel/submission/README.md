# AgentSentinel 测试网演示与提交文件

记录日期：2026-11-25。当前代码在 Sepolia（11155111）和 Reactive Lasna（5318007）重新部署并完成真实回调。演示账户兼任项目方、Agent 与商户；这只验证受限合约路径，不证明角色分离或生产安全。

## 可直接查看的材料

- [2 分 08 秒中文讲解视频](AgentSentinel-3min-Demo.mp4)：含架构、真实交易/状态截图、测试和边界。
- [可编辑 Demo Day PPT](AgentSentinel-Demo-Day.pptx)：8 页，讲者备注含逐页讲词。
- [Sepolia 核心部署命令截图](screenshots/command-core.png)、[Lasna 部署与连接截图](screenshots/command-reactive.png)、[Sepolia 回调与角色配置截图](screenshots/command-callback.png)。
- [登记/授权/资金交易截图](screenshots/command-orders1.png)、[正常与超额订单截图](screenshots/command-orders2.png)、[三段跨链交易截图](screenshots/command-crosschain.png)、[最终状态截图](screenshots/command-state.png)。
- [`forge test -vv` 通过截图](screenshots/command-tests.png)、[完整输出](evidence/forge-test-2026-11-25.txt)、[可复跑的链上回执检查脚本](evidence/verify-chain.ps1)。
- [六个合约 Sourcify `exact_match` 截图](screenshots/command-verified.png)、[原始 `forge verify-check` 输出](evidence/source-verification.txt)。
- 浏览器页面截图：[Sepolia 超额订单](screenshots/sepolia-risk.png)、[Lasna reaction](screenshots/lasna-reaction.png)、[Sepolia 回调](screenshots/sepolia-callback.png)。

## 实际部署地址

| 链 | 合约 | 地址 |
| --- | --- | --- |
| Sepolia | AgentRegistry | [`0xe29aC90eCf7D28D972Face09d77d74EcF351A3e5`](https://eth-sepolia.blockscout.com/address/0xe29aC90eCf7D28D972Face09d77d74EcF351A3e5) |
| Sepolia | CapabilityRegistry | [`0xe2E5738697cB8a17e018868460B8F8A0a3621c17`](https://eth-sepolia.blockscout.com/address/0xe2E5738697cB8a17e018868460B8F8A0a3621c17) |
| Sepolia | AccountabilityVault | [`0x3BdF77755307dE44625A8A0d1bC6b05B6Ee62476`](https://eth-sepolia.blockscout.com/address/0x3BdF77755307dE44625A8A0d1bC6b05B6Ee62476) |
| Sepolia | SentinelExecutor | [`0xB6Daf06E3D65008430ac9F2E3ca5F402134844A1`](https://eth-sepolia.blockscout.com/address/0xB6Daf06E3D65008430ac9F2E3ca5F402134844A1) |
| Lasna | AgentSentinel | [`0xAA9e4ad766f9370B693c3F0f4245FaFaE86434dB`](https://lasna.reactscan.net/address/0xAA9e4ad766f9370B693c3F0f4245FaFaE86434dB) |
| Sepolia | SentinelCallbackTarget | [`0x1A4DCB8DFEa162ed09C5a3Be1A6275F404a62384`](https://eth-sepolia.blockscout.com/address/0x1A4DCB8DFEa162ed09C5a3Be1A6275F404a62384) |

部署参数：商户和 Agent 均为测试账户 `0x4b55Cf75A3A18E58ed78c1B7f27Aa4F1be59410d`；保证金下限 0.005 ETH；单笔授权上限 0.003 ETH；Executor 累计支出硬上限 0.05 ETH。演示给 Executor 充值 0.01 ETH，正常订单 0.002 ETH，超额请求 0.004 ETH。

## 同一回执的三段交易

| 阶段 | 交易 | 已核对结果 |
| --- | --- | --- |
| Sepolia 源链 | [`0xed54f19864303d97f5d4693f1896e9728e292530708591af35904c9f40e1acdf`](https://eth-sepolia.blockscout.com/tx/0xed54f19864303d97f5d4693f1896e9728e292530708591af35904c9f40e1acdf) | `executeOrder` 成功上链；回执 2 为超额，未形成商户付款 |
| Lasna reaction | [`0x84a8845d27e84d4c81c522e779090f496b729d94350732c1dcaea75bfe7fcab7`](https://lasna.reactscan.net/tx/0x84a8845d27e84d4c81c522e779090f496b729d94350732c1dcaea75bfe7fcab7) | `AlertObserved(2)`，`seen(2)=true` |
| Sepolia 目标回调 | [`0x2b06737bdbc1fe40a1c00a295afee165b2c76510964819b9e1474d28a218db12`](https://eth-sepolia.blockscout.com/tx/0x2b06737bdbc1fe40a1c00a295afee165b2c76510964819b9e1474d28a218db12) | `DispositionExecuted(2)`；`processed(2)=true`、源链 `settled=true` |

[链上状态读回原始输出](evidence/onchain-state.txt)显示：Agent 与能力已失活，0.005 ETH 保证金转入 `forfeited`；正常订单后 `totalSpent=0.002 ETH`、`availableBudget=0.008 ETH`、`merchantCredit=0`（商户已领取）。测试中的重复事件、失败回滚与累计限额有 Foundry 覆盖；这次实链演示没有人为重放事件或制造回调失败，不能把本地测试说成这两种情况的实链证明。

首次两笔 Sepolia 部署交易因 gas limit 不足失败，未创建合约；[失败回执截图](screenshots/command-failed.png)与原始输出保留。提高估算余量后的当前部署以表中的成功地址和交易为准。六个合约经 Sourcify 返回 `exact_match`；Blockscout 的首次独立验证请求失败，不能把 Sourcify 结果表述为 Blockscout 已验证。独立审计、真实 LLM 调用、角色分离和长期运行可靠性尚未完成。

本地 `forge test -vv`：34 passed、0 failed；Node.js 判读服务：12 passed、0 failed。演示视频使用合成中文配音与真实命令/浏览器截图，不是实时录屏；AI 展示为规则模式。
