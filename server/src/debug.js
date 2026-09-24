import { S2C, EFFECTS } from "./events.js";
import { NpcPlayer } from "./npc.js";

/**
 * 開發用除錯指令(手動測試規格用,見 godot/TEST_SCENARIOS.md)。
 *
 * 啟用條件(server.js 啟動時判斷,兩個都要成立):
 *   1. 環境變數 SBG_DEBUG_COMMANDS=1(預設沒設 = 關閉,必須刻意打開)
 *   2. NODE_ENV 不是 "production"(正式環境即使誤設 SBG_DEBUG_COMMANDS 也會拒絕並印錯誤)
 * 沒啟用時 server.js 根本不會 import 這個檔案,所有 debug_* 訊息都會當成未知訊息忽略。
 *
 * 除錯連線不需要先 identify(除錯面板不是玩家),指令用 playerId 指定要操作的玩家/房間。
 * 回應:{ type: "debug_ack", command, detail } 或 { type: "debug_error", command, message }
 */

export const DEBUG_ENV_FLAG = "SBG_DEBUG_COMMANDS";

export function isDebugEnabled(env = process.env) {
  return env[DEBUG_ENV_FLAG] === "1" && env.NODE_ENV !== "production";
}

const NPC_DODGE_MODES = ["always", "never", "default"];

