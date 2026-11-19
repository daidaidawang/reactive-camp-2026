# Reactive Network 基础

## Reactive 解决的问题

普通合约不会主动运行，必须由交易触发。链上止损、套利或定时任务通常要配一个链下机器人，持续监听事件并发送交易。

Reactive 合约可以订阅其他链的事件。符合条件时，网络调用合约的 `react()`；合约需要在另一条链执行操作时，再请求跨链 callback。

```text
源链事件 → Reactive 合约 react() → 目标链 callback
```

因此，简单的事件监听和触发逻辑不需要自己维护常驻机器人。复杂计算或链下数据仍需要外部服务或预言机。

## 本地环境

- Git 2.54
- Node 22.22
- Foundry 1.7.1

在 Sepolia 向 Reactive faucet 转入 0.01 ETH，约一分钟后 Lasna 收到 1.05 lREACT。faucet 地址：`0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`。

## 适用场景

- 链上事件触发的自动操作
- 定时巡检和定投
- 跨链合约联动

逻辑依赖私有数据或复杂链下计算时，需要额外的数据源。每次 Reactive 执行和目标链 callback 都会产生费用。

记录日期：2026-11-16


