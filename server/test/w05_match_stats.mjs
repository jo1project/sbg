// W-05(結算畫面):game_over 帶雙方戰績 stats { gems, survivalMs, maxLength }
// 單獨執行:node test/w05_match_stats.mjs(沒設 SERVER_URL 會自己起一台測試伺服器)
import { runStandalone, matchPair, check, sleep, TestClient } from "./lib.mjs";

await runStandalone("W-05 結算戰績", async (url) => {
  const { a, b } = await matchPair(url);
  const t0 = Date.now();

  // A 吃 2 顆、B 吃 1 顆
  for (const food of a.foods.slice(0, 2)) {
    a.send({ type: "food_eaten_request", foodId: food.foodId, headPos: food.position });
  }
  b.send({ type: "food_eaten_request", foodId: b.foods[0].foodId, headPos: b.foods[0].position });

  // A 回報過 6 格的蛇身,之後死亡回報只有 1 格 → 最長身長取回報過的最大值
  const y = a.map.spawnPos.y;
  const body = (n) => Array.from({ length: n }, (_, i) => ({ x: 5 - i, y }));
  a.send({ type: "snake_position_update", headPos: body(6)[0], bodyCells: body(6) });
  b.send({ type: "snake_position_update", headPos: body(3)[0], bodyCells: body(3) });

  // 開局倒數 3 秒不算存活時間:等到倒數後約 1 秒才死
  await sleep(4000 - (Date.now() - t0));
  const s = a.mark();
  a.send({ type: "death_report", cause: "wall", headPos: { x: -1, y }, bodyCells: [{ x: 0, y }] });
  const goA = await a.waitFor((m) => m.type === "game_over", 1500, s);
  const goB = await b.waitFor((m) => m.type === "game_over", 1500);

  const sa = goA?.stats?.[a.playerId];
  const sb = goA?.stats?.[b.playerId];
  check(!!sa && !!sb, "game_over 帶雙方的 stats");
  check(sa?.gems === 2 && sb?.gems === 1, `寶石數 A=2、B=1(實際 ${sa?.gems}、${sb?.gems})`);
  check(sa?.maxLength === 6 && sb?.maxLength === 3, `最長身長 A=6、B=3(實際 ${sa?.maxLength}、${sb?.maxLength})`);
  check(sa?.survivalMs >= 700 && sa?.survivalMs <= 1600, `A 存活時間扣掉開局倒數約 1 秒(實際 ${sa?.survivalMs}ms)`);
  check(sb?.survivalMs >= sa?.survivalMs, `B 活到結束,存活時間 ≥ A(實際 ${sb?.survivalMs}ms)`);
  check(JSON.stringify(goB?.stats) === JSON.stringify(goA?.stats), "雙方收到同一份 stats");

  // 累計戰績(大廳顯示):新帳號 identified 帶全 0,打完一場寫進資料庫
  check(a.identified?.record?.wins === 0 && a.identified?.record?.losses === 0, "新帳號 identified.record 是 0 勝 0 敗");
  const ra = sa?.record;
  const rb = sb?.record;
  check(ra?.wins === 0 && ra?.losses === 1, `A 記 1 敗(實際 ${JSON.stringify(ra)})`);
  check(rb?.wins === 1 && rb?.losses === 0, `B 記 1 勝(實際 ${JSON.stringify(rb)})`);

  // 重新連線(同一個 playerId)→ identified.record 從資料庫讀回來
  const id = a.playerId;
  a.close();
  await sleep(300);
  const a2 = new TestClient(url, "A2");
  const idm = await a2.connect({ playerId: id });
  check(idm.playerId === id && idm.record?.losses === 1 && idm.record?.wins === 0, `重連後 identified.record 還在(實際 ${JSON.stringify(idm.record)})`);

  a2.close();
  b.close();
});