export function createDebugHandler({ onlinePlayers, matchmaker }) {
  // 找玩家:線上真人在 onlinePlayers;NPC 不在裡面,要從房間找
  function findPlayer(playerId) {
    if (onlinePlayers.has(playerId)) return onlinePlayers.get(playerId);
    for (const room of matchmaker.rooms.values()) {
      if (room.players[playerId]) return room.players[playerId];
    }
    return null;
  }

  function roomOf(player) {
    return player?.roomId ? matchmaker.rooms.get(player.roomId) : null;
  }

  // 指定玩家所在房間裡的 NPC 對手
  function npcOpponentOf(player) {
    const room = roomOf(player);
    if (!room) return { error: "玩家不在房間裡" };
    const opp = room.other(player.id);
    if (!(opp instanceof NpcPlayer)) return { error: "對手不是 NPC" };
    return { room, npc: opp };
  }

  function describe(p, room) {
    return {
      playerId: p.id,
      isNpc: !!p.isNpc,
      connected: p.isNpc ? true : p.connected,
      roomId: p.roomId || null,
      opponentId: room ? room.other(p.id)?.id ?? null : null,
      energy: p.energy,
      activeEffect: p.hasActiveEffect() ? { type: p.activeEffect.type, msLeft: p.activeEffect.endsAt - Date.now() } : null,
      pendingAttack: p.pendingAttack ? p.pendingAttack.attackId : null,
      dodgedAgainstMeCount: p.dodgedAgainstMeCount,
      npcDodgeMode: p.isNpc ? p.debugDodgeMode || "default" : undefined,
      npcAutoAttack: p.isNpc ? !p.debugAutoAttackOff : undefined,
    };
  }

  const commands = {
    // 列出線上玩家與房間(含 NPC),除錯面板選目標用
    debug_list() {
      const players = [];
      const seen = new Set();
      for (const room of matchmaker.rooms.values()) {
        for (const id of room.playerIds) {
          players.push(describe(room.players[id], room));
          seen.add(id);
        }
      }
      for (const p of onlinePlayers.values()) {
        if (!seen.has(p.id)) players.push(describe(p, null));
      }
      const rooms = [...matchmaker.rooms.values()].map((r) => ({
        roomId: r.id,
        playerIds: r.playerIds,
        debugNextEffect: r.debugNextEffect || null,
      }));
      return { players, rooms };
    },

    // 強制指定下一次隨機效果攻擊的結果(該玩家所在房間,不論誰發動),用一次就清掉
    debug_force_next_effect(msg) {
      const player = findPlayer(msg.playerId);
      const room = roomOf(player);
      if (!room) throw new Error("找不到玩家或玩家不在房間裡");
      if (msg.effect !== null && !EFFECTS.includes(msg.effect)) {
        throw new Error(`effect 必須是 ${EFFECTS.join("/")} 或 null(取消)`);
      }
      room.debugNextEffect = msg.effect;
      return { roomId: room.id, debugNextEffect: room.debugNextEffect };
    },

    // 直接設定某位玩家(真人或 NPC)的權威能量,並照正常流程廣播 energy_update
    debug_set_energy(msg) {
      const player = findPlayer(msg.playerId);
      if (!player) throw new Error("找不到玩家");
      if (typeof msg.energy !== "number" || !Number.isFinite(msg.energy) || msg.energy < 0) {
        throw new Error("energy 必須是 >= 0 的數字");
      }
      player.energy = msg.energy;
      const payload = { playerId: player.id, energy: player.energy, serverTime: Date.now() };
      const room = roomOf(player);
      if (room) room.broadcast(S2C.ENERGY_UPDATE, payload);
      else player.send(S2C.ENERGY_UPDATE, payload);
      return { playerId: player.id, energy: player.energy };
    },

    // 讓該玩家的 NPC 對手在 delayMs 後發動 attackType 攻擊。
    // energy(選填):發動前先把 NPC 能量設成這個值(不然能量 0 會被 no_energy 擋掉)
    debug_npc_attack(msg, reply) {
      const { room, npc, error } = npcOpponentOf(findPlayer(msg.playerId));
      if (error) throw new Error(error);
      if (msg.attackType !== "direct" && msg.attackType !== "random") {
        throw new Error("attackType 必須是 direct 或 random");
      }
      const delayMs = Math.max(0, Number(msg.delayMs) || 0);
      setTimeout(() => {
        if (room.ended) return reply("debug_error", { command: "debug_npc_attack", message: "房間已結束" });
        if (typeof msg.energy === "number" && msg.energy >= 0) {
          npc.energy = msg.energy;
          room.broadcast(S2C.ENERGY_UPDATE, { playerId: npc.id, energy: npc.energy, serverTime: Date.now() });
        }
        // NPC 的 send 是空的,暫時攔下 attack_rejected 才能把原因回報給除錯面板
        let rejected = null;
        npc.send = (type, payload) => {
          if (type === S2C.ATTACK_REJECTED) rejected = payload.reason;
        };
        room.handleAttackRequest(npc.id, msg.attackType, Date.now());
        delete npc.send; // 恢復 NpcPlayer.prototype.send
        if (rejected) {
          reply("debug_error", { command: "debug_npc_attack", message: `攻擊被拒絕: ${rejected}` });
        } else {
          reply("debug_ack", {
            command: "debug_npc_attack",
            detail: { fired: true, attackId: npc.pendingAttack?.attackId ?? null, attackType: msg.attackType },
          });
        }
      }, delayMs);
      return { scheduledInMs: delayMs, npcId: npc.id };
    },

    // NPC 被攻擊時的閃躲:always = 永遠閃避、never = 永遠不閃避、default = 照規格 30%
    debug_npc_dodge(msg) {
      const { npc, error } = npcOpponentOf(findPlayer(msg.playerId));
      if (error) throw new Error(error);
      if (!NPC_DODGE_MODES.includes(msg.mode)) throw new Error(`mode 必須是 ${NPC_DODGE_MODES.join("/")}`);
      npc.debugDodgeMode = msg.mode === "default" ? null : msg.mode;
      return { npcId: npc.id, mode: msg.mode };
    },

    // 關掉/打開 NPC 的自動攻擊,讓手動測試的時序不被 NPC 自己亂打干擾
    debug_npc_auto_attack(msg) {
      const { npc, error } = npcOpponentOf(findPlayer(msg.playerId));
      if (error) throw new Error(error);
      npc.debugAutoAttackOff = msg.enabled === false;
      return { npcId: npc.id, autoAttack: !npc.debugAutoAttackOff };
    },
  };

  /** 回傳 true = 這是除錯指令且已處理 */
  function handle(msg, ws) {
    if (typeof msg?.type !== "string" || !msg.type.startsWith("debug_")) return false;
    const reply = (type, payload) => {
      try {
        ws.send(JSON.stringify({ type, ...payload }));
      } catch {
        // 除錯連線可能已經關了
      }
    };
    const fn = commands[msg.type];
    if (!fn) {
      reply("debug_error", { command: msg.type, message: "未知的除錯指令" });
      return true;
    }
    try {
      const detail = fn(msg, reply);
      reply("debug_ack", { command: msg.type, detail });
      console.log(`[debug] ${msg.type} ${JSON.stringify(msg)} -> ${JSON.stringify(detail)}`);
    } catch (err) {
      reply("debug_error", { command: msg.type, message: err.message });
    }
    return true;
  }

  return { handle, commands };
}
