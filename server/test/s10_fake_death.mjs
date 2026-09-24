// S-10(規格 6.1):假的死亡回報會被伺服器拒絕
// 單獨執行:node test/s10_fake_death.mjs(沒設 SERVER_URL 會自己起一台測試伺服器)
import { runStandalone, matchPair, check, sleep } from "./lib.mjs";

await runStandalone("S-10 假死亡回報", async (url) => {
  const { a, b } = await matchPair(url);
  const center = a.map.spawnPos; // 重生點一定是可通行地板,當作「地圖中央、根本沒撞牆」的座標

  // 1) 在可通行格回報撞牆
  let s = a.mark();
  a.send({ type: "death_report", cause: "wall", headPos: center, bodyCells: [center] });
  const rej = await a.waitFor((m) => m.type === "death_report_rejected", 1500, s);
  check(rej?.reason === "collision_not_verified", `撞牆回報在地板格 (${center.x},${center.y}) → death_report_rejected`);

  // 2) 回報撞自己,但蛇頭不在身體上
  s = a.mark();
  a.send({ type: "death_report", cause: "self", headPos: center, bodyCells: [{ x: center.x + 1, y: center.y }] });
  const rej2 = await a.waitFor((m) => m.type === "death_report_rejected", 1500, s);
  check(!!rej2, "撞自己但蛇頭不在回報的身體上 → death_report_rejected");

  // 3) 回報撞障礙物,但那格沒有障礙物
  s = a.mark();
  a.send({ type: "death_report", cause: "obstacle", headPos: center, bodyCells: [] });
  const rej3 = await a.waitFor((m) => m.type === "death_report_rejected", 1500, s);
  check(!!rej3, "撞障礙物但那格沒有障礙物 → death_report_rejected");

  await sleep(400); // 超過 Double KO 的 200ms 等待
  check(!a.msgs.some((m) => m.type === "game_over") && !b.msgs.some((m) => m.type === "game_over"), "被拒絕的回報不會結束對局(雙方都沒收到 game_over)");

  // 對照組:真的撞牆會被採信
  s = b.mark();
  a.send({ type: "death_report", cause: "wall", headPos: { x: -1, y: center.y }, bodyCells: [{ x: 0, y: center.y }] });
  const go = await b.waitFor((m) => m.type === "game_over", 1500, s);
  check(go?.winnerId === b.playerId, "對照:真的撞牆(x=-1)被採信,B 獲勝");

  a.close();
  b.close();
});
