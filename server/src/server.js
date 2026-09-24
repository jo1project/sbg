import { WebSocketServer } from "ws";
import { Player } from "./player.js";
import { Matchmaker } from "./matchmaking.js";
import { C2S, S2C, CONFIG } from "./events.js";
import { createPlayer, findPlayerById, findPlayerByRecoveryCode } from "./db.js";

const PORT = process.env.PORT || 8080;
// 正式環境建議搭配 deploy/nginx.conf.example,由 Nginx 終止 wss:// 再轉給這裡的 ws://
// 這種部署下 Node 不需要對外開放,設 HOST=127.0.0.1 只接受本機的 Nginx 轉發
const HOST = process.env.HOST || "0.0.0.0";
const wss = new WebSocketServer({ port: PORT, host: HOST });
const matchmaker = new Matchmaker();

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

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.on("pong", heartbeat);
  let player = null; // 需等待客戶端送出 identify 後才建立/綁定

  ws.on("message", (raw) => {
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

      if (existingConn && !existingConn.connected) {
        // 寬限期內重連:重新綁定 ws,保留原本的能量/effect/房間狀態
        existingConn.ws = ws;
        existingConn.connected = true;
        existingConn.deviceInfo = msg.deviceInfo || existingConn.deviceInfo;
        clearTimeout(existingConn.disconnectTimer);
        player = existingConn;
        wsToPlayerId.set(ws, playerId);
        player.send(S2C.IDENTIFIED, { playerId, reconnected: true });

        const room = getRoom(player);
        if (room) {
          const opponent = room.other(player.id);
          opponent.send(S2C.OPPONENT_RECONNECTED, {});
        }
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
      onlinePlayers.set(playerId, player);
      wsToPlayerId.set(ws, playerId);

      const payload = { playerId };
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
    opponent.send(S2C.OPPONENT_DISCONNECTED, { graceMs: CONFIG.RECONNECT_GRACE_MS });

    // 10秒寬限期:期間暫停判定(此skeleton先不強制凍結遊戲時鐘,
    // 實際上線前需搭配前端在收到 OPPONENT_DISCONNECTED 時暫停操作)
    player.disconnectTimer = setTimeout(() => {
      if (player.connected) return; // 已重連
      room.endGame({ reason: "opponent_disconnect_timeout", winnerId: opponent.id });
      matchmaker.removeRoom(room.id);
    }, CONFIG.RECONNECT_GRACE_MS);
  });
});

console.log(`貪食蛇對戰伺服器已啟動,監聽埠號 ${PORT}`);
