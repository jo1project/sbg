import { nanoid } from "nanoid";
import { Room } from "./room.js";
import { NpcPlayer } from "./npc.js";
import { S2C, CONFIG } from "./events.js";

export class Matchmaker {
  constructor() {
    this.queue = []; // 等待隨機配對的 Player[]
    this.pendingChallenges = new Map(); // targetPlayerId -> {fromPlayer, timeoutTimer}
    this.rooms = new Map(); // roomId -> Room
    this.onRoomCreated = null; // callback(room) 由外部(server.js)注入,方便挂 disconnect handler 等
  }

  // ---------- 隨機配對 ----------

  joinQueue(player) {
    if (player.isBusy()) {
      return player.send(S2C.INVITE_FAILED, { reason: "busy" }); // 理論上前端應先擋,這裡雙重保險
    }
    if (this.queue.includes(player)) return;
    this.queue.push(player);
    player.inQueue = true;
    player.send(S2C.MATCH_WAITING, {});

    // 立刻嘗試配對
    this.tryMatch();

    // 等待逾時後配 NPC(若這時已經配對成功,timer內會檢查是否還在queue)
    player.npcFallbackTimer = setTimeout(() => {
      const idx = this.queue.indexOf(player);
      if (idx === -1) return; // 已經配對成功,不用管
      this.queue.splice(idx, 1);
      player.inQueue = false;
      const npc = new NpcPlayer(`npc_${nanoid(6)}`);
      this.createRoom(player, npc);
    }, CONFIG.MATCH_WAIT_BEFORE_NPC_MS);
  }

  leaveQueue(player) {
    const idx = this.queue.indexOf(player);
    if (idx !== -1) this.queue.splice(idx, 1);
    player.inQueue = false;
    clearTimeout(player.npcFallbackTimer);
  }

  tryMatch() {
    while (this.queue.length >= 2) {
      const a = this.queue.shift();
      const b = this.queue.shift();
      a.inQueue = false;
      b.inQueue = false;
      clearTimeout(a.npcFallbackTimer);
      clearTimeout(b.npcFallbackTimer);
      this.createRoom(a, b);
    }
  }

  // ---------- 好友ID配對(需雙方都在線,含邀請/接受流程) ----------

  challengeFriend(fromPlayer, targetPlayerId, onlinePlayers) {
    if (fromPlayer.isBusy()) {
      return fromPlayer.send(S2C.INVITE_FAILED, { reason: "self_busy" });
    }
    const target = onlinePlayers.get(targetPlayerId);
    if (!target || !target.connected) {
      return fromPlayer.send(S2C.INVITE_FAILED, { reason: "target_offline", targetPlayerId });
    }
    if (target === fromPlayer) {
      return fromPlayer.send(S2C.INVITE_FAILED, { reason: "cannot_challenge_self" });
    }
    if (target.isBusy()) {
      return fromPlayer.send(S2C.INVITE_FAILED, { reason: "target_busy", targetPlayerId });
    }

    const timeoutTimer = setTimeout(() => {
      this.expireInvite(fromPlayer, target);
    }, CONFIG.INVITE_TIMEOUT_MS);

    fromPlayer.outgoingInvite = { targetId: target.id, timeoutTimer };
    target.incomingInvite = { fromId: fromPlayer.id };

    fromPlayer.send(S2C.INVITE_SENT, { targetPlayerId: target.id, timeoutMs: CONFIG.INVITE_TIMEOUT_MS });
    target.send(S2C.INVITE_RECEIVED, { fromPlayerId: fromPlayer.id });
  }

  acceptInvite(target, onlinePlayers) {
    const invite = target.incomingInvite;
    if (!invite) return;
    const fromPlayer = onlinePlayers.get(invite.fromId);
    this.clearInviteState(fromPlayer, target);
    if (!fromPlayer || !fromPlayer.connected) {
      return target.send(S2C.INVITE_FAILED, { reason: "inviter_offline" });
    }
    this.createRoom(fromPlayer, target);
  }

  rejectInvite(target, onlinePlayers) {
    const invite = target.incomingInvite;
    if (!invite) return;
    const fromPlayer = onlinePlayers.get(invite.fromId);
    this.clearInviteState(fromPlayer, target);
    if (fromPlayer) fromPlayer.send(S2C.INVITE_REJECTED, { targetPlayerId: target.id });
  }

  cancelInvite(fromPlayer, onlinePlayers) {
    const invite = fromPlayer.outgoingInvite;
    if (!invite) return;
    const target = onlinePlayers.get(invite.targetId);
    this.clearInviteState(fromPlayer, target);
    if (target) target.send(S2C.INVITE_CANCELLED, { fromPlayerId: fromPlayer.id });
  }

  expireInvite(fromPlayer, target) {
    if (!fromPlayer.outgoingInvite || fromPlayer.outgoingInvite.targetId !== target.id) return;
    this.clearInviteState(fromPlayer, target);
    fromPlayer.send(S2C.INVITE_TIMEOUT, { targetPlayerId: target.id });
    target.send(S2C.INVITE_TIMEOUT, { fromPlayerId: fromPlayer.id });
  }

  clearInviteState(fromPlayer, target) {
    if (fromPlayer && fromPlayer.outgoingInvite) {
      clearTimeout(fromPlayer.outgoingInvite.timeoutTimer);
      fromPlayer.outgoingInvite = null;
    }
    if (target) target.incomingInvite = null;
  }

  // ---------- 建立房間 ----------

  createRoom(playerA, playerB) {
    const roomId = `room_${nanoid(8)}`;
    const room = new Room(roomId, playerA, playerB);
    this.rooms.set(roomId, room);
    room.onEnded = () => this.removeRoom(roomId);

    playerA.roomId = roomId;
    playerB.roomId = roomId;

    playerA.send(S2C.MATCH_FOUND, { roomId, opponentId: playerB.id });
    playerB.send(S2C.MATCH_FOUND, { roomId, opponentId: playerA.id });

    if (playerB instanceof NpcPlayer) playerB.startBehavior(room);
    if (playerA instanceof NpcPlayer) playerA.startBehavior(room);

    if (this.onRoomCreated) this.onRoomCreated(room);
    return room;
  }

  removeRoom(roomId) {
    const room = this.rooms.get(roomId);
    if (!room) return;
    for (const id of room.playerIds) {
      const p = room.players[id];
      if (p instanceof NpcPlayer) p.stopBehavior();
    }
    this.rooms.delete(roomId);
  }
}
