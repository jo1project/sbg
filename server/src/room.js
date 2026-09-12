import { nanoid } from "nanoid";
import { S2C, EFFECTS, CONFIG } from "./events.js";

/**
 * 一場 1v1 對戰房間。
 * 房間生命週期短(對戰結束即銷毀),用記憶體管理即可,不需持久化。
 */
export class Room {
  constructor(id, playerA, playerB) {
    this.id = id;
    this.players = { [playerA.id]: playerA, [playerB.id]: playerB };
    this.playerIds = [playerA.id, playerB.id];

    // 模式B:雙方地圖各自獨立,食物也各玩各的,不共用同一份清單
    this.foods = { [playerA.id]: new Map(), [playerB.id]: new Map() };
    this.obstacles = { [playerA.id]: [], [playerB.id]: [] }; // 同樣各自獨立,見規格2.3節
    this.ended = false;
    this.onEnded = null; // 由外部(matchmaking.js)注入,對戰結束時通知移除房間

    this.spawnInitialObstacles(); // 須在食物生成之前,讓食物避開障礙物座標
    this.spawnInitialFoods();
    this.startMinimapBroadcast();
  }

  other(playerId) {
    const otherId = this.playerIds.find((id) => id !== playerId);
    return this.players[otherId];
  }

  broadcast(type, payload = {}, excludeId = null) {
    for (const id of this.playerIds) {
      if (id === excludeId) continue;
      this.players[id].send(type, payload);
    }
  }

  // ---------- 障礙物(靜態,整局不變動,見規格2.3節) ----------

  spawnInitialObstacles() {
    // 蛇初始重生座標(對應client端 GameController._startMatch 的起始位置),障礙物需避開
    const startX = Math.floor(CONFIG.MAP_SIZE / 2);
    const startY = Math.floor(CONFIG.MAP_SIZE / 2);
    const spawnCells = [];
    for (let i = 0; i < CONFIG.INITIAL_SNAKE_LENGTH; i++) spawnCells.push({ x: startX - i, y: startY });

    for (const playerId of this.playerIds) {
      const list = this.obstacles[playerId];
      for (let i = 0; i < CONFIG.OBSTACLE_COUNT; i++) {
        let pos;
        let attempts = 0;
        do {
          pos = {
            x: Math.floor(Math.random() * CONFIG.MAP_SIZE),
            y: Math.floor(Math.random() * CONFIG.MAP_SIZE),
          };
          attempts++;
        } while (
          attempts < 50 &&
          (spawnCells.some((c) => c.x === pos.x && c.y === pos.y) || list.some((o) => o.x === pos.x && o.y === pos.y))
        );
        list.push(pos);
      }
      this.players[playerId].send(S2C.OBSTACLE_LAYOUT, { obstacles: list });
    }
  }

  // ---------- 食物 ----------

  spawnInitialFoods() {
    for (const playerId of this.playerIds) {
      for (let i = 0; i < CONFIG.FOOD_COUNT; i++) this.spawnFood(playerId);
    }
  }

  spawnFood(playerId) {
    const player = this.players[playerId];
    const myFoods = this.foods[playerId];
    const foodId = `f_${nanoid(8)}`;

    const myObstacles = this.obstacles[playerId] || [];
    const occupied = (pos) => {
      if ([...myFoods.values()].some((f) => f.x === pos.x && f.y === pos.y)) return true;
      if (player.snakeBody && player.snakeBody.some((c) => c.x === pos.x && c.y === pos.y)) return true;
      if (myObstacles.some((o) => o.x === pos.x && o.y === pos.y)) return true;
      return false;
    };

    let pos;
    let attempts = 0;
    do {
      pos = {
        x: Math.floor(Math.random() * CONFIG.MAP_SIZE),
        y: Math.floor(Math.random() * CONFIG.MAP_SIZE),
      };
      attempts++;
    } while (occupied(pos) && attempts < 50); // 避免蛇身佔滿地圖時無窮迴圈

    myFoods.set(foodId, pos);
    player.send(S2C.FOOD_SPAWNED, { foodId, position: pos });
    return foodId;
  }

