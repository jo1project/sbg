// F-04(規格 5):food_eaten_request 的 foodId 對、headPos 錯 → 能量不變、不補食物
// 單獨執行:node test/f04_fake_food.mjs(沒設 SERVER_URL 會自己起一台測試伺服器)
import { runStandalone, matchPair, check, sleep } from "./lib.mjs";

await runStandalone("F-04 假吃食回報", async (url) => {
  const { a, b } = await matchPair(url);
  check(a.foods.length === 3, `開局收到 3 顆食物(實際 ${a.foods.length})`);
  const food = a.foods[0];
  const wrong = { x: food.position.x === 1 ? 2 : 1, y: food.position.y };

  let s = a.mark();
  a.send({ type: "food_eaten_request", foodId: food.foodId, headPos: wrong });
  await sleep(600);
  const after = a.msgs.slice(s);
  check(!after.some((m) => m.type === "energy_update" && m.playerId === a.playerId), "headPos 錯誤 → 沒有 energy_update(能量不變)");
  check(!after.some((m) => m.type === "food_spawned"), "headPos 錯誤 → 沒有補新食物");

  // 不存在的 foodId 也一樣被忽略
  s = a.mark();
  a.send({ type: "food_eaten_request", foodId: "f_nope", headPos: food.position });
  await sleep(400);
  check(!a.msgs.slice(s).some((m) => m.type === "energy_update" || m.type === "food_spawned"), "不存在的 foodId → 忽略");

  // 對照組:位置正確 → 能量 +1、補一顆新的(證明測試本身有效)
  s = a.mark();
  a.send({ type: "food_eaten_request", foodId: food.foodId, headPos: food.position });
  const eu = await a.waitFor((m) => m.type === "energy_update" && m.playerId === a.playerId, 1000, s);
  const fs = await a.waitFor((m) => m.type === "food_spawned", 1000, s);
  check(eu?.energy === 1, "對照:位置正確 → 能量變 1");
  check(!!fs && fs.foodId !== food.foodId, "對照:位置正確 → 補一顆新食物");
  check(!b.msgs.slice(0).some((m) => m.type === "food_spawned" && m.foodId === fs?.foodId), "新食物只通知自己,對手收不到");

  a.close();
  b.close();
});
