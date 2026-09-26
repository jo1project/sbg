// 大地圖產生器:把現有的 classic 地圖(12x24,maps/map_*.json)當成「塊」,拼接成一張多房間大地圖。
// 離線跑、人工看過 ASCII 預覽再 commit 進 maps/(伺服器執行時不產生地圖,維持規格 2.3「固定地圖池」)。
//
// 用法:
//   node tools/gen_large_map.mjs                          # 3 塊、隨機 seed,印 ASCII 預覽
//   node tools/gen_large_map.mjs --blocks=3 --seed=42 --out=maps/large_01.json
//   node tools/gen_large_map.mjs --blocks=3 --candidates=3 --out-dir=/tmp/cands   # 一次產生多張候選
//
// 參數:
//   --blocks   幾塊(預設 3)。排在 blocks x blocks 的格子裡隨機長成相連形狀,之後裁掉空白
//   --gap      塊與塊之間多留幾格虛空(預設 3)。塊本身四周已有 1 格虛空,所以塊間走廊長 gap+2
//   --seed     亂數種子(寫進輸出 JSON,同 seed 同參數一定產生同一張)
//
// 規則(不符合就換 seed 重來,最多 200 次):
//   - 每塊用一張 classic 地圖(可左右/上下翻轉);塊數 >= 3 時三張 classic 都至少用一次
//   - 相鄰的塊用 3 格寬的走廊連接(蛇迴轉要 2 條車道 + 1 格餘裕);生成樹之外,
//     相鄰但沒連的塊 50% 機率也連、已連的塊 50% 機率開第二道門 → 形成迴圈,避免只有死路
//   - 走廊內不放障礙物;走廊口兩側 2 格內的障礙物移除(避免一出走廊就撞)
//   - 障礙物 <= 地板格數 5%
//   - 出生點:四周 3 格內沒有障礙物;開局往右走,右邊 6 格、左邊 3 格(初始蛇身)都是淨空地板
//   - 所有可走格子(地板扣障礙物)彼此連通;沒有 1 格寬的瓶頸
//   - gemCount = round(地板格數 / FLOOR_PER_GEM),跟 classic 的寶石密度一樣(3 顆 / 約 200 格)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SERVER_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const W = 12;
const H = 24;
const FLOOR_PER_GEM = 67;
const CORRIDOR_WIDTH = 3;
const DOOR_CLEAR = 2;
const MAX_OBSTACLE_RATIO = 0.05;

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, "").split("=");
    return [k, v ?? "true"];
  })
);
const BLOCKS = Number(args.blocks ?? 3);
const GAP = Number(args.gap ?? 3);

const templates = fs
  .readdirSync(path.join(SERVER_DIR, "maps"))
  .filter((f) => f.endsWith(".json"))
  .map((f) => JSON.parse(fs.readFileSync(path.join(SERVER_DIR, "maps", f), "utf-8")))
  .filter((m) => (m.mapSet || "classic") === "classic" && m.gridCols === W && m.gridRows === H)
  .sort((a, b) => a.mapId.localeCompare(b.mapId));

// mulberry32:可重現的亂數
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const key = (x, y) => `${x},${y}`;
const obstacleCells = (o) => (o.size === "big" ? [{ x: o.x, y: o.y }, { x: o.x + 1, y: o.y }] : [{ x: o.x, y: o.y }]);

// 塊的排列:從 (0,0) 開始,每次挑一個已放的塊的空鄰格長出去 → 一定相連;回傳 [slots, 生成樹的邊]
function layout(rand) {
  const slots = [[0, 0]];
  const tree = [];
  const has = (x, y) => slots.some(([a, b]) => a === x && b === y);
  while (slots.length < BLOCKS) {
    const options = [];
    slots.forEach(([x, y], i) => {
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        if (!has(x + dx, y + dy)) options.push([i, x + dx, y + dy]);
      }
    });
    const [from, nx, ny] = options[Math.floor(rand() * options.length)];
    slots.push([nx, ny]);
    tree.push([from, slots.length - 1]);
  }
  const minX = Math.min(...slots.map((s) => s[0]));
  const minY = Math.min(...slots.map((s) => s[1]));
  return { slots: slots.map(([x, y]) => [x - minX, y - minY]), tree };
}