  handleFoodEaten(playerId, foodId, headPos) {
    const player = this.players[playerId];
    const myFoods = this.foods[playerId];
    const food = myFoods.get(foodId);
    if (!player || !food) return; // 食物已被吃過或不存在,忽略

    // 基本驗證:蛇頭需與食物座標重疊,避免造假回報
    if (!headPos || headPos.x !== food.x || headPos.y !== food.y) {
      console.warn(`[room ${this.id}] food_eaten_request 位置不符,忽略 (player ${playerId})`);
      return;
    }

    myFoods.delete(foodId);
    player.lastHeadPos = headPos;
    player.energy += 1;

    // 能量條給雙方看(對戰互動用),但食物本身只通知該玩家自己
    this.broadcast(S2C.ENERGY_UPDATE, {
      playerId,
      energy: player.energy,
      serverTime: Date.now(),
    });

    this.spawnFood(playerId); // 補回恆定3個(僅該玩家的棋盤)
  }

  // ---------- 蛇身座標同步(伺服器內部用,不轉發完整座標給對手) ----------

  handleSnakePositionUpdate(playerId, headPos, bodyCells) {
    const player = this.players[playerId];
    if (!player) return;
    player.lastHeadPos = headPos;
    player.snakeBody = Array.isArray(bodyCells) ? bodyCells : [];
  }

  startMinimapBroadcast() {
    this.minimapTimer = setInterval(() => {
      if (this.ended) return clearInterval(this.minimapTimer);
      for (const playerId of this.playerIds) {
        const player = this.players[playerId];
        const opponent = this.other(playerId);
        if (!player.lastHeadPos) continue;

        const noise = CONFIG.MINIMAP_NOISE_RANGE;
        const fuzzyPos = {
          x: player.lastHeadPos.x + Math.floor((Math.random() * 2 - 1) * noise),
          y: player.lastHeadPos.y + Math.floor((Math.random() * 2 - 1) * noise),
        };
        opponent.send(S2C.OPPONENT_POSITION_FUZZY, { position: fuzzyPos });
      }
    }, CONFIG.MINIMAP_BROADCAST_MS);
  }

  // ---------- 攻擊 ----------

  handleAttackRequest(attackerId, attackType, clientTime) {
    const attacker = this.players[attackerId];
    const target = this.other(attackerId);
    attacker.clearExpiredEffect();
    target.clearExpiredEffect();

    // 檢查順序見規格文件 4.3
    if (attacker.isPaused()) {
      return attacker.send(S2C.ATTACK_REJECTED, { reason: "attacker_paused" });
    }
    if (attacker.pendingAttack) {
      return attacker.send(S2C.ATTACK_REJECTED, { reason: "attack_in_progress" });
    }
    if (target.hasActiveEffect()) {
      return attacker.send(S2C.ATTACK_REJECTED, { reason: "target_effect_active" });
    }

    const effectValue = attacker.effectiveEnergy(); // min(energy, 10)
    if (effectValue <= 0) {
      return attacker.send(S2C.ATTACK_REJECTED, { reason: "no_energy" });
    }

    attacker.energy -= effectValue; // 乙案:扣封頂值,餘額保留
    const attackId = `atk_${nanoid(8)}`;

    // random 類型先擲骰決定效果,但先不揭露給任一方
    let rolledEffect = null;
    if (attackType === "random") {
      rolledEffect = EFFECTS[Math.floor(Math.random() * EFFECTS.length)];
    }

    attacker.pendingAttack = {
      attackId,
      attackType,
      effectValue,
      rolledEffect,
      targetId: target.id,
      serverAttackTime: Date.now(),
      resolved: false,
    };
    target.pendingIncomingAttack = attacker.pendingAttack;

    this.broadcast(S2C.ATTACK_INCOMING, {
      attackId,
      attackType,
      attackerId,
      attackerEnergyUsed: effectValue,
      serverAttackTime: attacker.pendingAttack.serverAttackTime,
      dodgeWindowMs: CONFIG.DODGE_WINDOW_MS,
    });

    this.broadcast(S2C.ENERGY_UPDATE, {
      playerId: attackerId,
      energy: attacker.energy,
      serverTime: Date.now(),
    });

    // 若目標是NPC,由伺服器直接依中等難度閃躲成功率模擬決策,
    // 不需等待(NPC沒有真人的0.3秒反應延遲,但仍受機率限制)
    if (target.isNpc) {
      const dodged = Math.random() < CONFIG.NPC_DODGE_SUCCESS_RATE;
      setTimeout(() => {
        this.resolveAttack(attacker, target, attackId, { dodged });
      }, 100 + Math.random() * 150); // 模擬反應延遲,避免瞬間判定顯得不自然
      return;
    }

    // 若對方在視窗內沒有送 dodge_attempt,逾時自動判定失敗
    setTimeout(() => {
      this.resolveAttack(attacker, target, attackId, { dodged: false, timedOut: true });
    }, CONFIG.DODGE_WINDOW_MS + target.rttMs / 2 + 50); // 額外緩衝給網路延遲
  }

