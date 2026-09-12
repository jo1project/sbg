// 對應 server/src/events.js 的 CONFIG,數值必須跟伺服器一致。
class GameConfig {
  static const serverUrl = "wss://my1st123.pp.ua/snake";
  static const mapSize = 20;
  static const dodgeWindowMs = 300;
  static const previewDelayMs = 1000;
  static const energyCap = 10;
  static const initialSnakeLength = 4;
  static const moveTickMs = 200; // 一般移動速度(格/次),非規格明定數值,先估計
  static const speedupTickMs = 110; // 加速效果下的移動間隔
}

// C2S / S2C 事件名稱字串,對應 server/src/events.js
class Ev {
  // Client -> Server
  static const identify = "identify";
  static const restoreAccount = "restore_account";
  static const joinQueue = "join_queue";
  static const challengeFriend = "challenge_friend";
  static const inviteAccept = "invite_accept";
  static const inviteReject = "invite_reject";
  static const inviteCancel = "invite_cancel";
  static const ping = "ping";
  static const foodEatenRequest = "food_eaten_request";
  static const deathReport = "death_report";
  static const snakePositionUpdate = "snake_position_update";
  static const attackRequest = "attack_request";
  static const dodgeAttempt = "dodge_attempt";
  static const leaveRoom = "leave_room";

  // Server -> Client
  static const identified = "identified";
  static const accountRestored = "account_restored";
  static const restoreFailed = "restore_failed";
  static const matchFound = "match_found";
  static const matchWaiting = "match_waiting";
  static const inviteReceived = "invite_received";
  static const inviteSent = "invite_sent";
  static const inviteFailed = "invite_failed";
  static const inviteRejected = "invite_rejected";
  static const inviteTimeout = "invite_timeout";
  static const inviteCancelled = "invite_cancelled";
  static const pong = "pong";
  static const foodSpawned = "food_spawned";
  static const energyUpdate = "energy_update";
  static const attackIncoming = "attack_incoming";
  static const attackRejected = "attack_rejected";
  static const attackResult = "attack_result";
  static const selfPausedBySpam = "self_paused_by_spam";
  static const deathReportRejected = "death_report_rejected";
  static const opponentPositionFuzzy = "opponent_position_fuzzy";
  static const opponentDisconnected = "opponent_disconnected";
  static const opponentReconnected = "opponent_reconnected";
  static const gameOver = "game_over";
  static const error = "error";
}