// 把一張 classic 地圖翻轉後平移到 (ox, oy)
function place(t, flipX, flipY, ox, oy) {
  const fx = (x0, x1) => (flipX ? [W - 1 - x1, W - 1 - x0] : [x0, x1]);
  const fy = (y0, y1) => (flipY ? [H - 1 - y1, H - 1 - y0] : [y0, y1]);
  const rect = (r) => {
    const [x0, x1] = fx(r.x0, r.x1);
    const [y0, y1] = fy(r.y0, r.y1);
    return { x0: x0 + ox, x1: x1 + ox, y0: y0 + oy, y1: y1 + oy };
  };
  const obstacles = t.obstacles.map((o) => {
    const wide = o.size === "big" ? 1 : 0;
    const x = flipX ? W - 1 - o.x - wide : o.x;
    const y = flipY ? H - 1 - o.y : o.y;
    return { ...o, x: x + ox, y: y + oy };
  });
  return { rooms: t.rooms.map(rect), corridors: t.corridors.map(rect), obstacles };
}

function generate(seed) {
  const rand = rng(seed);
  const { slots, tree } = layout(rand);
  const cols = Math.max(...slots.map((s) => s[0])) + 1;
  const rows = Math.max(...slots.map((s) => s[1])) + 1;
  const origin = ([sx, sy]) => [sx * (W + GAP), sy * (H + GAP)];

  // 每塊的模板:先把所有模板各放一次(洗牌),不夠再隨機補
  const order = [...templates].sort(() => rand() - 0.5);
  while (order.length < slots.length) order.push(templates[Math.floor(rand() * templates.length)]);
  const blocks = slots.map((s, i) => {
    const t = order[i];
    const flipX = rand() < 0.5;
    const flipY = rand() < 0.5;
    return { t, flipX, flipY, ...place(t, flipX, flipY, ...origin(s)) };
  });

  const rooms = blocks.flatMap((b) => b.rooms);
  const corridors = blocks.flatMap((b) => b.corridors);
  let obstacles = blocks.flatMap((b) => b.obstacles);
  const floor = new Set();
  for (const z of [...rooms, ...corridors]) for (let x = z.x0; x <= z.x1; x++) for (let y = z.y0; y <= z.y1; y++) floor.add(key(x, y));

  // 要連的邊:生成樹 + 其他相鄰的塊(50%),已連的邊 50% 開第二道門
  const edges = tree.map(([a, b]) => [a, b]);
  for (let i = 0; i < slots.length; i++) {
    for (let j = i + 1; j < slots.length; j++) {
      const adj = Math.abs(slots[i][0] - slots[j][0]) + Math.abs(slots[i][1] - slots[j][1]) === 1;
      const inTree = edges.some(([a, b]) => (a === i && b === j) || (a === j && b === i));
      if (adj && !inTree && rand() < 0.5) edges.push([i, j]);
    }
  }
  for (const e of [...edges]) if (rand() < 0.5) edges.push(e);

  const mouths = []; // 走廊口兩端的地板格,之後清掉附近的障礙物
  const used = new Map(); // 邊 -> 已開的門的位置,第二道門要離第一道 >= 4 格
  const newCorridors = [];
  for (let [a, b] of edges) {
    let [ax, ay] = origin(slots[a]);
    let [bx, by] = origin(slots[b]);
    const horizontal = slots[a][1] === slots[b][1];
    if ((horizontal && ax > bx) || (!horizontal && ay > by)) {
      [a, b] = [b, a];
      [ax, ay, bx, by] = [bx, by, ax, ay];
    }
    // 兩塊相對的邊緣上,兩側都是地板的位置(水平相鄰看列,垂直相鄰看欄)
    const edgeA = horizontal ? ax + W - 2 : ay + H - 2;
    const edgeB = horizontal ? bx + 1 : by + 1;
    const span = horizontal ? H : W;
    const base = horizontal ? ay : ax;
    const ok = [];
    for (let i = 0; i + CORRIDOR_WIDTH <= span; i++) {
      let fits = true;
      for (let k = 0; k < CORRIDOR_WIDTH; k++) {
        const p = base + i + k;
        const aCell = horizontal ? key(edgeA, p) : key(p, edgeA);
        const bCell = horizontal ? key(edgeB, p) : key(p, edgeB);
        if (!floor.has(aCell) || !floor.has(bCell)) fits = false;
      }
      const eKey = `${a}-${b}`;
      if (fits && !(used.get(eKey) || []).some((q) => Math.abs(q - i) < CORRIDOR_WIDTH + 4)) ok.push(i);
    }
    if (ok.length === 0) continue; // 第二道門放不下就算了;生成樹的邊放不下會在連通檢查被擋掉
    const i = ok[Math.floor(rand() * ok.length)];
    const eKey = `${a}-${b}`;
    used.set(eKey, [...(used.get(eKey) || []), i]);
    const p0 = base + i;
    const p1 = p0 + CORRIDOR_WIDTH - 1;
    const c = horizontal
      ? { x0: edgeA + 1, x1: edgeB - 1, y0: p0, y1: p1 }
      : { x0: p0, x1: p1, y0: edgeA + 1, y1: edgeB - 1 };
    newCorridors.push(c);
    for (let p = p0; p <= p1; p++) mouths.push(horizontal ? [edgeA, p] : [p, edgeA], horizontal ? [edgeB, p] : [p, edgeB]);
    for (let x = c.x0; x <= c.x1; x++) for (let y = c.y0; y <= c.y1; y++) floor.add(key(x, y));
  }

  // 走廊口附近的障礙物移除
  const nearMouth = (c) => mouths.some(([mx, my]) => Math.abs(mx - c.x) <= DOOR_CLEAR && Math.abs(my - c.y) <= DOOR_CLEAR);
  const removed = obstacles.filter((o) => obstacleCells(o).some(nearMouth));
  obstacles = obstacles.filter((o) => !removed.includes(o));

  const blocked = new Set(obstacles.flatMap(obstacleCells).map((c) => key(c.x, c.y)));
  const open = (x, y) => floor.has(key(x, y)) && !blocked.has(key(x, y));

  // 出生點:每個房間裡符合淨空規則、最靠近房間中心的格子,隨機挑一個房間
  const spawnOk = (x, y) => {
    for (let dx = -3; dx <= 3; dx++) for (let dy = -3; dy <= 3; dy++) if (blocked.has(key(x + dx, y + dy))) return false;
    for (let dx = -3; dx <= 6; dx++) if (!open(x + dx, y)) return false;
    return true;
  };
  const spawnChoices = [];
  for (const r of rooms) {
    const cx = (r.x0 + r.x1) / 2;
    const cy = (r.y0 + r.y1) / 2;
    let best = null;
    for (let x = r.x0; x <= r.x1; x++) {
      for (let y = r.y0; y <= r.y1; y++) {
        if (!spawnOk(x, y)) continue;
        const d = Math.abs(x - cx) + Math.abs(y - cy);
        if (!best || d < best.d) best = { x, y, d };
      }
    }
    if (best) spawnChoices.push({ x: best.x, y: best.y });
  }

  const allCorridors = [...corridors, ...newCorridors];
  const map = {
    mapId: `large_s${seed}`,
    mapSet: "large",
    seed,
    blocks: blocks.map((b) => `${b.t.mapId}${b.flipX ? "~x" : ""}${b.flipY ? "~y" : ""}`),
    gridCols: cols * W + (cols - 1) * GAP,
    gridRows: rows * H + (rows - 1) * GAP,
    gemCount: Math.round(floor.size / FLOOR_PER_GEM),
    rooms,
    corridors: allCorridors,
    spawnPos: spawnChoices.length ? spawnChoices[Math.floor(rand() * spawnChoices.length)] : null,
    obstacles,
  };
  const shape = `${cols}x${rows}`; // 排列的外框(3 塊:橫排 / 直排 / L 形)
  return { map, removed, shape, newCorridors, problems: validate(map, floor, blocked, edges, tree, newCorridors) };
}

