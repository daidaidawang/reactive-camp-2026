#!/usr/bin/env node
/**
 * AgentSentinel · AI 判读服务（链下）
 *
 * 运行时管线（赛道 3 的 AI 参与证明）：
 *   Sepolia RiskAlert 事件 → 本服务读取事件与授权上下文
 *   → LLM 分类风险并生成结构化处置建议（JSON verdict）
 *   → 提交到 Lasna AgentSentinel.submitVerdict()
 *   → Sentinel 规则引擎校验（AI 不能突破链上证据）→ 跨链回调处置
 *
 * LLM 接入：DASHSCOPE_API_KEY 有值时调用通义千问（OpenAI 兼容接口）；
 * 无 key 时使用本地确定性模拟（同一 JSON schema），演示"拔 key 降级"。
 *
 * 用法：node scripts/ai-verdict.js [--once]
 */

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

// ---------- 配置 ----------
const envFile = fs.readFileSync(path.join(__dirname, "..", ".env"), "utf8");
const env = {};
for (const line of envFile.split(/\r?\n/)) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m && !process.env[m[1]]) env[m[1]] = m[2].trim();
}
const CFG = {
  privateKey: process.env.PRIVATE_KEY || env.PRIVATE_KEY,
  sepoliaRpc: process.env.SEPOLIA_RPC || env.SEPOLIA_RPC,
  lasnaRpc: process.env.LASNA_RPC || env.LASNA_RPC,
  sentinel: process.env.SENTINEL_ADDR || env.SENTINEL_ADDR,
  executor: process.env.EXECUTOR_ADDR || env.EXECUTOR_ADDR,
  dashscopeKey: process.env.DASHSCOPE_API_KEY || env.DASHSCOPE_API_KEY || "",
  model: process.env.DASHSCOPE_MODEL || env.DASHSCOPE_MODEL || "qwen-plus",
  pollMs: parseInt(process.env.POLL_INTERVAL_MS || env.POLL_INTERVAL_MS || "15000", 10),
};

const RISK_TOPIC_0 = keccakEvent("RiskAlert(uint256,address,bytes32,uint256,uint256)");
const processed = new Set(); // 已裁决的 receiptId
const startBlock = process.env.FROM_BLOCK
  ? parseInt(process.env.FROM_BLOCK, 10)
  : Number(execSync(`cast block-number -r ${CFG.sepoliaRpc}`).toString().trim()) - 300;

function keccakEvent(sig) {
  return execSync(`cast keccak "${sig}"`).toString().trim();
}

function cast(args, silent = false) {
  return execSync(`cast ${args}`, { encoding: "utf8", stdio: silent ? ["ignore", "pipe", "pipe"] : undefined }).trim();
}

// ---------- 第 1 步：轮询风险事件 ----------
function fetchAlerts() {
  const raw = cast(
    `logs --from-block ${startBlock} --to-block latest --address ${CFG.executor} ` +
    `"RiskAlert(uint256,address,bytes32,uint256,uint256)" --rpc-url ${CFG.sepoliaRpc} --json`,
    true
  );
  const logs = JSON.parse(raw || "[]");
  return logs.map((l) => ({
    receiptId: BigInt(l.topics[1]).toString(),
    agent: "0x" + l.topics[2].slice(-40),
    capId: l.topics[3],
    amount: BigInt("0x" + l.data.slice(2, 66)).toString(),
    maxSpend: BigInt("0x" + l.data.slice(66, 130)).toString(),
    txHash: l.transactionHash,
    blockNumber: l.blockNumber,
  }));
}

// ---------- 第 2 步：AI 判读（真实 LLM 或本地模拟，同一 JSON 契约） ----------
function mockLLM(ctx) {
  // 确定性模拟：与真实 LLM 输出完全相同的结构化契约
  const amountEth = Number(ctx.amount) / 1e18;
  const capEth = Number(ctx.maxSpend) / 1e18;
  const ratio = (amountEth / capEth).toFixed(2);
  return {
    level: 3,
    reason: `[模拟LLM] Agent ${ctx.agent.slice(0, 10)}... 在能力 ${ctx.capId.slice(0, 10)}... 下请求 ${amountEth} ETH，` +
      `超过授权额度 ${capEth} ETH（${ratio} 倍）。构成财务越界证据，建议 L3 终止处置：撤销授权并罚没保证金。`,
    provider: "mock",
  };
}

