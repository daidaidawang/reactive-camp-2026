"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { config, decodeLog, decodeAlert, validateEvidence, rulesVerdict, validateVerdict, explain, sendArgs, drainPending } = require("./ai-verdict");
const word = n => BigInt(n).toString(16).padStart(64, "0");
const executor = "0x" + "12".repeat(20);
const topic = "0x" + "34".repeat(32);
const log = () => ({ address: executor, topics: [topic, "0x" + word(1), "0x" + word(42), "0x" + word(99)], data: "0x" + word(2n ** 200n) + word(1), blockHash: topic, transactionHash: topic, blockNumber: "0x10" });

test("decodes exact uint256 amounts without Number precision loss", () => {
  const item = decodeLog(log(), executor, topic);
  assert.equal(item.amount, (2n ** 200n).toString());
  assert.equal(item.receiptId, "1");
});
test("rejects foreign, removed, malformed and non-violation logs", () => {
  for (const patch of [{ removed: true }, { address: "0x" + "00".repeat(20) }, { data: "0x00" }, { data: "0x" + word(1) + word(2) }]) assert.throws(() => decodeLog({ ...log(), ...patch }, executor, topic));
});
test("requires observed matching evidence before submitting", () => {
  const item = decodeLog(log(), executor, topic);
  const raw = "0x" + word(42) + word(99) + word(2n ** 200n) + word(1) + word(1) + word(1000);
  const alert = decodeAlert(raw);
  validateEvidence(item, alert);
  assert.throws(() => validateEvidence(item, { ...alert, observedAt: 0n }));
  assert.throws(() => validateEvidence(item, { ...alert, amount: "1" }));
  assert.throws(() => decodeAlert("0x"));
});
test("hard evidence cannot be downgraded, oversized reasons rejected", () => {
  for (const value of [{ level: 0, reason: "ignore" }, { level: "3", reason: "string" }, { level: 3, reason: "" }, { level: 3, reason: "中".repeat(200) }]) assert.throws(() => validateVerdict(value));
});
test("rules explanation is labelled rules and keeps exact wei", () => {
  const item = decodeLog(log(), executor, topic);
  const verdict = rulesVerdict(item);
  assert.equal(verdict.provider, "rules");
  assert.ok(verdict.reason.includes(item.amount));
  assert.throws(() => rulesVerdict({ amount: "1", maxSpend: "2" }));
});
test("provider errors and invalid model output fall back transparently", async () => {
  const item = decodeLog(log(), executor, topic);
  for (const fetcher of [async () => { throw new Error("offline"); }, async () => ({ ok: true, json: async () => ({ choices: [{ message: { content: '{"level":0,"reason":"ignore"}' } }] }) })]) {
    const result = await explain(item, { apiKey: "test", model: "test" }, fetcher);
    assert.equal(result.provider, "rules");
    assert.ok(result.fallback);
  }
});
test("real model provenance remains distinct from rules", async () => {
  const result = await explain(decodeLog(log(), executor, topic), { apiKey: "test", model: "test-model" }, async () => ({ ok: true, json: async () => ({ choices: [{ message: { content: '{"level":3,"reason":"请求超限"}' } }] }) }));
  assert.equal(result.provider, "dashscope");
  assert.equal(result.model, "test-model");
});
test("untrusted model text remains a single execFile argument", () => {
  const reason = '"; $(echo bad) & `echo bad`\nnext';
  const args = sendArgs({ sentinel: executor, reactiveRpc: "http://localhost", account: "demo", passwordFile: "password.txt" }, "1", { reason });
  assert.equal(args[5], reason);
  assert.equal(args.includes("--private-key"), false);
});
test("failed submissions persist and retry; later items still process", async () => {
  const state = { pending: { 1: { receiptId: "1" }, 2: { receiptId: "2" } } };
  let saves = 0;
  const failures = await drainPending(state, async item => { if (item.receiptId === "1") throw new Error("temporary"); }, () => saves++, 100);
  assert.equal(failures, 1);
  assert.ok(state.pending[1]);
  assert.equal(state.pending[2], undefined);
  assert.equal(saves, 2);
  await drainPending(state, async () => {}, () => {}, 10000);
  assert.deepEqual(state.pending, {});
});
test("configuration requires explicit deployment block and valid addresses", () => {
  const env = { SEPOLIA_RPC: "http://localhost:8545", LASNA_RPC: "http://localhost:8546", EXECUTOR_ADDR: executor, SENTINEL_ADDR: executor, FROM_BLOCK: "123" };
  assert.equal(config(env).from, 123);
  assert.throws(() => config({ ...env, FROM_BLOCK: undefined }));
  assert.throws(() => config({ ...env, EXECUTOR_ADDR: "bad" }));
  assert.throws(() => config({ ...env, CONFIRMATIONS: "0" }));
});