function validate(map, floor, blocked, _edges, tree, newCorridors) {
  const problems = [];
  if (!map.spawnPos) problems.push("找不到符合淨空規則的出生點");
  if (newCorridors.length < tree.length) problems.push("有相鄰的塊接不起來(邊緣沒有 3 格寬的共同地板)");
  const obstacleCount = [...blocked].length;
  if (obstacleCount > floor.size * MAX_OBSTACLE_RATIO) problems.push(`障礙物 ${obstacleCount} 格 > 地板 5%`);

  const open = (k) => floor.has(k) && !blocked.has(k);
  const openCells = [...floor].filter(open);
  // 從 start 走得到幾格(skip:當成擋住的格子)
  const reach = (start, skip = null) => {
    const seen = new Set([start]);
    const stack = [start];
    while (stack.length) {
      const [x, y] = stack.pop().split(",").map(Number);
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const k = key(x + dx, y + dy);
        if (k !== skip && open(k) && !seen.has(k)) {
          seen.add(k);
          stack.push(k);
        }
      }
    }
    return seen.size;
  };
  // 連通
  if (map.spawnPos) {
    const n = reach(key(map.spawnPos.x, map.spawnPos.y));
    if (n !== openCells.length) problems.push(`有 ${openCells.length - n} 格走不到`);
  }
  // 1 格寬瓶頸:左右都擋住但上下能走(或反過來),而且是唯一通道(堵住它地圖就斷成兩半)。
  // 障礙物跟牆之間的 1 格縫(classic 手工地圖本來就有)繞過障礙物就好,不算
  const chokes = openCells.filter((k) => {
    const [x, y] = k.split(",").map(Number);
    const o = (dx, dy) => open(key(x + dx, y + dy));
    const narrow = (!o(-1, 0) && !o(1, 0) && o(0, -1) && o(0, 1)) || (!o(0, -1) && !o(0, 1) && o(-1, 0) && o(1, 0));
    if (!narrow) return false;
    const neighbor = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => key(x + dx, y + dy)).find(open);
    return reach(neighbor, k) !== openCells.length - 1;
  });
  if (chokes.length) problems.push(`1 格寬瓶頸 ${chokes.length} 處:${chokes.slice(0, 5).join(" ")}`);
  return problems;
}