  handleDodgeAttempt(defenderId, attackId, clientActionTime) {
    const defender = this.players[defenderId];
    const attack = defender.pendingIncomingAttack;
    if (!attack || attack.attackId !== attackId || attack.resolved) return;

    const attacker = this.players[this.playerIds.find((id) => id !== defenderId)];

    // 用 RTT 校正操作實際發生時間,判定是否落在視窗內
    const estimatedServerActionTime = clientActionTime + defender.rttMs / 2;
    const windowStart = attack.serverAttackTime;
    const windowEnd = attack.serverAttackTime + CONFIG.DODGE_WINDOW_MS;
    const dodged = estimatedServerActionTime >= windowStart && estimatedServerActionTime <= windowEnd;

    this.resolveAttack(attacker, defender, attackId, { dodged });
  }

  resolveAttack(attacker, defender, attackId, { dodged, timedOut = false }) {
    const attack = attacker.pendingAttack;
    if (!attack || attack.attackId !== attackId || attack.resolved) return;
    attack.resolved = true;
    attacker.pendingAttack = null;
    defender.pendingIncomingAttack = null;

    if (dodged) {
      this.broadcast(S2C.ATTACK_RESULT, { attackId, dodged: true });
      this.registerDodgeSuccess(attacker.id, defender.id);
      return;
    }

    if (attack.attackType === "direct") {
      this.broadcast(S2C.ATTACK_RESULT, {
        attackId,
        dodged: false,
        effectType: "direct_lengthen",
        lengthenBy: attack.effectValue,
      });
    } else {
      let durationMs = attack.effectValue * 500; // energy x 0.5秒
      if (attack.rolledEffect === "pause") {
        durationMs = Math.min(durationMs, CONFIG.PAUSE_EFFECT_CAP_MS); // 暫停效果額外封頂3秒
      }
      this.broadcast(S2C.ATTACK_RESULT, {
        attackId,
        dodged: false,
        effectType: attack.rolledEffect,
        effectDuration: durationMs,
        previewDelayMs: CONFIG.PREVIEW_DELAY_MS,
      });

      // 效果延遲1秒後正式生效(對應前端的預告/攻擊動畫時間)
      setTimeout(() => {
        defender.activeEffect = {
          type: attack.rolledEffect,
          endsAt: Date.now() + durationMs,
        };
      }, CONFIG.PREVIEW_DELAY_MS);
    }
  }

  // 閃躲成功時呼叫,累加防守方的spam反制計數
  registerDodgeSuccess(attackerId, defenderId) {
    const attacker = this.players[attackerId];
    attacker.dodgedAgainstMeCount += 1;
    if (attacker.dodgedAgainstMeCount >= CONFIG.SPAM_PAUSE_THRESHOLD) {
      attacker.dodgedAgainstMeCount = 0;
      attacker.activeEffect = { type: "pause", endsAt: Date.now() + CONFIG.SPAM_PAUSE_DURATION_MS };
      attacker.send(S2C.SELF_PAUSED_BY_SPAM, { durationMs: CONFIG.SPAM_PAUSE_DURATION_MS });
    }
  }

