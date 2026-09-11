import { Player } from "./player.js";

/**
 * 簡化版中等難度 NPC。
 * 目前僅實作「半隨機發動攻擊」的行為,移動/尋路邏輯留給前端
 * 或後續版本補完(NPC的蛇身移動可先由前端用固定/簡單邏輯模擬,
 * 伺服器端 NPC 物件主要負責攻擊決策與能量累積模擬)。
 */
export class NpcPlayer extends Player {
  constructor(id) {
    super(id, null, { isNpc: true });
    this.decisionInterval = null;
    // 每局隨機決定這次的「想打就打」門檻(5~10之間),模擬非固定滿量才出手
    this.attackEnergyThreshold = 5 + Math.floor(Math.random() * 6);
  }

  // 由 Room 建立房間後呼叫,開始定期做決策
  startBehavior(room) {
    // 模擬 NPC 吃食物累積能量(簡化:固定間隔隨機加能量)
    this.foodTimer = setInterval(() => {
      if (this.isPaused()) return;
      this.energy += 1;
      room.broadcast("energy_update", {
        playerId: this.id,
        energy: this.energy,
        serverTime: Date.now(),
      });
    }, 2000 + Math.random() * 1500); // 中等難度:約每2~3.5秒吃到一個食物

    // 能量達到隨機門檻(5~10)後才會出手,而非固定滿量,模擬中等難度的出手時機
    this.attackTimer = setInterval(() => {
      if (this.isPaused() || this.pendingAttack) return;
      if (this.energy < this.attackEnergyThreshold) return;
      const attackType = Math.random() < 0.5 ? "direct" : "random";
      room.handleAttackRequest(this.id, attackType, Date.now());
      // 出手後重新抽一次下次的門檻
      this.attackEnergyThreshold = 5 + Math.floor(Math.random() * 6);
    }, 2500);
  }

  stopBehavior() {
    clearInterval(this.foodTimer);
    clearInterval(this.attackTimer);
  }

  send() {
    // NPC 不需要真的送出網路訊息
  }
}
