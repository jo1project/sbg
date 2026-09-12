// 數值平衡用的對戰模擬工具(規格文件第10節「數值平衡的原型測試與調整」)。
// 用兩個模擬「玩家」(貪食蛇本地移動邏輯照抄客戶端 collision.dart 的規則)透過真正的
// WebSocket 連上正在跑的伺服器對戰,重複跑多場收集數據(場長、死因、命中率、雪球效應),
// 取代純粹憑感覺猜數值。伺服器邏輯完全不用修改,跟真的手機客戶端走同一套協定。
//
// 用法:
//   node src/server.js &
//   node tools/balance_sim.mjs                # 預設跑15場
//   MATCHES=30 MOVE_TICK_MS=150 node tools/balance_sim.mjs   # 調參數重跑觀察差異
import WebSocket from "ws";
import { CONFIG } from "../src/events.js";

const SERVER_URL = process.env.SERVER_URL || "ws://127.0.0.1:8080";
const MATCHES = Number(process.env.MATCHES) || 15;
const MOVE_TICK_MS = Number(process.env.MOVE_TICK_MS) || 200; // 對應 client GameConfig.moveTickMs
const INITIAL_LEN = 4; // 對應 client GameConfig.initialSnakeLength
const MAP = CONFIG.MAP_SIZE;
const ATTACK_CHANCE_PER_TICK = Number(process.env.ATTACK_CHANCE) || 0.08; // 模擬玩家的出手積極度
const RANDOM_TURN_CHANCE = 0.15; // 模擬人類移動時的隨機雜訊,避免機器人路徑太死板

const DIRS = {
  right: { x: 1, y: 0 },
  left: { x: -1, y: 0 },
  up: { x: 0, y: -1 },
  down: { x: 0, y: 1 },
};
const OPPOSITE = { right: "left", left: "right", up: "down", down: "up" };

function eq(a, b) {
  return a.x === b.x && a.y === b.y;
}

function checkDeath(newHead, body, grow) {
  if (newHead.x < 0 || newHead.x >= MAP || newHead.y < 0 || newHead.y >= MAP) return "wall";
  const toCheck = grow ? body : body.slice(0, -1);
  if (toCheck.some((c) => eq(c, newHead))) return "self";
  return null;
}

class Bot {
  constructor(label) {
    this.label = label;
    this.playerId = null;
    this.opponentId = null;
    this.energy = 0;
    this.dir = "right";
    this.pendingDir = null;
    this.snake = [];
    this.foods = new Map();
    this.growthPending = 0;
    this.pendingOutgoingAttack = false;
    this.alive = true;
    this.attackerByAttackId = new Map();
    this.stats = { attacksSent: 0, attacksLanded: 0, dodgesSuccess: 0, timesHitByDirect: 0, lengthGained: 0 };
  }

  async connect() {
    this.ws = new WebSocket(SERVER_URL);
    await new Promise((resolve, reject) => {
      this.ws.once("open", resolve);
      this.ws.once("error", reject);
    });
    this.ws.on("message", (raw) => this._onMessage(JSON.parse(raw.toString())));
  }

  send(type, payload = {}) {
    this.ws.send(JSON.stringify({ type, ...payload }));
  }

  identify() {
    this.send("identify");
  }

