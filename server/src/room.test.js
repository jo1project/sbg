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

// 撞障礙物:比對該玩家自己的障礙物清單(各玩家獨立)
room.obstacles["A"] = [{ x: 7, y: 7 }];
room.obstacles["B"] = [{ x: 1, y: 1 }];
assert.equal(room.validateDeathReport("A", "obstacle", { x: 7, y: 7 }), true);
assert.equal(room.validateDeathReport("A", "obstacle", { x: 1, y: 1 }), false, "那是對方的障礙物,不是自己的");
assert.equal(room.validateDeathReport("B", "obstacle", { x: 1, y: 1 }), true);

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

// 障礙物生成規則:稀疏地標式(數量上限、彼此曼哈頓距離下限、排除中央地帶、避開重生安全區)
const room3 = new Room("m3", fakePlayer("C"), fakePlayer("D"));
clearInterval(room3.minimapTimer);
const insetX = CONFIG.MAP_WIDTH * CONFIG.OBSTACLE_CENTER_INSET_RATIO;
const insetY = CONFIG.MAP_HEIGHT * CONFIG.OBSTACLE_CENTER_INSET_RATIO;
const spawnX = Math.floor(CONFIG.MAP_WIDTH / 2);
const spawnY = Math.floor(CONFIG.MAP_HEIGHT / 2);
for (const id of ["C", "D"]) {
  const list = room3.obstacles[id];
  assert.ok(list.length <= CONFIG.OBSTACLE_COUNT, "障礙物數量不該超過目標值");
  for (const o of list) {
    const inCentral = o.x >= insetX && o.x < CONFIG.MAP_WIDTH - insetX && o.y >= insetY && o.y < CONFIG.MAP_HEIGHT - insetY;
    assert.equal(inCentral, false, "障礙物不該落在中央排除地帶");
    assert.ok(Math.hypot(o.x - spawnX, o.y - spawnY) > CONFIG.OBSTACLE_SAFE_RADIUS, "障礙物不該落在重生安全區內");
  }
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) {
      const dist = Math.abs(list[i].x - list[j].x) + Math.abs(list[i].y - list[j].y);
      assert.ok(dist >= CONFIG.OBSTACLE_MIN_DIST, "任兩障礙物曼哈頓距離需 >= 下限");
    }
  }
}

console.log("room.validateDeathReport: 全部通過");
