// E-07(規格 6):暫停效果解除的瞬間,原方向前方是自己的身體 → 死亡 self,伺服器採信
// 需要除錯指令(自己起的測試伺服器會開;用 SERVER_URL 連別台時那台要 SBG_DEBUG_COMMANDS=1)。
// 單獨執行:node test/e07_pause_body_death.mjs
//
// 情境:A 的蛇 6 節、貼著自己繞小圈、剛被直接攻擊命中還有待成長的長度(尾巴暫時不會讓開),
// 這時被 B 的隨機攻擊命中暫停。暫停中蛇完全靜止;暫停結束後照原方向走的第一步就撞上身體。
// 伺服器不模擬移動,這裡用 client 會送的訊息重現:暫停期間回報座標、暫停結束後送 death_report。
import { runStandalone, matchPair, debugClient, check, sleep } from "./lib.mjs";

await runStandalone("E-07 暫停解除撞身體", async (url) => {
  const { a, b } = await matchPair(url);
  const dbg = await debugClient(url);
  const s0 = a.map.spawnPos;

  // A 的蛇:頭在 (x,y) 往右;身體依序 左→左下→下→右下,頭的右邊 (x+1,y) 是身體的第 4 節
  //   (x-1,y) (x,y)=頭 → 下一步 (x+1,y)
  //   (x-1,y+1) (x,y+1) (x+1,y+1)
  // 簡化成:body = [頭(x,y), (x-1,y), (x-1,y+1), (x,y+1), (x+1,y+1), (x+1,y)]  (x+1,y) 是尾巴前一節,不會讓開
  const x = s0.x, y = s0.y;
  const body = [
    { x, y },
    { x: x - 1, y },
    { x: x - 1, y: y + 1 },
    { x, y: y + 1 },
    { x: x + 1, y: y + 1 },
    { x: x + 1, y }, // 尾巴(因為還有待成長長度,這一步尾巴不會移走)
  ];
  const ahead = { x: x + 1, y }; // 往右的下一格 = 自己身體

  // B 發動隨機攻擊,指定暫停,A 不閃
  await dbg.cmd({ type: "debug_set_energy", playerId: b.playerId, energy: 6 });
  await dbg.cmd({ type: "debug_force_next_effect", playerId: a.playerId, effect: "pause" });
  let s = a.mark();
  b.send({ type: "attack_request", attackType: "random", clientTime: Date.now() });
  const res = await a.waitFor((m) => m.type === "attack_result", 2500, s);
  check(res?.effectType === "pause" && res.dodged === false, "A 沒閃,被 pause 命中");
  check(res?.effectDuration === 3000, `暫停 3000ms(能量 6 × 0.5 = 3 秒,實際 ${res?.effectDuration})`);

  // 效果在預告 1 秒後生效;暫停期間 A 靜止,照常每秒回報座標
  await sleep((res?.previewDelayMs ?? 1000) + 200);
  const list = await dbg.cmd({ type: "debug_list" });
  const aState = list.players.find((p) => p.playerId === a.playerId);
  check(aState?.activeEffect?.type === "pause", "伺服器端 A 正在暫停中");
  for (let i = 0; i < 2; i++) {
    a.send({ type: "snake_position_update", headPos: body[0], bodyCells: body });
    await sleep(1000);
  }

  // 暫停中不能攻擊
  await dbg.cmd({ type: "debug_set_energy", playerId: a.playerId, energy: 3 });
  s = a.mark();
  a.send({ type: "attack_request", attackType: "direct", clientTime: Date.now() });
  const rej = await a.waitFor((m) => m.type === "attack_rejected", 1000, s);
  check(rej?.reason === "attacker_paused", "暫停中 A 不能攻擊(attacker_paused)");

  // 等暫停結束,照原方向(右)走第一步 → 撞到身體
  await sleep(1000);
  const list2 = await dbg.cmd({ type: "debug_list" });
  check(!list2.players.find((p) => p.playerId === a.playerId)?.activeEffect, "暫停已結束");
  s = b.mark();
  const sa = a.mark();
  a.send({ type: "death_report", cause: "self", headPos: ahead, bodyCells: body });
  const go = await b.waitFor((m) => m.type === "game_over", 1500, s);
  check(!a.msgs.slice(sa).some((m) => m.type === "death_report_rejected"), "死亡回報沒有被拒絕");
  check(go?.winnerId === b.playerId && go.reason === "single_death", "伺服器採信:A 撞自己死亡,B 獲勝");

  dbg.close();
  a.close();
  b.close();
});