  // ---------- 死亡判定(客戶端回報座標、伺服器驗證碰撞是否成立) ----------

  // 用死亡當下回報的座標做邏輯自洽驗證,不是重新模擬整場移動:
  // 撞牆用地圖邊界判斷(不受延遲影響,100%準確);撞自己則檢查蛇頭是否真的落在回報的蛇身格上;
  // 撞障礙物則比對該玩家自己的障礙物座標清單(room建立時生成,見 spawnInitialObstacles)。
  // 擋掉「完全沒碰撞卻回報死亡」的假造事件,細節見規格文件6.1節的取捨說明。
  validateDeathReport(playerId, cause, headPos, bodyCells) {
    if (!headPos || typeof headPos.x !== "number" || typeof headPos.y !== "number") return false;
    if (cause === "wall") {
      return headPos.x < 0 || headPos.x >= CONFIG.MAP_SIZE || headPos.y < 0 || headPos.y >= CONFIG.MAP_SIZE;
    }
    if (cause === "self") {
      return Array.isArray(bodyCells) && bodyCells.some((c) => c && c.x === headPos.x && c.y === headPos.y);
    }
    if (cause === "obstacle") {
      const list = this.obstacles[playerId] || [];
      return list.some((o) => o.x === headPos.x && o.y === headPos.y);
    }
    return false; // 未知死因,直接視為不合法
  }

  handleDeathReport(playerId, cause, headPos, bodyCells) {
    if (this.ended) return; // 已結束(可能另一方剛觸發了game_over),忽略重複回報
    const player = this.players[playerId];
    if (!player || player.deathReportedAt) return; // 避免同一人重複回報

    if (!this.validateDeathReport(playerId, cause, headPos, bodyCells)) {
      console.warn(`[room ${this.id}] death_report 碰撞驗證失敗,忽略 (player ${playerId}, cause=${cause})`);
      player.send(S2C.DEATH_REPORT_REJECTED, { reason: "collision_not_verified" });
      return;
    }

    const now = Date.now();
    player.deathReportedAt = now;

    const opponent = this.other(playerId);

    if (opponent.deathReportedAt) {
      // 對手也已回報死亡,檢查時間差是否落在 Double KO 窗口內
      const diff = Math.abs(now - opponent.deathReportedAt);
      if (diff <= CONFIG.DOUBLE_KO_WINDOW_MS) {
        this.endGame({ reason: "double_ko", winnerId: null, draw: true });
      } else {
        // 超過窗口,以先回報者(對手)為死亡在先 -> 對手判負,自己(後回報)也已死亡,
        // 但先回報者已經輸了,所以自己算贏
        this.endGame({ reason: "sequential_death", winnerId: playerId });
      }
      return;
    }

    // 只有這方回報死亡,先記錄,等待一小段時間看對手是否也在Double KO窗口內死亡
    // (避免對手其實也快死了,只是網路延遲晚一點點送達,誤判為單方死亡)
    setTimeout(() => {
      if (this.ended) return;
      if (opponent.deathReportedAt) return; // 期間對手也回報了,上面的分支會處理
      this.endGame({ reason: "single_death", winnerId: opponent.id });
    }, CONFIG.DOUBLE_KO_WINDOW_MS);
  }

  // ---------- 結束/斷線 ----------

  endGame(result) {
    if (this.ended) return;
    this.ended = true;
    clearInterval(this.minimapTimer);
    this.broadcast(S2C.GAME_OVER, result);
    // 清掉雙方的 roomId,否則 Player.isBusy() 會永遠判定為忙碌,再也配不到對戰
    for (const id of this.playerIds) {
      if (this.players[id].roomId === this.id) this.players[id].roomId = null;
    }
    this.onEnded?.();
  }
}