async function realLLM(ctx) {
  const prompt = `你是链上 AI 智能体风控判读引擎。根据以下链上证据输出 JSON 判读（不要输出其他文字）：
{"level": <0-3>, "reason": "<中文，50字内>"}

等级语义：0=仅建议 1=降级限流 2=冻结(可恢复) 3=终止(撤权+罚没)。

链上证据（由 SentinelExecutor 合约计算，不可伪造）：
- 事件: RiskAlert（财务越界证据）
- Agent: ${ctx.agent}
- 能力: ${ctx.capId}
- 请求金额: ${Number(ctx.amount) / 1e18} ETH
- 授权上限: ${Number(ctx.maxSpend) / 1e18} ETH
- 证据交易: ${ctx.txHash}

已知规则：财务越界（请求金额超过授权上限）必须判 L3。`;

  const res = await fetch("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${CFG.dashscopeKey}` },
    body: JSON.stringify({
      model: CFG.model,
      messages: [{ role: "user", content: prompt }],
      temperature: 0.1,
    }),
  });
  const data = await res.json();
  const content = data.choices?.[0]?.message?.content ?? "";
  const jsonMatch = content.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("LLM 输出无法解析: " + content);
  const parsed = JSON.parse(jsonMatch[0]);
  parsed.provider = `dashscope:${CFG.model}`;
  return parsed;
}

// ---------- 第 3 步：verdict 上链（提交给规则引擎校验） ----------
function submitVerdict(receiptId, level, reason) {
  const safeReason = reason.replace(/["`\\$]/g, "'").slice(0, 150);
  try {
    const hash = cast(
      `send ${CFG.sentinel} "submitVerdict(uint256,uint256,string)" ${receiptId} ${level} "${safeReason}" ` +
      `--rpc-url ${CFG.lasnaRpc} --private-key ${CFG.privateKey}`,
      true
    );
    const m = hash.match(/transactionHash\s+(0x[0-9a-fA-F]+)/);
    return m ? m[1] : hash.split(/\r?\n/)[0];
  } catch (e) {
    // cast 失败时打印真实 stderr，便于排查
    const errText = (e.stderr || e.stdout || e.message || "").split(/\r?\n/).filter(Boolean).slice(-3).join(" | ");
    throw new Error("submitVerdict 失败: " + errText.slice(0, 300));
  }
}

// ---------- 主循环 ----------
async function judgeOne(a) {
  // 先查链上状态：告警未投递到 Lasna → 稍后重试；已裁决 → 跳过
  let chainState = "";
  try {
    chainState = cast(
      `call ${CFG.sentinel} "alerts(uint256)(address,bytes32,uint256,uint256,bool,uint256)" ${a.receiptId} --rpc-url ${CFG.lasnaRpc}`,
      true
    );
  } catch { /* Sentinel 侧查询失败则照常走判读 */ }
  if (chainState) {
    const fields = chainState.split(/\r?\n/).map((s) => s.trim());
    const observedAt = fields[5] || "0";
    const open = fields[4] || "false";
    if (observedAt === "0" || observedAt.startsWith("0x0000000000000000000000000000000000000000000000000000000000000000")) {
      console.log(`┌─ 告警 #${a.receiptId} 尚未投递到 Lasna，稍后重试`);
      processed.delete(a.receiptId);
      return;
    }
    if (open === "false") {
      console.log(`┌─ 告警 #${a.receiptId} 已在链上裁决，跳过`);
      return;
    }
  }

  console.log(`\n┌─ [${new Date().toLocaleTimeString()}] 发现风险证据 #${a.receiptId}`);
  console.log(`│  agent=${a.agent} 请求=${Number(a.amount) / 1e18} ETH 上限=${Number(a.maxSpend) / 1e18} ETH`);
  console.log(`│  证据交易: ${a.txHash}`);

  const ctx = { agent: a.agent, capId: a.capId, amount: a.amount, maxSpend: a.maxSpend, txHash: a.txHash };
  let verdict;
  try {
    verdict = CFG.dashscopeKey ? await realLLM(ctx) : mockLLM(ctx);
  } catch (e) {
    console.log(`│  ⚠ LLM 调用失败（${e.message}）→ 降级为本地确定性模拟`);
    verdict = mockLLM(ctx);
  }
  console.log(`│  🤖 [${verdict.provider}] 判读: level=${verdict.level}`);
  console.log(`│     ${verdict.reason}`);

  const lasnaTx = submitVerdict(a.receiptId, verdict.level, verdict.reason);
  console.log(`│  ✅ verdict 已提交 Lasna: ${lasnaTx}`);
  console.log(`└─  等待 Sentinel 规则引擎校验 → 跨链回调处置`);
}

async function main() {
  const once = process.argv.includes("--once");
  console.log("═══ AgentSentinel AI 判读服务 ═══");
  console.log(`LLM: ${CFG.dashscopeKey ? "通义千问 " + CFG.model : "本地确定性模拟（未配置 key）"}`);
  console.log(`监听 ${CFG.executor} 的 RiskAlert 事件（from block ${startBlock}）`);

  for (;;) {
    try {
      const alerts = fetchAlerts().filter((a) => !processed.has(a.receiptId));
      for (const a of alerts) {
        processed.add(a.receiptId);
        await judgeOne(a);
      }
    } catch (e) {
      console.error("轮询异常:", e.message?.slice(0, 200));
    }
    if (once) break;
    await new Promise((r) => setTimeout(r, CFG.pollMs));
  }
}

main().catch((e) => {
  console.error("启动失败:", e);
  process.exit(1);
});
