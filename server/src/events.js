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
  // cause: "wall" | "self" | "obstacle", headPos: 撞上的那一格(新蛇頭座標),bodyCells: 移動前的完整蛇身佔用座標(含頭,index 0 為頭)
  // 伺服器用這三個欄位做碰撞驗證,見 room.js validateDeathReport()
  DEATH_REPORT: "death_report",
  SNAKE_POSITION_UPDATE: "snake_position_update", // 每1秒回報一次自己的蛇身座標(伺服器內部用)
  ATTACK_REQUEST: "attack_request",
  DODGE_ATTEMPT: "dodge_attempt",
  LEAVE_ROOM: "leave_room",
};

export const S2C = {
  // Server -> Client
  IDENTIFIED: "identified", // { playerId, record: { wins, losses, draws }, recoveryCode?(新帳號), reconnected?, inRoom? }
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
  OBSTACLE_LAYOUT: "obstacle_layout", // 房間建立時一次性推送該玩家從固定地圖池抽到的整包地圖資料({ map }),只給該玩家自己,雙方各自獨立不同步
  ENERGY_UPDATE: "energy_update",
  ATTACK_INCOMING: "attack_incoming",
  ATTACK_REJECTED: "attack_rejected",
  ATTACK_RESULT: "attack_result",
  SELF_PAUSED_BY_SPAM: "self_paused_by_spam",
  DEATH_REPORT_REJECTED: "death_report_rejected", // 回報的座標經伺服器驗證不成立(碰撞對不上),死亡不算數
  OPPONENT_POSITION_FUZZY: "opponent_position_fuzzy", // 模糊小地圖用,每2秒推播一次
  OPPONENT_DISCONNECTED: "opponent_disconnected",
  OPPONENT_RECONNECTED: "opponent_reconnected",
  MATCH_RESUMED: "match_resumed", // 斷線方重連後,同一則訊息同時送給雙方:{ pausedMs, serverTime },雙方從凍結處同時恢復
  // { reason, winnerId, draw, stats: { [playerId]: { gems, survivalMs, maxLength } } }
  // stats 給結算畫面用:gems 本場吃到的寶石數、survivalMs 存活時間(不含開局倒數與斷線凍結)、
  // maxLength 回報過的最長蛇身格數(NPC 沒有蛇身、或還沒回報過蛇身時為 null)、
  // record 記入這場後的累計戰績 { wins, losses, draws }(NPC 為 null)
  GAME_OVER: "game_over",
  ERROR: "error",
};

// 隨機效果種類
export const EFFECTS = ["speedup", "pause", "blind"];

// 數值常數(對應規格文件)
export const CONFIG = {
  ENERGY_CAP: 10,              // 效果計算封頂值
  DODGE_WINDOW_MS: 1000,       // 閃躲視窗
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
  HEARTBEAT_TIMEOUT_MS: 5000, // 已 identify 的連線超過這麼久沒收到任何訊息(client 每秒 ping)就視為斷線,進入寬限期
  // (5 秒:容忍行動網路切換/短暫卡頓;Flutter 版沒有自動重連,太短會讓網路抖動變成判負)
  // 斷線當下閃避視窗還開著,恢復時怎麼處理:"remaining" 剩多少給多少 / "full" 重新給完整視窗 / "fail" 判閃躲失敗
  // 已決定用 "full":恢復時重送 attack_incoming 並重新給完整 1 秒(斷線方沒看到的那段不算,也不用 client 精準暫停本地警示計時)
  DODGE_WINDOW_ON_RESUME: "full",
  MAP_WIDTH: 12,  // 直向手機比例地圖,12欄(x軸),需與地圖池每張地圖的 gridCols 一致
  MAP_HEIGHT: 24, // 24列(y軸),需與地圖池每張地圖的 gridRows 一致
  SNAKE_POSITION_SYNC_MS: 1000, // 玩家回報蛇身座標的頻率(伺服器內部使用,不轉發完整座標給對手)
  MINIMAP_BROADCAST_MS: 2000,   // 模糊小地圖推播頻率
  MINIMAP_NOISE_RANGE: 2,       // 小地圖座標誤差範圍(±N格的隨機雜訊)
  PRE_GAME_COUNTDOWN_MS: 3000,  // client 收到 match_found 後的開局倒數(伺服器不等倒數,只在算結算的存活時間時扣掉)
};
