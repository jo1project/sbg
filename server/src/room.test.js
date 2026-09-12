import assert from "node:assert/strict";
import { Room } from "./room.js";
import { Player } from "./player.js";
import { CONFIG } from "./events.js";

// 最小假房間,validateDeathReport 是純邏輯,不依賴玩家狀態
const fakePlayer = (id) => ({ id, send: () => {}, snakeBody: [], resetForMatch: () => {} });
const room = new Room("test", fakePlayer("A"), fakePlayer("B"));

// 撞牆:座標在邊界外才算數(地圖非正方形,x/y邊界要分開驗證)
assert.equal(room.validateDeathReport("A", "wall", { x: -1, y: 5 }), true);
assert.equal(room.validateDeathReport("A", "wall", { x: CONFIG.MAP_WIDTH, y: 5 }), true);
assert.equal(room.validateDeathReport("A", "wall", { x: 5, y: CONFIG.MAP_HEIGHT }), true);
assert.equal(room.validateDeathReport("A", "wall", { x: 5, y: 5 }), false, "地圖中央不該算撞牆死亡");

// 撞自己:蛇頭需真的落在回報的蛇身格上
assert.equal(room.validateDeathReport("A", "self", { x: 3, y: 3 }, [{ x: 3, y: 3 }, { x: 2, y: 3 }]), true);
assert.equal(room.validateDeathReport("A", "self", { x: 9, y: 9 }, [{ x: 3, y: 3 }]), false, "沒撞到身體不該算數");
assert.equal(room.validateDeathReport("A", "self", { x: 3, y: 3 }, []), false, "空蛇身不該算撞自己");

// 撞障礙物:比對該玩家自己抽到的地圖的障礙物清單(各玩家獨立,見maps.js地圖池)
room.maps["A"] = { rooms: [{ x0: 0, x1: 11, y0: 0, y1: 23 }], corridors: [], obstacles: [{ x: 7, y: 7 }] };
room.maps["B"] = { rooms: [{ x0: 0, x1: 11, y0: 0, y1: 23 }], corridors: [], obstacles: [{ x: 1, y: 1 }] };
assert.equal(room.validateDeathReport("A", "obstacle", { x: 7, y: 7 }), true);
assert.equal(room.validateDeathReport("A", "obstacle", { x: 1, y: 1 }), false, "那是對方的障礙物,不是自己的");
assert.equal(room.validateDeathReport("B", "obstacle", { x: 1, y: 1 }), true);

// 撞牆/牆體:落在地圖的房間/走廊範圍之外(黑色虛空)也算撞牆,即使沒超出地圖邊界
room.maps["A"] = {
  rooms: [{ x0: 1, x1: 10, y0: 1, y1: 4 }],
  corridors: [],
  obstacles: [],
};
assert.equal(room.validateDeathReport("A", "wall", { x: 5, y: 2 }), false, "房間內部不算撞牆");
assert.equal(room.validateDeathReport("A", "wall", { x: 0, y: 2 }), true, "房間範圍外的地板內座標算撞牆(牆體/虛空)");
assert.equal(room.validateDeathReport("A", "wall", { x: 5, y: 15 }), true, "沒有房間/走廊覆蓋的座標算撞牆(黑色虛空)");

// 缺資料 / 未知死因一律拒絕
assert.equal(room.validateDeathReport("A", "wall", null), false);
assert.equal(room.validateDeathReport("A", "teleport", { x: 3, y: 3 }, []), false);

clearInterval(room.minimapTimer);

// 回歸測試:同一個 Player 物件(同一條WebSocket連線)打完第一場、死亡回報一次後,
// 若沒重置就直接進第二場,第二場真的死亡時 handleDeathReport 會因 deathReportedAt
// 還留著上一場的值而被靜默忽略(玩家會卡死畫面、遊戲也不結束)。
const realA = new Player("realA", { send: () => {} });
const realB = new Player("realB", { send: () => {} });
const room1 = new Room("m1", realA, realB);
clearInterval(room1.minimapTimer);
realA.deathReportedAt = Date.now(); // 模擬第一場死亡回報過

const room2 = new Room("m2", realA, realB); // 配到第二場,同一組Player物件被重用
clearInterval(room2.minimapTimer);
assert.equal(realA.deathReportedAt, null, "新的一場對戰開始時,上一場的死亡回報記錄要被清掉");

// 固定地圖池:房間建立時雙方各自獨立抽到一張完整地圖(mapId/rooms/corridors/obstacles),
// 且之後生成的食物只會落在該地圖的房間/走廊可通行範圍內、不會疊在障礙物上(見 maps.js + room.js spawnFood)
const sentMessages = { C: [], D: [] };
const trackedPlayer = (id) => ({
  id,
  send: (type, payload) => sentMessages[id].push({ type, payload }),
  snakeBody: [],
  resetForMatch: () => {},
});
const room3 = new Room("m3", trackedPlayer("C"), trackedPlayer("D"));
clearInterval(room3.minimapTimer);

const isInZones = (map, pos) =>
  [...map.rooms, ...map.corridors].some((z) => pos.x >= z.x0 && pos.x <= z.x1 && pos.y >= z.y0 && pos.y <= z.y1);

for (const id of ["C", "D"]) {
  const map = room3.maps[id];
  assert.ok(map && map.mapId, "每位玩家應各自抽到一張完整地圖");
  assert.equal(map.gridCols, CONFIG.MAP_WIDTH, "地圖欄數需與伺服器MAP_WIDTH一致");
  assert.equal(map.gridRows, CONFIG.MAP_HEIGHT, "地圖列數需與伺服器MAP_HEIGHT一致");

  const mapMsg = sentMessages[id].find((m) => m.type === "obstacle_layout");
  assert.ok(mapMsg && mapMsg.payload.map === map, "obstacle_layout事件應攜帶完整地圖資料給該玩家自己");

  const foodMsgs = sentMessages[id].filter((m) => m.type === "food_spawned");
  assert.equal(foodMsgs.length, CONFIG.FOOD_COUNT, "房間建立時應補滿恆定食物數量");
  for (const { payload } of foodMsgs) {
    assert.ok(isInZones(map, payload.position), "食物只能生成在房間/走廊可通行範圍內");
    assert.ok(
      !map.obstacles.some((o) => o.x === payload.position.x && o.y === payload.position.y),
      "食物不該生成在障礙物座標上"
    );
  }
}

console.log("room.validateDeathReport: 全部通過");