  _onMessage(msg) {
    switch (msg.type) {
      case "identified":
        this.playerId = msg.playerId;
        break;
      case "match_found":
        this.opponentId = msg.opponentId;
        this._startMatch();
        break;
      case "energy_update":
        if (msg.playerId === this.playerId) this.energy = msg.energy;
        break;
      case "food_spawned":
        this.foods.set(msg.foodId, msg.position);
        break;
      case "attack_incoming":
        this.attackerByAttackId.set(msg.attackId, msg.attackerId);
        if (msg.attackerId !== this.playerId) this._maybeDodge(msg.attackId, msg.dodgeWindowMs);
        break;
      case "attack_result": {
        const attackerId = this.attackerByAttackId.get(msg.attackId);
        this.attackerByAttackId.delete(msg.attackId);
        const iAmAttacker = attackerId === this.playerId;
        const iAmDefender = attackerId && !iAmAttacker;
        if (iAmAttacker) {
          this.pendingOutgoingAttack = false;
          if (!msg.dodged) this.stats.attacksLanded++;
        }
        if (!msg.dodged && iAmDefender) {
          if (msg.effectType === "direct_lengthen") {
            this.growthPending += msg.lengthenBy;
            this.stats.timesHitByDirect++;
            this.stats.lengthGained += msg.lengthenBy;
          }
        }
        if (msg.dodged && iAmDefender) this.stats.dodgesSuccess++;
        break;
      }
      case "attack_rejected":
        this.pendingOutgoingAttack = false;
        break;
      case "game_over":
        this.alive = false;
        this._onGameOver?.(msg);
        break;
    }
  }

  _startMatch() {
    const start = { x: Math.floor(MAP / 2), y: Math.floor(MAP / 2) };
    this.snake = Array.from({ length: INITIAL_LEN }, (_, i) => ({ x: start.x - i, y: start.y }));
    this.dir = "right";
    this.moveTimer = setInterval(() => this._tick(), MOVE_TICK_MS);
    this.syncTimer = setInterval(() => {
      if (!this.snake.length) return;
      this.send("snake_position_update", { headPos: this.snake[0], bodyCells: this.snake });
    }, CONFIG.SNAKE_POSITION_SYNC_MS);
  }

  _pickDirection() {
    const candidates = Object.keys(DIRS).filter((d) => d !== OPPOSITE[this.dir]);
    const valid = candidates.filter((d) => !checkDeath({ x: this.snake[0].x + DIRS[d].x, y: this.snake[0].y + DIRS[d].y }, this.snake, this.growthPending > 0));
    const pool = valid.length ? valid : candidates;

    if (Math.random() < RANDOM_TURN_CHANCE || this.foods.size === 0) {
      return pool[Math.floor(Math.random() * pool.length)];
    }
    let best = pool[0];
    let bestDist = Infinity;
    for (const d of pool) {
      const nh = { x: this.snake[0].x + DIRS[d].x, y: this.snake[0].y + DIRS[d].y };
      for (const f of this.foods.values()) {
        const dist = Math.abs(nh.x - f.x) + Math.abs(nh.y - f.y);
        if (dist < bestDist) {
          bestDist = dist;
          best = d;
        }
      }
    }
    return best;
  }

  _tick() {
    if (!this.snake.length) return;
    const nextDir = this._pickDirection();
    this.dir = nextDir;
    const head = this.snake[0];
    const newHead = { x: head.x + DIRS[nextDir].x, y: head.y + DIRS[nextDir].y };
    const grow = this.growthPending > 0;
    const cause = checkDeath(newHead, this.snake, grow);

    if (cause) {
      clearInterval(this.moveTimer);
      clearInterval(this.syncTimer);
      this.send("death_report", { cause, headPos: newHead, bodyCells: this.snake });
      return;
    }

    const nextBody = [newHead, ...this.snake];
    if (!grow) nextBody.pop();
    else this.growthPending--;
    this.snake = nextBody;

    for (const [foodId, pos] of this.foods) {
      if (eq(pos, newHead)) {
        this.foods.delete(foodId);
        this.send("food_eaten_request", { foodId, headPos: newHead });
        break;
      }
    }

    if (!this.pendingOutgoingAttack && this.energy >= 5 && Math.random() < ATTACK_CHANCE_PER_TICK) {
      this.pendingOutgoingAttack = true;
      this.stats.attacksSent++;
      this.send("attack_request", {
        attackType: Math.random() < 0.5 ? "direct" : "random",
        clientTime: Date.now(),
      });
    }
  }

