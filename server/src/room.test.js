import assert from "node:assert/strict";
import { Room } from "./room.js";
import { Player } from "./player.js";
import { CONFIG } from "./events.js";

// 最小假房間,validateDeathReport 是純邏輯,不依賴玩家狀態
const fakePlayer = (id) => ({ id, send: () => {}, snakeBody: [], resetForMatch: () => {} });
const room = new Room("test", fakePlayer("A"), fakePlayer("B"));

// 撞牆:座標在邊界外才算數
assert.equal(room.validateDeathReport("A", "wall", { x: -1, y: 5 }), true);
assert.equal(room.validateDeathReport("A", "wall", { x: CONFIG.MAP_SIZE, y: 5 }), true);
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

console.log("room.validateDeathReport: 全部通過");
