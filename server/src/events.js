// 所有 WebSocket 訊息的 type 常數,對應規格文件第7章的事件一覽

export const C2S = {
  // Client -> Server
  // 連線建立後回報自己的 playerId(沒有則視為新玩家)。選填 mapSets: 支援的地圖組,例如 ["classic","large"];
  // 沒帶 = 只支援 classic(Flutter)。雙方都支援 "large" 才會配到大地圖,見 room.js constructor
  IDENTIFY: "identify",
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
  SET_NICKNAME: "set_nickname",           // { nickname } 1～12 字,成功回 nickname_updated,不合格回 error { reason: "invalid_nickname" }
  GET_RECOVERY_CODE: "get_recovery_code", // 設定頁「顯示繼承碼」用,回 recovery_code
  GET_FRIENDS: "get_friends",             // 好友清單(對戰過的真人),回 friends
};

export const S2C = {
  // Server -> Client
  IDENTIFIED: "identified", // { playerId, record: { wins, losses, draws }, nickname(沒設過是 null), recoveryCode?(新帳號), reconnected?, inRoom? }
  ACCOUNT_RESTORED: "account_restored",
  RESTORE_FAILED: "restore_failed",
  MATCH_FOUND: "match_found",
  MATCH_WAITING: "match_waiting",
  INVITE_RECEIVED: "invite_received",     // 收到別人的邀請 { fromPlayerId, fromNickname(null = 沒設) }
  INVITE_SENT: "invite_sent",             // 通知發起方邀請已送出、進入等待中
  INVITE_FAILED: "invite_failed",         // 對方不在線/忙碌中
  INVITE_REJECTED: "invite_rejected",     // 對方拒絕
  INVITE_TIMEOUT: "invite_timeout",       // 30秒逾時未回應
  INVITE_CANCELLED: "invite_cancelled",   // 發起方自己取消(通知對方邀請已撤回)
  PONG: "pong",
  FOOD_SPAWNED: "food_spawned",
  // 房間建立時一次性推送該玩家的整包地圖資料({ map }),只給該玩家自己。classic 雙方各自抽(可能不同),large 雙方同一張(規格2.3)
  OBSTACLE_LAYOUT: "obstacle_layout",
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
  NICKNAME_UPDATED: "nickname_updated", // { nickname }
  RECOVERY_CODE: "recovery_code",       // { recoveryCode }
  FRIENDS: "friends",                   // { friends: [{ playerId, nickname(null = 沒設), online }] },最近對戰的在前面
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
  FOOD_COUNT: 3,               // classic 地圖的恆定寶石數;大地圖用地圖 JSON 的 gemCount(依地板格數算,見 tools/gen_large_map.mjs)
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
  // classic 地圖尺寸(直向手機比例 12欄x24列,需與 classic 地圖池每張地圖的 gridCols/gridRows 一致)。
  // 伺服器判定都用各地圖自己的 gridCols/gridRows,這兩個只當小地圖雜訊的縮放基準
  MAP_WIDTH: 12,
  MAP_HEIGHT: 24,
  SNAKE_POSITION_SYNC_MS: 1000, // 玩家回報蛇身座標的頻率(伺服器內部使用,不轉發完整座標給對手)
  MINIMAP_BROADCAST_MS: 2000,   // 模糊小地圖推播頻率
  MINIMAP_NOISE_RANGE: 2,       // 小地圖座標誤差範圍(±N格的隨機雜訊),以 12x24 為準,大地圖依寬高等比放大
  PRE_GAME_COUNTDOWN_MS: 3000,
  // NPC 模擬吃寶石的間隔 [最短, 最長](ms),依地圖組分開。大地圖寶石密度跟小地圖一樣,但牆和走廊要繞路,先抓慢一點;
  // 之後用真人大地圖對局的 game_over.stats(gems / survivalMs)校正
  NPC_FOOD_INTERVAL_MS: { classic: [2000, 3500], large: [2500, 4500] },  // client 收到 match_found 後的開局倒數(伺服器不等倒數,只在算結算的存活時間時扣掉)
};
