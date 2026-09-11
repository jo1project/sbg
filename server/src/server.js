import { WebSocketServer } from "ws";
import { Player } from "./player.js";
import { Matchmaker } from "./matchmaking.js";
import { C2S, S2C, CONFIG } from "./events.js";
import { createPlayer, findPlayerById, findPlayerByRecoveryCode } from "./db.js";

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });
const matchmaker = new Matchmaker();

// 目前在線玩家: playerId -> Player (供好友ID配對查詢)
const onlinePlayers = new Map();
// ws -> playerId,方便斷線時反查
const wsToPlayerId = new Map();

function getRoom(player) {
  if (!player.roomId) return null;
  return matchmaker.rooms.get(player.roomId);
}

wss.on("connection", (ws) => {
  let player = null; // 需等待客戶端送出 identify 後才建立/綁定

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      return; // 忽略無法解析的訊息
    }

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

      player = new Player(playerId, ws);
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
        room.handleDeathReport(player.id);
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