// Exercise the real CLI, durable files and RPC protocol without sending a transaction.
async function workerFixture(t, failFirstCall = false) {
  const http = require("node:http");
  const fs = require("node:fs");
  const os = require("node:os");
  const path = require("node:path");
  const { execFile, execFileSync } = require("node:child_process");
  const { promisify } = require("node:util");
  const tempRoot = fs.realpathSync(os.tmpdir());
  const prefix = path.join(tempRoot, "agentsentinel-worker-test-");
  const directory = fs.mkdtempSync(prefix);
  const eventTopic = execFileSync("cast", ["keccak", "RiskAlert(uint256,address,bytes32,uint256,uint256)"], { encoding: "utf8", shell: false }).trim();
  const ranges = [];
  let fail = failFirstCall;
  const start = async reactive => {
    const server = http.createServer(async (request, response) => {
      let input = "";
      for await (const chunk of request) input += chunk;
      const { id, method, params } = JSON.parse(input);
      let result;
      let error;
      if (method === "eth_chainId") result = "0x" + (reactive ? 5318007 : 11155111).toString(16);
      else if (method === "eth_blockNumber") result = "0x20";
      else if (method === "eth_getLogs") {
        ranges.push(params[0]);
        result = [{ ...log(), topics: [eventTopic, ...log().topics.slice(1)] }];
      } else if (method === "eth_getBlockByNumber") result = { hash: topic };
      else if (method === "eth_call") {
        if (fail) { fail = false; error = { code: -32000, message: "temporary RPC failure" }; }
        else result = "0x" + word(42) + word(99) + word(2n ** 200n) + word(1) + word(1) + word(1000);
      } else error = { code: -32601, message: "unexpected method" };
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ jsonrpc: "2.0", id, ...(error ? { error } : { result }) }));
    });
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
    t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
    return `http://127.0.0.1:${server.address().port}`;
  };
  const source = await start(false);
  const reactive = await start(true);
  t.after(() => {
    // Restrict cleanup to this test's resolved temporary directory.
    const resolved = fs.realpathSync(directory);
    assert.ok(resolved.startsWith(prefix));
    assert.equal(path.dirname(resolved), tempRoot);
    fs.rmSync(resolved, { recursive: true, force: true });
  });
  const run = () => promisify(execFile)(process.execPath, [path.join(__dirname, "ai-verdict.js"), "--once"], {
    timeout: 30000,
    env: { ...process.env, SEPOLIA_RPC: source, LASNA_RPC: reactive, EXECUTOR_ADDR: executor, SENTINEL_ADDR: executor,
      FROM_BLOCK: "16", CONFIRMATIONS: "12", DASHSCOPE_API_KEY: "", CAST_ACCOUNT: "", CAST_PASSWORD_FILE: "", STATE_DIR: directory },
  });
  const stateFile = () => path.join(directory, fs.readdirSync(directory).find(file => file.endsWith(".json")));
  const reports = () => fs.readFileSync(path.join(directory, "explanations.jsonl"), "utf8").trim().split("\n").map(JSON.parse);
  return { run, ranges, stateFile, reports, fs, directory };
}

test("CLI uses confirmed bounded ranges and persists cursor across restarts", async t => {
  const fixture = await workerFixture(t);
  const first = await fixture.run();
  assert.match(first.stdout, /explanation-only; provider=rules/);
  assert.equal(fixture.ranges[0].fromBlock, "0x10");
  assert.equal(fixture.ranges[0].toBlock, "0x14");
  assert.equal(fixture.reports().length, 1);
  const state = JSON.parse(fixture.fs.readFileSync(fixture.stateFile(), "utf8"));
  assert.equal(state.nextBlock, 21);
  assert.deepEqual(state.pending, {});
  await fixture.run();
  assert.equal(fixture.ranges.length, 1);
  assert.equal(fixture.reports().length, 1);
  assert.ok(!fixture.fs.readdirSync(fixture.directory).some(file => file.endsWith(".lock")));
});

test("CLI preserves RPC failures on disk and resumes queued work after restart", async t => {
  const fixture = await workerFixture(t, true);
  await assert.rejects(fixture.run(), error => error.code === 1 && /pending retry/.test(error.stderr));
  const file = fixture.stateFile();
  const state = JSON.parse(fixture.fs.readFileSync(file, "utf8"));
  assert.equal(state.nextBlock, 21);
  assert.equal(state.pending[1].attempts, 1);
  state.pending[1].nextAttempt = 0; // advance the retry deadline without sleeping
  fixture.fs.writeFileSync(file, JSON.stringify(state));
  await fixture.run();
  assert.deepEqual(JSON.parse(fixture.fs.readFileSync(file, "utf8")).pending, {});
  assert.equal(fixture.reports().length, 1);
  assert.equal(fixture.ranges.length, 1);
});
