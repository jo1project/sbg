// 自動化測試共用工具:用 WebSocket 直接連伺服器、模擬玩家。
//
// 伺服器:有設 SERVER_URL 就連那台(必須用 SBG_DEBUG_COMMANDS=1 啟動,部分測試要用除錯指令);
// 沒設就自己在隨機埠號起一台(開除錯指令、用暫存資料庫,不會碰到 data.sqlite),測完關掉。
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";

const SERVER_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- 結果統計 ----------
let failures = 0;
export function check(cond, label) {
  console.log(`${cond ? "PASS" : "FAIL"}  ${label}`);
  if (!cond) failures++;
  return cond;
}
export function finish(name) {
  console.log(failures === 0 ? `\n[${name}] 全部通過` : `\n[${name}] ${failures} 項失敗`);
  return failures === 0;
}

// ---------- 伺服器 ----------
export async function startServer() {
  if (process.env.SERVER_URL) return { url: process.env.SERVER_URL, stop: async () => {} };
  const port = 20000 + Math.floor(Math.random() * 20000);
  const tmp = mkdtempSync(path.join(os.tmpdir(), "sbg-test-"));
  const proc = spawn(process.execPath, ["src/server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      HOST: "127.0.0.1",
      SBG_DEBUG_COMMANDS: "1",
      NODE_ENV: "test",
      DB_PATH: path.join(tmp, "test.sqlite"),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let log = "";
  proc.stdout.on("data", (d) => (log += d));
  proc.stderr.on("data", (d) => (log += d));
  const url = `ws://127.0.0.1:${port}`;
  for (let i = 0; i < 100; i++) {
    try {
      const ws = await openSocket(url);
      ws.close();
      break;
    } catch {
      await sleep(100);
      if (i === 99) throw new Error(`伺服器沒起來:\n${log}`);
    }
  }
  return {
    url,
    log: () => log,
    stop: async () => {
      proc.kill();
      await sleep(200);
      try {
        rmSync(tmp, { recursive: true, force: true });
      } catch {
        // Windows 上 sqlite 檔可能還被鎖住,暫存資料夾留著也無妨
      }
    },
  };
}

function openSocket(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once("open", () => resolve(ws));
    ws.once("error", reject);
  });
}

// ---------- 模擬玩家 ----------
// 跟 Flutter client 一樣每秒 ping(伺服器 3 秒沒收到訊息就當斷線)
export class TestClient {
  constructor(url, name) {
    this.url = url;
    this.name = name;
    this.msgs = [];
    this.playerId = null;
  }

  async connect({ playerId = null, ping = true } = {}) {
    this.ws = await openSocket(this.url);
    this.ws.on("message", (raw) => this.msgs.push(JSON.parse(raw.toString())));
    if (ping) this.startPing();
    this.send({ type: "identify", deviceInfo: `test:${this.name}`, ...(playerId ? { playerId } : {}) });
    const idm = await this.waitFor((m) => m.type === "identified", 3000);
    if (!idm) throw new Error(`${this.name} identify 沒回應`);
    this.playerId = idm.playerId;
    this.identified = idm;
    return idm;
  }

  startPing() {
    this.stopPing();
    this.pingTimer = setInterval(() => this.send({ type: "ping", clientTime: Date.now() }), 1000);
  }
  stopPing() {
    clearInterval(this.pingTimer);
  }

  send(o) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(o));
  }

  // 模擬斷線/切背景:直接關掉連線,不送 leave_room
  drop() {
    this.stopPing();
    this.ws.terminate();
  }

  // 用同一個 playerId 重新連線
  async reconnect() {
    const since = this.msgs.length;
    this.ws = await openSocket(this.url);
    this.ws.on("message", (raw) => this.msgs.push(JSON.parse(raw.toString())));
    this.startPing();
    this.send({ type: "identify", deviceInfo: `test:${this.name}`, playerId: this.playerId });
    return this.waitFor((m) => m.type === "identified", 3000, since);
  }

  mark() {
    return this.msgs.length;
  }

  async waitFor(pred, ms = 3000, since = 0) {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      const m = this.msgs.slice(since).find(pred);
      if (m) return m;
      await sleep(10);
    }
    return null;
  }

  close() {
    this.stopPing();
    try {
      this.ws?.close();
    } catch {
      // 已經關了
    }
  }
}

// 兩位玩家同時排隊 -> 互相配對。回傳雙方各自收到的地圖與食物
export async function matchPair(url) {
  const a = new TestClient(url, "A");
  const b = new TestClient(url, "B");
  await a.connect();
  await b.connect();
  return rematch(a, b);
}

export async function rematch(a, b) {
  const sa = a.mark();
  const sb = b.mark();
  a.send({ type: "join_queue" });
  b.send({ type: "join_queue" });
  const ma = await a.waitFor((m) => m.type === "match_found", 3000, sa);
  const mb = await b.waitFor((m) => m.type === "match_found", 3000, sb);
  if (!ma || !mb || ma.opponentId !== b.playerId) throw new Error("A、B 沒有互相配對到");
  for (const [c, s] of [[a, sa], [b, sb]]) {
    c.map = (await c.waitFor((m) => m.type === "obstacle_layout", 1000, s)).map;
    c.foods = c.msgs.slice(s).filter((m) => m.type === "food_spawned");
    c.roomId = (c === a ? ma : mb).roomId;
  }
  return { a, b };
}

// ---------- 除錯連線(伺服器要開 SBG_DEBUG_COMMANDS=1) ----------
export async function debugClient(url) {
  const ws = await openSocket(url);
  const msgs = [];
  ws.on("message", (raw) => msgs.push(JSON.parse(raw.toString())));
  return {
    async cmd(o) {
      const since = msgs.length;
      ws.send(JSON.stringify(o));
      const t0 = Date.now();
      while (Date.now() - t0 < 2000) {
        const m = msgs.slice(since).find((x) => x.command === o.type);
        if (m) {
          if (m.type === "debug_error") throw new Error(`${o.type}: ${m.message}`);
          return m.detail;
        }
        await sleep(10);
      }
      throw new Error(`${o.type} 沒有回應(伺服器有用 SBG_DEBUG_COMMANDS=1 啟動嗎?)`);
    },
    close: () => ws.close(),
  };
}

// 地圖工具
export function isFloor(map, x, y) {
  return [...(map.rooms || []), ...(map.corridors || [])].some((z) => x >= z.x0 && x <= z.x1 && y >= z.y0 && y <= z.y1);
}

// 單獨執行一個測試:起伺服器 -> 跑 -> 關伺服器 -> exit code
export async function runStandalone(name, fn) {
  const server = await startServer();
  let ok = false;
  try {
    await fn(server.url);
    ok = finish(name);
  } catch (err) {
    console.log(`FAIL  例外:${err.stack || err}`);
    finish(name);
  } finally {
    await server.stop();
  }
  process.exitCode = ok ? 0 : 1;
  return ok;
}
