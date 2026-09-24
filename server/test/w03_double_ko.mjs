// W-03(規格 6、6.1):雙方死亡回報相差 ≤200ms → Double KO 平手;超過 200ms → 先回報的輸
// 單獨執行:node test/w03_double_ko.mjs(沒設 SERVER_URL 會自己起一台測試伺服器)
import { runStandalone, matchPair, rematch, check, sleep } from "./lib.mjs";

// 合法的撞牆回報:蛇頭走出地圖左邊界
const wallDeath = (c) => ({
  type: "death_report",
  cause: "wall",
  headPos: { x: -1, y: c.map.spawnPos.y },
  bodyCells: [{ x: 0, y: c.map.spawnPos.y }],
});

await runStandalone("W-03 Double KO", async (url) => {
  const { a, b } = await matchPair(url);

  // 1) 50ms 內雙方各回報一次
  let sa = a.mark();
  let sb = b.mark();
  a.send(wallDeath(a));
  await sleep(50);
  b.send(wallDeath(b));
  const goA = await a.waitFor((m) => m.type === "game_over", 1500, sa);
  const goB = await b.waitFor((m) => m.type === "game_over", 1500, sb);
  check(goA?.reason === "double_ko" && goA.draw === true && goA.winnerId === null, "間隔 50ms → A 收到 double_ko 平手");
  check(goB?.reason === "double_ko" && goB.draw === true, "間隔 50ms → B 收到 double_ko 平手");

  // 2) 同一對再配一場,A 先回報,300ms 後 B 才回報
  await rematch(a, b);
  sa = a.mark();
  sb = b.mark();
  a.send(wallDeath(a));
  await sleep(300);
  b.send(wallDeath(b));
  const go2A = await a.waitFor((m) => m.type === "game_over", 1500, sa);
  const go2B = await b.waitFor((m) => m.type === "game_over", 1500, sb);
  check(go2A?.winnerId === b.playerId && !go2A.draw, `間隔 300ms → 先回報的 A 判負(reason ${go2A?.reason})`);
  check(go2B?.winnerId === b.playerId, "間隔 300ms → B 收到自己獲勝");
  check(a.msgs.slice(sa).filter((m) => m.type === "game_over").length === 1, "只會收到一次 game_over(B 較晚的回報被忽略)");

  a.close();
  b.close();
});
