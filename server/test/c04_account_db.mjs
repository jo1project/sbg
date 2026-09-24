// C-02 / C-03 / C-04(規格 8.1):玩家 ID 與還原碼存在 SQLite,重開伺服器後還在,可用還原碼找回帳號
// 這是唯一真的走到資料庫讀寫的測試(需要 better-sqlite3 能載入)。單獨執行:node test/c04_account_db.mjs
// 有設 SERVER_URL 時只測還原碼,不測「重開伺服器」(沒辦法重開別人的伺服器)。
import WebSocket from "ws";
import { startServer, TestClient, check, finish, sleep } from "./lib.mjs";

function rawSend(url, msg) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once("error", reject);
    ws.once("open", () => ws.send(JSON.stringify(msg)));
    ws.once("message", (raw) => {
      resolve(JSON.parse(raw.toString()));
      ws.close();
    });
  });
}

let server = await startServer();
let ok = false;
try {
  const a = new TestClient(server.url, "A");
  const idm = await a.connect();
  check(/^[2-9A-HJ-NP-Z]{6}$/.test(idm.playerId), `新玩家 ID 是 6 碼、沒有 0/O/1/I(${idm.playerId})`);
  check(/^[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}$/.test(idm.recoveryCode || ""), `新帳號附上還原碼(${idm.recoveryCode})`);
  a.close();

  const b = new TestClient(server.url, "A2");
  const id2 = await b.connect({ playerId: idm.playerId });
  check(id2.playerId === idm.playerId && !id2.recoveryCode, "用同一個 ID 再連 → 同一位玩家,不再給還原碼");
  b.close();

  const restored = await rawSend(server.url, { type: "restore_account", recoveryCode: idm.recoveryCode });
  check(restored.type === "account_restored" && restored.playerId === idm.playerId, "restore_account 用還原碼找回同一個 ID");
  const bad = await rawSend(server.url, { type: "restore_account", recoveryCode: "0000-0000-0000" });
  check(bad.type === "restore_failed", "不存在的還原碼 → restore_failed");

  if (!process.env.SERVER_URL) {
    // 關掉伺服器、用同一個資料庫重開:資料要還在
    const dbDir = server.dbDir;
    await server.stop({ keepDb: true });
    server = await startServer({ dbDir });
    const c = new TestClient(server.url, "A3");
    const id3 = await c.connect({ playerId: idm.playerId });
    check(id3.playerId === idm.playerId && !id3.recoveryCode, "重開伺服器後用原本的 ID 連線 → 還是同一位玩家(資料有寫進 SQLite 檔)");
    c.close();
    const restored2 = await rawSend(server.url, { type: "restore_account", recoveryCode: idm.recoveryCode });
    check(restored2.playerId === idm.playerId, "重開伺服器後還原碼仍然有效");
    const unknown = new TestClient(server.url, "X");
    const idx = await unknown.connect({ playerId: "ZZZZZZ" });
    check(idx.playerId !== "ZZZZZZ" && !!idx.recoveryCode, "資料庫裡沒有的 ID → 建立新玩家(附還原碼)");
    unknown.close();
  }
  ok = finish("C-04 帳號與資料庫");
} catch (err) {
  console.log(`FAIL  例外:${err.stack || err}`);
  finish("C-04 帳號與資料庫");
} finally {
  await server.stop();
  await sleep(100);
}
process.exitCode = ok ? 0 : 1;