  _maybeDodge(attackId, windowMs) {
    if (Math.random() < 0.2) return; // 模擬20%機率反應不及,完全沒按
    const reactionMs = 80 + Math.random() * 260; // 模擬人類反應時間,可能超出視窗而閃躲失敗
    setTimeout(() => {
      if (!this.alive) return;
      this.send("dodge_attempt", { attackId, clientActionTime: Date.now() });
    }, reactionMs);
  }

  close() {
    clearInterval(this.moveTimer);
    clearInterval(this.syncTimer);
    this.ws.close();
  }
}

async function runOneMatch() {
  const a = new Bot("A");
  const b = new Bot("B");
  await a.connect();
  await b.connect();
  a.identify();
  b.identify();
  await new Promise((r) => setTimeout(r, 100));

  const startedAt = Date.now();
  const result = await new Promise((resolve) => {
    let settled = false;
    const done = (msg) => {
      if (settled) return;
      settled = true;
      resolve(msg);
    };
    a._onGameOver = done;
    b._onGameOver = done;
    a.send("join_queue");
    b.send("join_queue");
  });
  const durationMs = Date.now() - startedAt;

  const stats = {
    durationMs,
    reason: result.reason,
    draw: !!result.draw,
    winnerLabel: result.winnerId === a.playerId ? "A" : result.winnerId === b.playerId ? "B" : null,
    aFinalLen: a.snake.length,
    bFinalLen: b.snake.length,
    a: a.stats,
    b: b.stats,
  };

  a.close();
  b.close();
  return stats;
}

function summarize(runs) {
  const n = runs.length;
  const avg = (f) => runs.reduce((s, r) => s + f(r), 0) / n;
  const reasonCounts = {};
  for (const r of runs) reasonCounts[r.reason] = (reasonCounts[r.reason] || 0) + 1;

  console.log(`\n===== ${n} 場模擬結果 (MOVE_TICK_MS=${MOVE_TICK_MS}, ATTACK_CHANCE=${ATTACK_CHANCE_PER_TICK}) =====`);
  console.log(`平均場長: ${(avg((r) => r.durationMs) / 1000).toFixed(1)} 秒`);
  console.log(`結束原因分布:`, reasonCounts);
  console.log(`平均每場攻擊次數(雙方合計): ${avg((r) => r.a.attacksSent + r.b.attacksSent).toFixed(1)}`);
  console.log(`平均命中率: ${((avg((r) => r.a.attacksLanded + r.b.attacksLanded) / Math.max(1, avg((r) => r.a.attacksSent + r.b.attacksSent))) * 100).toFixed(0)}%`);
  console.log(`平均閃躲成功次數(雙方合計): ${avg((r) => r.a.dodgesSuccess + r.b.dodgesSuccess).toFixed(1)}`);

  // 雪球效應指標:輸家在死前平均被直接攻擊拉長多少格(相對起始長度4),越高代表越容易滾雪球
  const loserLengthGain = runs
    .filter((r) => !r.draw && r.winnerLabel)
    .map((r) => (r.winnerLabel === "A" ? r.b.lengthGained : r.a.lengthGained));
  const avgLoserGain = loserLengthGain.length ? loserLengthGain.reduce((s, v) => s + v, 0) / loserLengthGain.length : 0;
  console.log(`輸家死前平均被直接攻擊拉長: ${avgLoserGain.toFixed(1)} 格(雪球效應指標,越高越明顯)`);
  console.log("");
}

async function main() {
  const runs = [];
  for (let i = 0; i < MATCHES; i++) {
    const r = await runOneMatch();
    runs.push(r);
    console.log(
      `[場 ${i + 1}/${MATCHES}] ${(r.durationMs / 1000).toFixed(1)}s reason=${r.reason} winner=${r.draw ? "平手" : r.winnerLabel}`
    );
  }
  summarize(runs);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
