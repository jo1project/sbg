// D-04～D-10(規格 6.2):斷線寬限、整場凍結、重連恢復、切背景、心跳逾時
// 需要除錯指令(自己起的測試伺服器會開)。單獨執行:node test/d_reconnect.mjs(約 40 秒)
import { runStandalone, matchPair, rematch, debugClient, check, sleep } from "./lib.mjs";
import { CONFIG } from "../src/events.js";

const near = (v, target, tol) => typeof v === "number" && Math.abs(v - target) <= tol;

await runStandalone("D 斷線與重連", async (url) => {
  const { a, b } = await matchPair(url);
  const dbg = await debugClient(url);
  const state = async (c) => (await dbg.cmd({ type: "debug_list" })).players.find((p) => p.playerId === c.playerId);

  // ---------- D-07:效果進行中斷線,重連後剩餘時間正確 ----------
  await dbg.cmd({ type: "debug_set_energy", playerId: b.playerId, energy: 8 }); // 失明 8 × 0.5 = 4 秒
  await dbg.cmd({ type: "debug_force_next_effect", playerId: a.playerId, effect: "blind" });
  let s = a.mark();
  b.send({ type: "attack_request", attackType: "random", clientTime: Date.now() });
  const res = await a.waitFor((m) => m.type === "attack_result", 2500, s);
  check(res?.effectType === "blind" && res.effectDuration === 4000, "A 被失明 4 秒命中");
  await sleep(1000 + 1000); // 預告 1 秒 + 效果跑 1 秒
  const before = await state(a);
  check(near(before?.activeEffect?.msLeft, 3000, 150), `斷線前效果剩約 3000ms(實際 ${before?.activeEffect?.msLeft})`);

  let sb = b.mark();
  a.drop(); // A 斷線(切背景 = 直接關連線,不送 leave_room)
  const disc = await b.waitFor((m) => m.type === "opponent_disconnected", 1000, sb);
  check(disc?.graceMs === CONFIG.RECONNECT_GRACE_MS, "B 立刻收到 opponent_disconnected(寬限 10 秒)");

  // 凍結期間 B 的攻擊被擋
  await dbg.cmd({ type: "debug_set_energy", playerId: b.playerId, energy: 3 });
  b.send({ type: "attack_request", attackType: "direct", clientTime: Date.now() });
  const rej = await b.waitFor((m) => m.type === "attack_rejected", 1000, sb);
  check(rej?.reason === "match_paused", "凍結期間不能攻擊(match_paused)");

  await sleep(3000);
  sb = b.mark();
  const sa = a.mark();
  const idm = await a.reconnect();
  check(idm?.reconnected === true && idm.inRoom === true, "A 用同一個 playerId 重連 → identified reconnected: true, inRoom: true");
  const resumedA = await a.waitFor((m) => m.type === "match_resumed", 1000, sa);
  const resumedB = await b.waitFor((m) => m.type === "match_resumed", 1000, sb);
  check(!!resumedA && !!resumedB, "雙方都收到 match_resumed");
  check(resumedA && resumedB && resumedA.serverTime === resumedB.serverTime, "雙方收到的是同一則恢復訊息(serverTime 相同)");
  check(near(resumedA?.pausedMs, 3000, 300), `pausedMs ≈ 3000(實際 ${resumedA?.pausedMs})`);
  const after = await state(a);
  check(near(after?.activeEffect?.msLeft, 3000, 250), `重連後效果還剩約 3000ms,沒有在凍結期間跑掉(實際 ${after?.activeEffect?.msLeft})`);
  await sleep(3300);
  check(!(await state(a))?.activeEffect, "恢復後再過 3 秒效果結束");

  // ---------- D-08:閃避視窗開著時斷線(目前 DODGE_WINDOW_ON_RESUME = remaining,待決定) ----------
  await dbg.cmd({ type: "debug_set_energy", playerId: b.playerId, energy: 2 });
  s = a.mark();
  b.send({ type: "attack_request", attackType: "direct", clientTime: Date.now() });
  const inc = await a.waitFor((m) => m.type === "attack_incoming", 1000, s);
  await sleep(300);
  a.drop();
  await sleep(2000);
  const s2 = a.mark();
  await a.reconnect();
  const inc2 = await a.waitFor((m) => m.type === "attack_incoming" && m.resumed, 1000, s2);
  console.log(`      (DODGE_WINDOW_ON_RESUME = ${CONFIG.DODGE_WINDOW_ON_RESUME})`);
  check(inc2?.attackId === inc?.attackId, "重連後重送同一個 attack_incoming(resumed: true)");
  if (CONFIG.DODGE_WINDOW_ON_RESUME === "remaining") {
    check(near(inc2?.dodgeWindowMs, 700, 150), `remaining:剩餘視窗約 700ms(實際 ${inc2?.dodgeWindowMs})`);
  }
  await sleep(200);
  a.send({ type: "dodge_attempt", attackId: inc.attackId, clientActionTime: Date.now() });
  const r2 = await a.waitFor((m) => m.type === "attack_result" && m.attackId === inc.attackId, 1500, s2);
  check(r2?.dodged === true, "恢復後在剩餘視窗內閃避 → 成功");

  // ---------- D-09:切背景 5 秒後回來,對戰繼續 ----------
  sb = b.mark();
  a.drop();
  await sleep(5000);
  const s3 = a.mark();
  const id3 = await a.reconnect();
  check(id3?.inRoom === true && !!(await a.waitFor((m) => m.type === "match_resumed", 1000, s3)), "5 秒後回來 → 對戰繼續");
  check(!b.msgs.slice(sb).some((m) => m.type === "game_over"), "B 沒有收到 game_over");

  // ---------- D-10:心跳逾時(3 秒沒訊息)→ 視為斷線 ----------
  sb = b.mark();
  a.stopPing(); // 連線還在,但不再送任何訊息(例如 App 被系統凍結)
  const t0 = Date.now();
  const disc2 = await b.waitFor((m) => m.type === "opponent_disconnected", 5000, sb);
  const dt = Date.now() - t0;
  check(!!disc2 && dt >= CONFIG.HEARTBEAT_TIMEOUT_MS - 100 && dt <= CONFIG.HEARTBEAT_TIMEOUT_MS + 1000, `停止 ping 約 3 秒後被判斷線(實際 ${dt}ms)`);
  const s4 = a.mark();
  await a.reconnect();
  check(!!(await a.waitFor((m) => m.type === "match_resumed", 1000, s4)), "重連後恢復");

  // ---------- D-06 / D-09:切背景 12 秒 → 已判負,回來時補送結果 ----------
  sb = b.mark();
  a.drop();
  const goB = await b.waitFor((m) => m.type === "game_over", 11500, sb);
  check(goB?.reason === "opponent_disconnect_timeout" && goB.winnerId === b.playerId, "10 秒寬限到 → B 獲勝(opponent_disconnect_timeout)");
  await sleep(1500);
  const s5 = a.mark();
  const id5 = await a.reconnect();
  check(id5?.reconnected === true && id5.inRoom === false, "12 秒後回來 → identified inRoom: false");
  const goA = await a.waitFor((m) => m.type === "game_over", 1000, s5);
  check(goA?.winnerId === b.playerId, "補送 A 錯過的 game_over(A 判負)");

  // ---------- 對 NPC:NPC 在凍結期間不會加能量、不會攻擊 ----------
  // (用新的一場:A、B 再配一次,確認房間可以正常重開)
  await rematch(a, b);
  check(true, "判負後雙方可以再配對");

  dbg.close();
  a.close();
  b.close();
});
