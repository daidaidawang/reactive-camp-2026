# Reactive Builder Camp 2026

Reactive Omni 学习和实验记录。合约代码在 `reactive-monitor/`，每日笔记在 `notes/`。

课程：[Reactive Builder Camp](https://web3career.build/zh/programs/reactive-builder-camp)

## 目录

- `notes/reactive-network-basics.md`：Reactive Network 基础
- `notes/reactive-fees.md`：源链、目标链和费用
- `notes/sepolia-transfer-monitor.md`：监听 Sepolia 上的 ERC-20 Transfer
- `notes/agentsentinel-cross-chain-disposition.md`：AgentSentinel 跨链回调处置
- `notes/agentsentinel-rule-mode-e2e.md`：AgentSentinel 规则模式下的完整链路
- `notes/给项目加保护-防误触发、防重复、设上限.md`：测试材料、三项保护和失败模式
- `reactive-monitor/`：Foundry 合约和部署文件
- `agentsentinel/`：AgentSentinel 合约和判读服务
- `agentsentinel/README.md`：AgentSentinel 的能力边界、部署授权顺序和链下服务配置

## 网络参数

| 网络 | Chain ID | RPC |
|---|---:|---|
| Lasna | 5318007 | `https://lasna-rpc.rnk.dev/` |
| Sepolia | 11155111 | 使用本地 `.env` 中的 RPC |

Lasna SYSTEM：`0x8888888888888888888888888888888888888888`

## Transfer 监控实验

合约部署在 [Lasna / Reactscan](https://lasna.reactscan.net/address/0x1E3b32cB9F31868212b9938c57d76d3fC2Af12dd)，监控 Sepolia 上的测试代币 CTT：`0xeD2f9C6Be45d8287515428B5FA60E0f2FcEb2e51`。单笔转账不少于 5 CTT 才计数，累计命中 3 次后自动退订。

最后一次命中的 [Sepolia 转账](https://sepolia.etherscan.io/tx/0x26037056d061a72af9855112e9dd1c5bff7bbda0f056d8e12ce3ddd3639a3827) 对应 [Lasna `react()` 交易](https://lasna.reactscan.net/tx/0x51f23ac799e83c3a90257f904db7a324cd3d2a25dce9013acce0e8006c8050a4)。最终计数为 3，剩余次数为 0，订阅已移除。部署和费用处理过程见 [Transfer 监控笔记](notes/sepolia-transfer-monitor.md)。

私钥和 RPC 凭证放在本地 `.env` 文件中，不提交到仓库。





