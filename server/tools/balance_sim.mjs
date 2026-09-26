// 數值平衡用的對戰模擬工具(規格文件第10節「數值平衡的原型測試與調整」)。
// 用兩個模擬「玩家」(貪食蛇本地移動邏輯照抄客戶端 collision.dart 的規則)透過真正的
// WebSocket 連上正在跑的伺服器對戰,重複跑多場收集數據(場長、死因、命中率、雪球效應),
// 取代純粹憑感覺猜數值。伺服器邏輯完全不用修改,跟真的手機客戶端走同一套協定。
//
// 用法:
//   node src/server.js &
//   node tools/balance_sim.mjs                # 預設跑15場
//   MATCHES=30 MOVE_TICK_MS=325 node tools/balance_sim.mjs   # 調參數重跑觀察差異
//   MAP_SET=large node tools/balance_sim.mjs  # identify 帶 mapSets 含 "large"(模擬 Godot),伺服器有大地圖就配大地圖
//   MAPS_DIR=/tmp/maps node src/server.js     # 伺服器用別的地圖資料夾(例如 gen_large_map.mjs 產生的候選)
//
// 機器人:照伺服器送來的地圖(obstacle_layout)走,用 BFS 繞牆找最近的寶石,15% 機率隨便轉彎(只挑下一步不會死的方向),
// 不做更遠的預判——會像人一樣把自己困住。死亡判定照 client:撞牆(房間/走廊外)、撞障礙物、撞自己。
// 效果(暫停/加速/失明)不模擬,只模擬直接攻擊的變長。
import WebSocket from "ws";

const SERVER_URL = process.env.SERVER_URL || "ws://127.0.0.1:8080";
const MATCHES = Number(process.env.MATCHES) || 15;
const CONCURRENCY = Number(process.env.CONCURRENCY) || 5; // 同時跑幾場
const MOVE_TICK_MS = Number(process.env.MOVE_TICK_MS) || 350; // Godot snake_train.gd step_time(Flutter 是 325)
const MAX_MATCH_MS = Number(process.env.MAX_MATCH_MS) || 600000; // 超過就當平手結束(避免機器人永遠不死)
const MAP_SETS = process.env.MAP_SET === "large" ? ["classic", "large"] : undefined;
const COUNTDOWN_MS = 3000; // 同 client:收到 match_found 後倒數 3 秒才開始動
const INITIAL_LEN = 4; // 對應 client GameConfig.initialSnakeLength
const SNAKE_POSITION_SYNC_MS = 1000;
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

const key = (p) => `${p.x},${p.y}`;

// 地圖 -> { floor: Set, blocked: Set }(同 client:房間/走廊外是牆,障礙物 big 佔兩格)
function parseMap(map) {
  const floor = new Set();
  for (const z of [...map.rooms, ...map.corridors]) {
    for (let x = z.x0; x <= z.x1; x++) for (let y = z.y0; y <= z.y1; y++) floor.add(`${x},${y}`);
  }
  const blocked = new Set();
  for (const o of map.obstacles) {
    blocked.add(`${o.x},${o.y}`);
    if (o.size === "big") blocked.add(`${o.x + 1},${o.y}`);
  }
  return { floor, blocked };
}

