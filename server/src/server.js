import { WebSocketServer } from "ws";
import { Player } from "./player.js";
import { Matchmaker } from "./matchmaking.js";
import { C2S, S2C, CONFIG } from "./events.js";
import { createPlayer, findPlayerById, findPlayerByRecoveryCode, getRecord, recordMatchResult, getNickname, cleanNickname, setNickname, addFriends, getFriends } from "./db.js";

const PORT = process.env.PORT || 8080;
// 正式環境建議搭配 deploy/nginx.conf.example,由 Nginx 終止 wss:// 再轉給這裡的 ws://
// 這種部署下 Node 不需要對外開放,設 HOST=127.0.0.1 只接受本機的 Nginx 轉發
const HOST = process.env.HOST || "0.0.0.0";
const wss = new WebSocketServer({ port: PORT, host: HOST });
const matchmaker = new Matchmaker();
matchmaker.recordResult = recordMatchResult;
matchmaker.nicknameOf = getNickname;
// 兩位真人開房 = 對戰過 → 互相加好友(NPC 不記)
matchmaker.onRoomCreated = (room) => {
  const [a, b] = room.playerIds.map((id) => room.players[id]);
  if (!a.isNpc && !b.isNpc) addFriends(a.id, b.id);
};

// 目前在線玩家: playerId -> Player (供好友ID配對查詢)
const onlinePlayers = new Map();
// ws -> playerId,方便斷線時反查
const wsToPlayerId = new Map();

// 開發用除錯指令(見 debug.js):必須同時 SBG_DEBUG_COMMANDS=1 且 NODE_ENV 不是 production 才會載入,
// 沒啟用時 debug.js 完全不會被 import,debug_* 訊息一律當未知訊息忽略。
let debug = null;
if (process.env.SBG_DEBUG_COMMANDS === "1") {
  if (process.env.NODE_ENV === "production") {
    console.error("[debug] NODE_ENV=production,拒絕啟用除錯指令(SBG_DEBUG_COMMANDS 被忽略)");
  } else {
    const { createDebugHandler } = await import("./debug.js");
    debug = createDebugHandler({ onlinePlayers, matchmaker });
    console.warn("[debug] ⚠ 開發用除錯指令已啟用(SBG_DEBUG_COMMANDS=1),正式環境不可使用");
  }
}

function getRoom(player) {
  if (!player.roomId) return null;
  return matchmaker.rooms.get(player.roomId);
}

// 偵測「TCP連線已死但close事件從未觸發」的殭屍連線(手機網路突然中斷/APP被系統強制終止
// 等情況常見,尤其Android不像iOS會明快地讓socket斷開)。沒有這個心跳機制,player.roomId會
// 永遠卡住,之後配對/挑戰好友一律回busy——這正是「玩幾場後卡busy」問題的根本原因。
const HEARTBEAT_MS = 30000;
function heartbeat() {
  this.isAlive = true;
}
setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate(); // 觸發下面的 ws.on("close"),走既有的房間/佇列清理邏輯
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_MS);

// 應用層心跳:client 每 1 秒送 ping,已 identify 的連線超過 HEARTBEAT_TIMEOUT_MS(5 秒)沒收到任何訊息就當作斷線
// (直接 terminate,走下面 close 的寬限期流程)。上面 30 秒的 ws ping 只是兜底清掉還沒 identify 的殭屍連線。
setInterval(() => {
  const now = Date.now();
  for (const p of onlinePlayers.values()) {
    if (p.isNpc || !p.connected || !p.ws) continue;
    if (now - (p.lastSeenAt || now) > CONFIG.HEARTBEAT_TIMEOUT_MS) {
      console.log(`[heartbeat] ${p.id} ${now - p.lastSeenAt}ms 沒有訊息,視為斷線`);
      p.ws.terminate();
    }
  }
}, 500);

// 斷線寬限期內重連(或是舊連線其實已死、伺服器還沒發現就先收到新連線):把新的 ws 綁回原本的 Player,
// 保留能量/效果/房間狀態;房間裡所有真人都在線時恢復對局(match_resumed 同時送給雙方)。
// identify 的 mapSets(選填):只收字串陣列,其他一律當成只支援 classic
function parseMapSets(v) {
  return Array.isArray(v) && v.every((s) => typeof s === "string") ? v.slice(0, 8) : ["classic"];
}

