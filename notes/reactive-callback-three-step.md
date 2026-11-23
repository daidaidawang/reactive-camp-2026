# Reactive 跨链回调三步走

## 知识点

Reactive 合约订阅源链事件

跨链 Callback

Callback 权限校验

## 思路

先在 Sepolia 部署 `CampOrigin`，用 `ping(500)` 发出 `Ping(address,uint256)` 事件。

Lasna 上的 `CampReactive` 订阅这个事件。收到事件后读取 `value`，小于 100 就不请求回调；这次传入的是 500，所以满足条件。

满足条件后，`CampReactive` 请求 Sepolia 上的 Callback Proxy 调用 `CampCallback.onEvent()`。Callback 把收到的值记下来，`count` 加一。

Callback 合约继承 `AbstractCallback`，回调函数第一个参数是 `address`。`onlyServiceProvider` 检查调用方是不是 Callback Proxy，`onlyCallbackSender` 检查回调是不是来自指定的 Reactive 合约。

如果不用 Reactive，就要自己运行一个机器人，不停轮询 Sepolia 的事件，满足条件后再发交易。Reactive 帮忙处理事件订阅和触发；合约仍要有执行费用，订阅地址、回调地址和权限也要配对。跨链回调不是源链交易里同步完成的，还要等 Reactive 网络和目标链处理。

## 这次跑通的链路

```text
Sepolia：CampOrigin.ping(500) 发出 Ping
    → Lasna：CampReactive.react() 收到事件，value=500，剩余次数从 5 变成 4
    → Sepolia：Callback Proxy 调用 CampCallback.onEvent()，count 从 0 变成 1
```

部署的合约：

- 源链事件合约：`0xd57ce1a19b61e85f2960057afbcf62b8ad7cfb7a`
- Lasna Reactive 合约：`0x3706f9690c15d8001c7ffec25cd4f4e6f9b168bc`
- Sepolia Callback 合约：`0xCC388F107162FebF744dAF0Feaf6405a340aeC0b`
- Sepolia Callback Proxy：`0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`

## 交易记录

源链 `Ping(500)` 事件：[Sepolia 交易](https://sepolia.etherscan.io/tx/0xa76ece4dce856b1be94d7978b1413416192a908fbe91ffb0cfcb963954b73997)

![源链 Ping 事件](https://daidaidawang.oss-cn-beijing.aliyuncs.com/D:%5Ctypora_img/image-20261120174108448.png)

Lasna 上的 `react()`：[Reactscan 交易](https://lasna.reactscan.net/tx/0x00c072c3a3966e0965c9c168e72d6f66fd4b65ff9c60d9b036f54ef3a7d04082)

![Lasna react 交易](https://daidaidawang.oss-cn-beijing.aliyuncs.com/D:%5Ctypora_img/image-20261120174307771.png)

目标链 Callback 执行：[Sepolia 交易](https://sepolia.etherscan.io/tx/0xb5f0ce08692130235aa5e6c2b0bbf013aa38cb58aada7e7e1f55840b24d09d41)

![目标链 Callback 交易](https://daidaidawang.oss-cn-beijing.aliyuncs.com/D:%5Ctypora_img/image-20261120174529012.png)

Reactive 记录的源链交易哈希和第一笔交易一致，`lastReactBlock` 已更新，剩余次数是 4。Callback 的 `count` 是 1，`lastValue` 是 500。

## 失败实验

用部署钱包直接调用 `CampCallback.onEvent()`，交易回滚：[Sepolia 失败交易](https://sepolia.etherscan.io/tx/0x926b8bff663e2156d7d796475e00708588e9b7c09c1dc6e12b7370f3c5a404c7)。Trace 返回 `NotAuthorized`。

直接调用时，`msg.sender` 是钱包地址，不是 Callback Proxy，所以 `onlyServiceProvider` 拒绝了这次调用。正常回调还要通过 `onlyCallbackSender` 检查，确认 Reactive 地址正确。

![钱包直接调用失败](https://daidaidawang.oss-cn-beijing.aliyuncs.com/D:%5Ctypora_img/image-20261120174021711.png)

## 收获

源链发出的事件可以触发 Lasna 上的 `react()`，再由 Callback Proxy 把调用送到目标链。

`react()` 和目标链 Callback 是两笔不同链上的交易。Callback 只接受 Proxy 转发、且 Reactive 地址正确的调用。

日期：2026-11-19
