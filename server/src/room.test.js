import assert from "node:assert/strict";
import { Room } from "./room.js";
import { CONFIG } from "./events.js";

// 最小假房間,validateDeathReport 是純邏輯,不依賴玩家狀態
const fakePlayer = (id) => ({ id, send: () => {}, snakeBody: [] });
const room = new Room("test", fakePlayer("A"), fakePlayer("B"));

// 撞牆:座標在邊界外才算數
assert.equal(room.validateDeathReport("wall", { x: -1, y: 5 }), true);
assert.equal(room.validateDeathReport("wall", { x: CONFIG.MAP_SIZE, y: 5 }), true);
assert.equal(room.validateDeathReport("wall", { x: 5, y: 5 }), false, "地圖中央不該算撞牆死亡");

// 撞自己:蛇頭需真的落在回報的蛇身格上
assert.equal(room.validateDeathReport("self", { x: 3, y: 3 }, [{ x: 3, y: 3 }, { x: 2, y: 3 }]), true);
assert.equal(room.validateDeathReport("self", { x: 9, y: 9 }, [{ x: 3, y: 3 }]), false, "沒撞到身體不該算數");
assert.equal(room.validateDeathReport("self", { x: 3, y: 3 }, []), false, "空蛇身不該算撞自己");

// 缺資料 / 未知死因一律拒絕
assert.equal(room.validateDeathReport("wall", null), false);
assert.equal(room.validateDeathReport("teleport", { x: 3, y: 3 }, []), false);

clearInterval(room.minimapTimer);
console.log("room.validateDeathReport: 全部通過");