function resumeConnection(existing, ws, deviceInfo, mapSets) {
  const oldWs = existing.ws;
  existing.ws = ws;
  existing.connected = true;
  existing.lastSeenAt = Date.now();
  existing.deviceInfo = deviceInfo || existing.deviceInfo;
  existing.mapSets = mapSets; // 只影響之後的新對局,進行中的房間地圖已經定了
  clearTimeout(existing.disconnectTimer);
  existing.disconnectTimer = null;
  wsToPlayerId.set(ws, existing.id);
  if (oldWs && oldWs !== ws) {
    wsToPlayerId.delete(oldWs);
    oldWs.terminate(); // 它的 close 事件會因為 player.ws 已經換掉而被忽略
  }

  const room = getRoom(existing);
  existing.send(S2C.IDENTIFIED, {
    playerId: existing.id,
    reconnected: true,
    inRoom: !!(room && !room.ended),
    record: getRecord(existing.id),
    nickname: getNickname(existing.id),
  });
  if (existing.missedGameOver) {
    // 寬限期已過、對局在斷線期間結束了:補送結果
    existing.send(S2C.GAME_OVER, existing.missedGameOver);
    existing.missedGameOver = null;
  }
  if (!room || room.ended) return existing;

  const opponent = room.other(existing.id);
  opponent.send(S2C.OPPONENT_RECONNECTED, {}); // 舊版 client(Flutter)靠這個解除凍結
  const allBack = room.playerIds.every((id) => room.players[id].isNpc || room.players[id].connected);
  if (allBack) room.resume();
  return existing;
}

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.on("pong", heartbeat);
  let player = null; // 需等待客戶端送出 identify 後才建立/綁定

  ws.on("message", (raw) => {
    if (player && player.ws === ws) player.lastSeenAt = Date.now();
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      return; // 忽略無法解析的訊息
    }

    // 除錯連線(除錯面板)不需要 identify
    if (debug && debug.handle(msg, ws)) return;

    // ---- 尚未 identify 前,只接受 identify / restore_account 訊息 ----
    if (!player) {
      if (msg.type === C2S.RESTORE_ACCOUNT) {
        const record = findPlayerByRecoveryCode(msg.recoveryCode);
        if (!record) {
          ws.send(JSON.stringify({ type: S2C.RESTORE_FAILED, reason: "recovery_code_not_found" }));
          return;
        }
        ws.send(JSON.stringify({ type: S2C.ACCOUNT_RESTORED, playerId: record.playerId }));
        // 前端收到後應接著送 identify(playerId: record.playerId)完成連線綁定
        return;
      }

      if (msg.type !== C2S.IDENTIFY) return;

      let record = null;
      if (msg.playerId) {
        record = findPlayerById(msg.playerId);
      }
      if (!record) {
        // 沒帶ID,或帶的ID在資料庫查無資料(裝置本地資料遺失等情況) -> 建立新玩家
        record = createPlayer();
      }

      const playerId = record.playerId;
      const existingConn = onlinePlayers.get(playerId);

      if (existingConn && (!existingConn.connected || getRoom(existingConn))) {
        // 寬限期內重連(含:舊連線在房間裡、伺服器還沒發現它已經斷了)
        player = resumeConnection(existingConn, ws, msg.deviceInfo, parseMapSets(msg.mapSets));
        return;
      }

      if (existingConn && existingConn.connected) {
        // TODO(debug): 查「玩幾場後卡busy配不到對戰」問題用,查到根因後移除。
        // 理論上舊連線的close事件應該已經觸發過,這裡卻還看到connected=true的舊entry,
        // 代表舊ws可能還沒真的關閉就建立了新連線,新Player會蓋掉舊的,舊的可能還卡在某個房間裡。
        console.log(
          `[busy] identify遇到還連著的舊entry player=${playerId} oldRoomId=${existingConn.roomId} ` +
            `oldInQueue=${existingConn.inQueue} device=${existingConn.deviceInfo}`
        );
      }

      player = new Player(playerId, ws);
      player.deviceInfo = msg.deviceInfo || "unknown";
      player.mapSets = parseMapSets(msg.mapSets);
      player.lastSeenAt = Date.now();
      onlinePlayers.set(playerId, player);
      wsToPlayerId.set(ws, playerId);

      const payload = { playerId, record: getRecord(playerId), nickname: getNickname(playerId) }; // record:累計戰績 { wins, losses, draws }(大廳顯示)
      // 只有「剛建立新帳號」的這次回應會附上還原碼,前端此時應提示玩家備份保存
      if (record.justCreated) payload.recoveryCode = record.recoveryCode;
      player.send(S2C.IDENTIFIED, payload);
      return;
    }

    switch (msg.type) {
      case C2S.PING: {
        const now = Date.now();
        player.send(S2C.PONG, { clientTime: msg.clientTime, serverTime: now });
        if (typeof msg.clientTime === "number") {
          // 粗略RTT估算:pong往返後由客戶端自行算更準,這裡先做一次伺服器端估計
          player.updateRtt(now - msg.clientTime);
        }
        break;
      }

      case C2S.JOIN_QUEUE:
        matchmaker.joinQueue(player);
        break;

      case C2S.CHALLENGE_FRIEND:
        matchmaker.challengeFriend(player, msg.targetPlayerId, onlinePlayers);
        break;

      case C2S.INVITE_ACCEPT:
        matchmaker.acceptInvite(player, onlinePlayers);
        break;

      case C2S.INVITE_REJECT:
        matchmaker.rejectInvite(player, onlinePlayers);
        break;

      case C2S.INVITE_CANCEL:
        matchmaker.cancelInvite(player, onlinePlayers);
        break;

      case C2S.FOOD_EATEN_REQUEST: {
        const room = getRoom(player);
        if (!room) break;
        room.handleFoodEaten(player.id, msg.foodId, msg.headPos);
        break;
      }

      case C2S.SNAKE_POSITION_UPDATE: {
        const room = getRoom(player);
        if (!room) break;
        room.handleSnakePositionUpdate(player.id, msg.headPos, msg.bodyCells);
        break;
      }

      case C2S.DEATH_REPORT: {
        const room = getRoom(player);
        if (!room) break;
        room.handleDeathReport(player.id, msg.cause, msg.headPos, msg.bodyCells);
        break;
      }

      case C2S.ATTACK_REQUEST: {
        const room = getRoom(player);
        if (!room) break;
        room.handleAttackRequest(player.id, msg.attackType, msg.clientTime);
        break;
      }

      case C2S.DODGE_ATTEMPT: {
        const room = getRoom(player);
        if (!room) break;
        room.handleDodgeAttempt(player.id, msg.attackId, msg.clientActionTime);
        break;
      }

      case C2S.SET_NICKNAME: {
        const nickname = cleanNickname(msg.nickname);
        if (!nickname) {
          player.send(S2C.ERROR, { reason: "invalid_nickname" });
          break;
        }
        setNickname(player.id, nickname);
        player.send(S2C.NICKNAME_UPDATED, { nickname });
        break;
      }

      case C2S.GET_RECOVERY_CODE:
        player.send(S2C.RECOVERY_CODE, { recoveryCode: findPlayerById(player.id)?.recoveryCode });
        break;

      case C2S.GET_FRIENDS:
        player.send(S2C.FRIENDS, {
          friends: getFriends(player.id).map((f) => ({ ...f, online: !!onlinePlayers.get(f.playerId)?.connected })),
        });
        break;

      case C2S.LEAVE_ROOM: {
        const room = getRoom(player);
        if (room) {
          room.endGame({ reason: "opponent_left", winnerId: room.other(player.id).id });
          matchmaker.removeRoom(room.id);
        }
        matchmaker.leaveQueue(player);
        break;
      }

      default:
        console.warn("未知訊息類型:", msg.type);
    }
  });

  ws.on("close", () => {
    if (!player) return;
    if (player.ws !== ws) return; // 已經被重連的新連線取代,這條舊連線關掉不影響狀態
    player.connected = false;
    matchmaker.leaveQueue(player);

    if (player.outgoingInvite) {
      const target = onlinePlayers.get(player.outgoingInvite.targetId);
      matchmaker.clearInviteState(player, target);
    }
    if (player.incomingInvite) {
      const fromPlayer = onlinePlayers.get(player.incomingInvite.fromId);
      matchmaker.clearInviteState(fromPlayer, player);
    }

    const room = getRoom(player);
    if (!room || room.ended) return;

    const opponent = room.other(player.id);
    // 10秒寬限期:整場對局凍結(所有對局計時暫停),雙方 client 都凍結自己的蛇,重連後由 match_resumed 同時恢復
    room.pause();
    opponent.send(S2C.OPPONENT_DISCONNECTED, { graceMs: CONFIG.RECONNECT_GRACE_MS });

    player.disconnectTimer = setTimeout(() => {
      if (player.connected) return; // 已重連
      room.endGame({ reason: "opponent_disconnect_timeout", winnerId: opponent.id });
      matchmaker.removeRoom(room.id);
    }, CONFIG.RECONNECT_GRACE_MS);
  });
});

console.log(`貪食蛇對戰伺服器已啟動,監聽埠號 ${PORT}`);
