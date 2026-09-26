// M-04 / M-11(好友):跟真人對戰過 → 互相出現在 get_friends;NPC 不會;用好友 ID 送邀請、對方收到帶暱稱的邀請、接受後開房
// 單獨執行:node test/m_friends.mjs(沒設 SERVER_URL 會自己起測試伺服器;NPC 那段要等 8 秒)
import { runStandalone, matchPair, check, sleep, TestClient } from "./lib.mjs";

async function friendsOf(c) {
  const s = c.mark();
  c.send({ type: "get_friends" });
  return (await c.waitFor((m) => m.type === "friends", 2000, s))?.friends;
}

await runStandalone("M 好友", async (url) => {
  const { a, b } = await matchPair(url);
  const fa = await friendsOf(a);
  const fb = await friendsOf(b);
  check(fa?.length === 1 && fa[0].playerId === b.playerId && fa[0].online === true, "對戰過 → A 的好友有 B(在線)");
  check(fb?.length === 1 && fb[0].playerId === a.playerId, "B 的好友也有 A");

  // 結束這場,改用好友 ID 邀請
  a.send({ type: "leave_room" });
  await a.waitFor((m) => m.type === "game_over", 2000);
  a.send({ type: "set_nickname", nickname: "阿蛇" });
  await a.waitFor((m) => m.type === "nickname_updated", 2000);
  let sb = b.mark();
  a.send({ type: "challenge_friend", targetPlayerId: b.playerId });
  const inv = await b.waitFor((m) => m.type === "invite_received", 2000, sb);
  check(inv?.fromPlayerId === a.playerId && inv?.fromNickname === "阿蛇", `B 收到邀請,帶 A 的暱稱(${inv?.fromNickname})`);
  sb = b.mark();
  const sa = a.mark();
  b.send({ type: "invite_accept" });
  const ma = await a.waitFor((m) => m.type === "match_found", 2000, sa);
  check(ma?.opponentId === b.playerId && !!(await b.waitFor((m) => m.type === "match_found", 2000, sb)), "B 接受 → 雙方開房");
  check((await friendsOf(a))?.length === 1, "再打一次不會重複加");
  b.close();
  await sleep(300);
  // B 斷線(寬限期中)不算在線;等 A 那邊的房間結束再測 NPC
  a.send({ type: "leave_room" });
  await a.waitFor((m) => m.type === "game_over", 2000, sa);

  // 沒人一起排 → 8 秒後配 NPC,NPC 不會變成好友
  const c = new TestClient(url, "C");
  await c.connect();
  c.send({ type: "join_queue" });
  const mc = await c.waitFor((m) => m.type === "match_found", 10000);
  check(!!mc, "C 配到 NPC");
  const fc = await friendsOf(c);
  check(Array.isArray(fc) && fc.length === 0, `NPC 不會出現在好友(實際 ${JSON.stringify(fc)})`);
  c.close();
  a.close();
});
