// L(大地圖):identify 帶 mapSets 含 "large" 的雙方拿到同一張大地圖(大地圖池多張時每場隨機抽一張,但雙方一定同一張)、
// 寶石數照地圖 gemCount;有一方沒帶(Flutter)就雙方都走 classic;大地圖上的地板不會被當成撞牆
// 單獨執行:node test/l_large_map.mjs(沒設 SERVER_URL 會自己起測試伺服器,用 server/maps/ 的地圖池)
import { runStandalone, check, TestClient } from "./lib.mjs";

const GODOT = { identify: { mapSets: ["classic", "large"] } };
const MATCHES = 12;

async function pair(a, b) {
  const sa = a.mark();
  const sb = b.mark();
  a.send({ type: "join_queue" });
  b.send({ type: "join_queue" });
  for (const [c, s] of [[a, sa], [b, sb]]) {
    await c.waitFor((m) => m.type === "match_found", 3000, s);
    c.map = (await c.waitFor((m) => m.type === "obstacle_layout", 1000, s))?.map;
    c.foods = c.msgs.slice(s).filter((m) => m.type === "food_spawned");
  }
}

async function leave(a, b) {
  const s = b.mark();
  a.send({ type: "leave_room" });
  await b.waitFor((m) => m.type === "game_over", 2000, s);
}

await runStandalone("L 大地圖", async (url) => {
  // 雙方都支援大地圖 → 每場雙方同一張;打多場,大地圖池的每張都應該抽得到
  const a = new TestClient(url, "GodotA");
  const b = new TestClient(url, "GodotB");
  await a.connect(GODOT);
  await b.connect(GODOT);
  const seen = new Set();
  let allSame = true;
  let allLarge = true;
  let gemsOk = true;
  for (let i = 0; i < MATCHES; i++) {
    await pair(a, b);
    if (a.map?.mapId !== b.map?.mapId) allSame = false;
    if (a.map?.mapSet !== "large") allLarge = false;
    if (a.foods.length !== a.map?.gemCount || b.foods.length !== b.map?.gemCount) gemsOk = false;
    seen.add(a.map?.mapId);
    if (i < MATCHES - 1) await leave(a, b);
  }
  check(allLarge, "雙方都支援時拿到大地圖");
  check(allSame, `${MATCHES} 場每場雙方都是同一張地圖`);
  check(seen.size >= 2, `大地圖池每張都抽得到(抽到 ${[...seen].join("、")})`);
  check(gemsOk, "寶石數照地圖 gemCount");
  check(a.foods.some((f) => f.position.x >= 12 || f.position.y >= 24), "寶石會出現在 12x24 以外(整張大地圖都會生)");

  // 大地圖上 12x24 以外的地板回報撞牆 → 驗證不通過(以前寫死 12x24 會被當成出界)
  const room = a.map.rooms.find((r) => r.x1 >= 12);
  const floorCell = { x: room.x1, y: room.y0 };
  let s = a.mark();
  a.send({ type: "death_report", cause: "wall", headPos: floorCell, bodyCells: [{ x: floorCell.x - 1, y: floorCell.y }] });
  check(!!(await a.waitFor((m) => m.type === "death_report_rejected", 1500, s)), `大地圖地板 (${floorCell.x},${floorCell.y}) 上的撞牆回報被拒絕`);
  await leave(a, b);

  // 一方沒帶 mapSets(Flutter)→ 雙方 classic
  const f = new TestClient(url, "Flutter");
  await f.connect();
  const c = new TestClient(url, "GodotC");
  await c.connect(GODOT);
  await pair(f, c);
  check(f.map?.gridCols === 12 && c.map?.gridCols === 12, `Flutter vs Godot 雙方都是 12 欄 classic(實際 ${f.map?.gridCols}、${c.map?.gridCols})`);
  check(f.foods.length === 3 && c.foods.length === 3, `classic 寶石數 3(實際 ${f.foods.length}、${c.foods.length})`);

  // mapSets 格式不對 → 當成只支援 classic
  const bad = new TestClient(url, "Bad");
  await bad.connect({ identify: { mapSets: "large" } });
  const d = new TestClient(url, "GodotD");
  await d.connect(GODOT);
  await pair(bad, d);
  check(bad.map?.gridCols === 12, "mapSets 不是陣列時當成 classic");

  for (const x of [a, b, f, c, bad, d]) x.close();
});
