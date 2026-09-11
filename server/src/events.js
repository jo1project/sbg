// 所有 WebSocket 訊息的 type 常數,對應規格文件第7章的事件一覽

export const C2S = {
  // Client -> Server
  IDENTIFY: "identify",               // 連線建立後回報自己的 playerId(沒有則視為新玩家)
  RESTORE_ACCOUNT: "restore_account", // 用還原碼找回帳號
  JOIN_QUEUE: "join_queue",           // 加入隨機配對佇列
  CHALLENGE_FRIEND: "challenge_friend", // 輸入好友ID發出邀請
  INVITE_ACCEPT: "invite_accept",
  INVITE_REJECT: "invite_reject",
  INVITE_CANCEL: "invite_cancel",
  PING: "ping",
  FOOD_EATEN_REQUEST: "food_eaten_request",
  // cause: "wall" | "self", headPos: 死亡當下蛇頭座標,bodyCells: 死亡當下蛇身佔用座標(不含頭)
  // 伺服器用這三個欄位做碰撞驗證,見 room.js validateDeathReport()
  DEATH_REPORT: "death_report",
  SNAKE_POSITION_UPDATE: "snake_position_update", // 每1秒回報一次自己的蛇身座標(伺服器內部用)
  ATTACK_REQUEST: "attack_request",
  DODGE_ATTEMPT: "dodge_attempt",
  LEAVE_ROOM: "leave_room",
};

export const S2C = {
  // Server -> Client
  IDENTIFIED: "identified",
  ACCOUNT_RESTORED: "account_restored",
  RESTORE_FAILED: "restore_failed",
  MATCH_FOUND: "match_found",
  MATCH_WAITING: "match_waiting",
  INVITE_RECEIVED: "invite_received",     // 收到別人的邀請
  INVITE_SENT: "invite_sent",             // 通知發起方邀請已送出、進入等待中
  INVITE_FAILED: "invite_failed",         // 對方不在線/忙碌中
  INVITE_REJECTED: "invite_rejected",     // 對方拒絕
  INVITE_TIMEOUT: "invite_timeout",       // 30秒逾時未回應
  INVITE_CANCELLED: "invite_cancelled",   // 發起方自己取消(通知對方邀請已撤回)
  PONG: "pong",
  FOOD_SPAWNED: "food_spawned",
  ENERGY_UPDATE: "energy_update",
  ATTACK_INCOMING: "attack_incoming",
  ATTACK_REJECTED: "attack_rejected",
  ATTACK_RESULT: "attack_result",
  SELF_PAUSED_BY_SPAM: "self_paused_by_spam",
  DEATH_REPORT_REJECTED: "death_report_rejected", // 回報的座標經伺服器驗證不成立(碰撞對不上),死亡不算數
  OPPONENT_POSITION_FUZZY: "opponent_position_fuzzy", // 模糊小地圖用,每2秒推播一次
  OPPONENT_DISCONNECTED: "opponent_disconnected",
  OPPONENT_RECONNECTED: "opponent_reconnected",
  GAME_OVER: "game_over",
  ERROR: "error",
};

// 隨機效果種類
export const EFFECTS = ["speedup", "pause", "blind"];

// 數值常數(對應規格文件)
export const CONFIG = {
  ENERGY_CAP: 10,              // 效果計算封頂值
  DODGE_WINDOW_MS: 300,        // 閃躲視窗
  PREVIEW_DELAY_MS: 1000,      // 閃躲失敗後的預告/攻擊動畫時間
  SPAM_PAUSE_THRESHOLD: 3,     // 連續被閃躲N次後反噬
  SPAM_PAUSE_DURATION_MS: 3000,
  PAUSE_EFFECT_CAP_MS: 3000,   // 暫停效果的獨立持續時間上限(即使能量計算超過也封頂3秒)
  FOOD_COUNT: 3,
  NPC_DODGE_SUCCESS_RATE: 0.3, // 中等難度NPC被攻擊時的閃躲成功率
  DOUBLE_KO_WINDOW_MS: 200, // 雙方死亡回報時間差在此範圍內視為Double KO
  MATCH_WAIT_BEFORE_NPC_MS: 8000, // 隨機配對等待真人的時間
  INVITE_TIMEOUT_MS: 30000,       // 好友邀請有效期限
  RECONNECT_GRACE_MS: 10000,
  MAP_SIZE: 20, // 假設地圖為 20x20 格,實際依前端棋盤調整
  SNAKE_POSITION_SYNC_MS: 1000, // 玩家回報蛇身座標的頻率(伺服器內部使用,不轉發完整座標給對手)
  MINIMAP_BROADCAST_MS: 2000,   // 模糊小地圖推播頻率
  MINIMAP_NOISE_RANGE: 2,       // 小地圖座標誤差範圍(±N格的隨機雜訊)
};
