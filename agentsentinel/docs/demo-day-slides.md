# AgentSentinel Demo Day 幻灯片

记录日期：2026-11-25。

[可编辑的 8 页 PPT](../submission/AgentSentinel-Demo-Day.pptx)已经生成，讲者备注含逐页讲词；[2 分 08 秒视频](../submission/AgentSentinel-3min-Demo.mp4)含中文配音和实际命令截图。PPT 的第 5 页是[三段跨链回执截图](../submission/screenshots/command-crosschain.png)，第 6 页是[最终状态读回](../submission/screenshots/command-state.png)，第 7 页是[`forge test` 通过画面](../submission/screenshots/command-tests.png)。

演示顺序：限定固定商户、单笔与累计上限、按回执去重；Sepolia 源链拒付并发 `RiskAlert(2)`；Lasna 观察并请求回调；Sepolia 目标端复核回执，完成撤权、罚没和结算；最后说明 AI 只提供解释、失败恢复和原型范围。实际地址、三笔交易和全部部署截图见[证据清单](../submission/README.md)。

本次演示是 rules 模式，没有真实 LLM 调用。视频是合成中文配音的幻灯片与真实截图演示，不是实时录屏。测试网合约没有第三方审计；演示账户兼任项目方、Agent 和商户。
