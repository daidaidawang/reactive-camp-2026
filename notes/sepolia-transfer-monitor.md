# Sepolia ERC-20 Transfer 监控

参考 Reactive Network 的 [Xfers 示例](https://github.com/Reactive-Network/reactive-smart-contract-demos/blob/omni/src/micro-demos/Xfers.sol)，在 Lasna 部署监控合约，订阅 Sepolia 上的 ERC-20 `Transfer` 事件。

## 合约

- 监控合约：[CampXfersMonitor](https://lasna.reactscan.net/address/0x1E3b32cB9F31868212b9938c57d76d3fC2Af12dd)
- 测试代币 CTT：`0xeD2f9C6Be45d8287515428B5FA60E0f2FcEb2e51`
- 源码：[CampXfersMonitor.sol](../reactive-monitor/src/CampXfersMonitor.sol)、[MockERC20.sol](../reactive-monitor/src/MockERC20.sol)
- 部署交易：[Reactscan](https://lasna.reactscan.net/tx/0x12154d80c18dd2e2b809cd2fea45b69f270b2060b246744df9e3ee51a8ab393e)

## 逻辑

构造函数订阅 Sepolia 上 CTT 的 `Transfer`。`topic0` 固定为 Transfer 事件签名，`topic1` 到 `topic3` 使用 `REACTIVE_IGNORE`。

`react()` 使用 `onlySystem` 限制调用方。单笔金额小于 5 CTT 时直接 `return`；达到阈值后记录 `Matched` 事件。命中三次后调用 `unsubscribe()`，参数与订阅时保持一致。

## 验证

1、2 CTT 的转账低于阈值，不计数；10、7、5 CTT 的转账触发计数。

第 3 次命中的 [Sepolia 转账](https://sepolia.etherscan.io/tx/0x26037056d061a72af9855112e9dd1c5bff7bbda0f056d8e12ce3ddd3639a3827) 对应 [Lasna `react()` 交易](https://lasna.reactscan.net/tx/0x51f23ac799e83c3a90257f904db7a324cd3d2a25dce9013acce0e8006c8050a4)，`Matched` 事件中的计数为 3。之前计数为 2 的交易在 [Reactscan](https://lasna.reactscan.net/tx/0x43acedd363cca1d8c225f31020697323e575d5d2be9cbc044592d7988939515b)。

完成后读取到 `_matchedCount() = 3`、`_limit() = 0`、SYSTEM `debt() = 0`。当前 filter index 中已没有 CTT 的 Transfer 订阅，自动退订完成。

## 欠费处理

合约最初部署时充值 0.05 lREACT。运行后查到 debt 为 0.0136774 lREACT，合约余额约 0.0084838 lREACT，因此后续事件没有触发 `react()`。

先通过 Sepolia faucet 的 `request(address)` 给监控合约补入 10.5 lREACT，交易记录在 [Sepolia Etherscan](https://sepolia.etherscan.io/tx/0x08b05f7e4fe77b48dd4b80c97de1b6a63a4ec564f72775ba68c1557b2d7f7ed7)。这只增加了合约余额，debt 仍未清偿。之后向 Lasna SYSTEM 调用 `depositTo(address)` 并存入 0.1 lREACT，[交易记录](https://lasna.reactscan.net/tx/0x979a98344a7d889d49ee9a75c89d43c2a00559201918a0d1b25d50fc73755704)。这笔存款先结清 debt，余款进入 reserves。

清偿后重新发出 5 CTT 转账，`react()` 成功执行并达到次数上限。欠费期间发出的那笔转账没有被处理。

## 复现时注意

- `@reactive/` remapping 指向 `lib/reactive-lib-omni/`，不要指到 `src/`。
- 新版 Foundry 的 `forge create` 要带 `--broadcast` 才会广播交易。
- `_limit` 是 public 状态变量，对应 getter 为 `_limit()`。
- `unsubscribe()` 的六个过滤参数必须与 `subscribe()` 完全相同。
- 过滤事件用 `return`，不要用 `revert`。
- 有 debt 时用 SYSTEM `depositTo(address)` 恢复合约；直接给合约转账不会自动还债。

记录日期：2026-11-18


