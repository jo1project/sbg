import { CONFIG } from "./events.js";

/**
 * 代表一位對戰中玩家的伺服器端權威狀態。
 * 注意:蛇身完整座標由客戶端自行模擬,伺服器只保存
 * 「權威判定」所需的最小狀態(能量、效果、閃躲計數)。
 */
export class Player {
  constructor(id, ws, { isNpc = false } = {}) {
    this.id = id;
    this.ws = ws;
    this.isNpc = isNpc;

    this.rttMs = 60; // 初始假設值,ping/pong後持續更新(滑動平均)
    this.connected = true;
    this.disconnectTimer = null;
    this.deviceInfo = "unknown"; // identify時客戶端回報,debug log排查特定廠牌連線問題用

    this.inQueue = false;               // 是否在隨機配對佇列中
    this.outgoingInvite = null;         // { targetId, timeoutTimer } 我方發出、尚未有結果的邀請
    this.incomingInvite = null;         // { fromId } 別人發給我、尚未回應的邀請

    this.resetForMatch();
  }

  // 同一個 WebSocket 連線(同一個 Player 物件)會被重複用在好幾場對戰,
  // 每次配對成功、Room建立時都要呼叫,否則上一場的死亡回報記錄/能量/效果會殘留,
  // 導致下一場真的死亡時 handleDeathReport 因 deathReportedAt 已經有值而被靜默忽略、
  // 玩家卡死在畫面上完全沒有 game_over(這是本次要修的bug)。
  resetForMatch() {
    this.energy = 0;
    this.activeEffect = null; // { type: 'pause'|'blind'|'speedup', endsAt: number }
    this.pendingAttack = null; // attackId 目前尚未結算的攻擊
    this.pendingIncomingAttack = null;
    this.dodgedAgainstMeCount = 0; // 對手閃躲我方攻擊的累計次數

    this.lastHeadPos = null; // 最近一次客戶端回報的蛇頭位置(用於吃食物驗證)
    this.snakeBody = []; // 最近一次回報的完整蛇身佔用座標(伺服器內部用,不轉發給對手)
    this.deathReportedAt = null;

    // 結算畫面的戰績(game_over.stats)
    this.gemsEaten = 0;
    this.maxLength = 0; // snake_position_update / death_report 回報過的最長蛇身格數
  }

  isBusy() {
    // 忙碌中的定義:正在對戰、正在排隊、有發出中的邀請、或已經有別人的邀請待處理
    return !!this.roomId || this.inQueue || !!this.outgoingInvite || !!this.incomingInvite;
  }

  send(type, payload = {}) {
    if (this.isNpc || !this.connected) return;
    try {
      this.ws.send(JSON.stringify({ type, ...payload }));
    } catch (err) {
      console.error(`[player ${this.id}] send failed`, err.message);
    }
  }

  updateRtt(sampleMs) {
    // 簡單滑動平均,避免單次抖動誤判
    this.rttMs = this.rttMs * 0.7 + sampleMs * 0.3;
  }

  hasActiveEffect() {
    return this.activeEffect && this.activeEffect.endsAt > Date.now();
  }

  isPaused() {
    return this.hasActiveEffect() && this.activeEffect.type === "pause";
  }

  effectiveEnergy() {
    return Math.min(this.energy, CONFIG.ENERGY_CAP);
  }

  clearExpiredEffect() {
    if (this.activeEffect && this.activeEffect.endsAt <= Date.now()) {
      this.activeEffect = null;
    }
  }
}