// ASCII 預覽:# 虛空  . 房間地板  , 走廊  o 障礙物  M 大型怪物(兩格)  S 出生點  > 開局蛇身
export function ascii(map) {
  const grid = Array.from({ length: map.gridRows }, () => Array(map.gridCols).fill("#"));
  for (const z of map.corridors) for (let x = z.x0; x <= z.x1; x++) for (let y = z.y0; y <= z.y1; y++) grid[y][x] = ",";
  for (const z of map.rooms) for (let x = z.x0; x <= z.x1; x++) for (let y = z.y0; y <= z.y1; y++) grid[y][x] = ".";
  for (const o of map.obstacles) for (const c of obstacleCells(o)) grid[c.y][c.x] = o.size === "big" ? "M" : "o";
  if (map.spawnPos) {
    for (let i = 1; i <= 3; i++) grid[map.spawnPos.y][map.spawnPos.x - i] = ">";
    grid[map.spawnPos.y][map.spawnPos.x] = "S";
  }
  return grid.map((r) => r.join("")).join("\n");
}

function summary(map, removed) {
  const floor = new Set();
  for (const z of [...map.rooms, ...map.corridors]) for (let x = z.x0; x <= z.x1; x++) for (let y = z.y0; y <= z.y1; y++) floor.add(key(x, y));
  return [
    `${map.mapId}  ${map.gridCols}x${map.gridRows}  塊:${map.blocks.join(" + ")}`,
    `地板 ${floor.size} 格(classic 約 200)  房間 ${map.rooms.length}  走廊 ${map.corridors.length}  障礙物 ${map.obstacles.length}` +
      `(走廊口移除 ${removed.length})  寶石 ${map.gemCount}  出生點 (${map.spawnPos.x},${map.spawnPos.y})`,
  ].join("\n");
}

function run() {
  const count = Number(args.candidates ?? 1);
  let seed = Number(args.seed ?? Math.floor(Math.random() * 1e6));
  const results = [];
  for (let tries = 0; results.length < count && tries < 200 * count; tries++, seed++) {
    const r = generate(seed);
    // 多張候選時排列外框不重複(前 100 次試不出新的就接受重複),方便比較
    if (tries < 100 && results.some((x) => x.shape === r.shape)) continue;
    if (r.problems.length) {
      if (args.verbose) console.error(`seed ${seed} 不合格:${r.problems.join(";")}`);
      continue;
    }
    results.push(r);
  }
  if (results.length < count) {
    console.error(`只產生出 ${results.length}/${count} 張合格地圖`);
    process.exitCode = 1;
  }
  for (const { map, removed } of results) {
    console.log(summary(map, removed));
    console.log(ascii(map));
    console.log("");
    const out = count === 1 && args.out ? args.out : args["out-dir"] ? path.join(args["out-dir"], `${map.mapId}.json`) : null;
    if (out) {
      fs.mkdirSync(path.dirname(out), { recursive: true });
      fs.writeFileSync(out, JSON.stringify(map, null, 2) + "\n");
      console.log(`寫入 ${out}\n`);
    }
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) run();