function checkDeath(grid, newHead, body, grow) {
  if (!grid.floor.has(key(newHead))) return "wall";
  if (grid.blocked.has(key(newHead))) return "obstacle";
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
    this.snake = [];
    this.foods = new Map();
    this.growthPending = 0;
    this.pendingOutgoingAttack = false;
    this.alive = true;
    this.attackerByAttackId = new Map();
    this.stats = { attacksSent: 0, attacksLanded: 0, dodgesSuccess: 0, timesHitByDirect: 0, lengthGained: 0, gems: 0, cause: null };
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
    if (this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify({ type, ...payload }));
  }

  identify() {
    this.send("identify", MAP_SETS ? { mapSets: MAP_SETS } : {});
  }

  _onMessage(msg) {
    switch (msg.type) {
      case "identified":
        this.playerId = msg.playerId;
        break;
      case "obstacle_layout":
        this.map = msg.map;
        this.grid = parseMap(msg.map);
        break;
      case "match_found":
        this.opponentId = msg.opponentId;
        this._onMatch?.();
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
        this._stop();
        this._onGameOver?.(msg);
        break;
    }
  }

  _startMatch() {
    const start = this.map.spawnPos;
    this.snake = Array.from({ length: INITIAL_LEN }, (_, i) => ({ x: start.x - i, y: start.y }));
    this.dir = "right";
    this.countdown = setTimeout(() => {
      this.moveTimer = setInterval(() => this._tick(), MOVE_TICK_MS);
      this.syncTimer = setInterval(() => {
        if (!this.snake.length) return;
        this.send("snake_position_update", { headPos: this.snake[0], bodyCells: this.snake });
      }, SNAKE_POSITION_SYNC_MS);
    }, COUNTDOWN_MS);
  }

  _pickDirection() {
    const head = this.snake[0];
    const candidates = Object.keys(DIRS).filter((d) => d !== OPPOSITE[this.dir]);
    const valid = candidates.filter(
      (d) => !checkDeath(this.grid, { x: head.x + DIRS[d].x, y: head.y + DIRS[d].y }, this.snake, this.growthPending > 0)
    );
    const pool = valid.length ? valid : candidates;

    if (Math.random() < RANDOM_TURN_CHANCE || this.foods.size === 0) {
      return pool[Math.floor(Math.random() * pool.length)];
    }
    // BFS:從蛇頭往外找最近的寶石(繞過牆、障礙物、蛇身),回傳第一步的方向
    const foods = new Set([...this.foods.values()].map(key));
    const body = new Set(this.snake.slice(0, -1).map(key));
    const firstStep = new Map();
    const queue = [];
    for (const d of valid) {
      const n = { x: head.x + DIRS[d].x, y: head.y + DIRS[d].y };
      if (foods.has(key(n))) return d;
      firstStep.set(key(n), d);
      queue.push(n);
    }
    for (let i = 0; i < queue.length; i++) {
      const p = queue[i];
      for (const dd of Object.values(DIRS)) {
        const n = { x: p.x + dd.x, y: p.y + dd.y };
        const k = key(n);
        if (firstStep.has(k) || !this.grid.floor.has(k) || this.grid.blocked.has(k) || body.has(k)) continue;
        firstStep.set(k, firstStep.get(key(p)));
        if (foods.has(k)) return firstStep.get(k);
        queue.push(n);
      }
    }
    return pool[Math.floor(Math.random() * pool.length)];
  }

  _tick() {
    if (!this.snake.length) return;
    const nextDir = this._pickDirection();
    this.dir = nextDir;
    const head = this.snake[0];
    const newHead = { x: head.x + DIRS[nextDir].x, y: head.y + DIRS[nextDir].y };
    const grow = this.growthPending > 0;
    const cause = checkDeath(this.grid, newHead, this.snake, grow);

    if (cause) {
      this.stats.cause = cause;
      this._stop();
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
        this.stats.gems++;
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

  _stop() {
    clearTimeout(this.countdown);
    clearInterval(this.moveTimer);
    clearInterval(this.syncTimer);
  }

  close() {
    this._stop();
    this.ws.close();
  }
}

// 配對階段一次只讓一組排隊,同時跑好幾場時才不會 A 配到別場的 B
let joinLock = Promise.resolve();

async function runOneMatch() {
  const a = new Bot("A");
  const b = new Bot("B");
  await a.connect();
  await b.connect();
  a.identify();
  b.identify();
  await new Promise((r) => setTimeout(r, 100));

  let startedAt = Date.now();
  let timer;
  const result = await new Promise((resolve) => {
    let settled = false;
    const done = (msg) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(msg);
    };
    a._onGameOver = done;
    b._onGameOver = done;
    joinLock = joinLock.then(async () => {
      const matched = new Promise((r) => (b._onMatch = r));
      a.send("join_queue");
      b.send("join_queue");
      await matched;
      startedAt = Date.now();
      timer = setTimeout(() => done({ reason: "timeout", draw: true }), MAX_MATCH_MS);
    });
  });
  const durationMs = Math.max(0, Date.now() - startedAt - COUNTDOWN_MS); // 不含開局倒數(同 game_over.stats 的 survivalMs)

  const stats = {
    durationMs,
    reason: result.reason,
    draw: !!result.draw,
    winnerLabel: result.winnerId === a.playerId ? "A" : result.winnerId === b.playerId ? "B" : null,
    mapId: a.map?.mapId,
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
  const causes = {};
  for (const r of runs) for (const c of [r.a.cause, r.b.cause]) if (c) causes[c] = (causes[c] || 0) + 1;
  const sorted = runs.map((r) => r.durationMs).sort((x, y) => x - y);
  const maps = [...new Set(runs.map((r) => r.mapId))].join(", ");
  const gemsPerMin = avg((r) => (r.a.gems + r.b.gems) / 2 / Math.max(1 / 60, r.durationMs / 60000));

  console.log(`\n===== ${n} 場模擬結果 (MOVE_TICK_MS=${MOVE_TICK_MS}, ATTACK_CHANCE=${ATTACK_CHANCE_PER_TICK}, 地圖: ${maps}) =====`);
  console.log(`平均場長: ${(avg((r) => r.durationMs) / 1000).toFixed(1)} 秒(中位數 ${(sorted[Math.floor(n / 2)] / 1000).toFixed(1)} 秒,不含開局倒數)`);
  console.log(`每人每分鐘吃寶石: ${gemsPerMin.toFixed(1)} 顆(約每 ${(60 / Math.max(0.01, gemsPerMin)).toFixed(1)} 秒一顆)`);
  console.log(`結束原因分布:`, reasonCounts);
  console.log(`死因分布:`, causes);
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
  let next = 0;
  const worker = async () => {
    while (next < MATCHES) {
      const i = next++;
      const r = await runOneMatch();
      runs.push(r);
      console.log(
        `[場 ${i + 1}/${MATCHES}] ${r.mapId} ${(r.durationMs / 1000).toFixed(1)}s reason=${r.reason} ` +
          `winner=${r.draw ? "平手" : r.winnerLabel} 寶石 ${r.a.gems}/${r.b.gems} 死因 ${r.a.cause || "-"}/${r.b.cause || "-"}`
      );
    }
  };
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  summarize(runs);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
