import Database from "better-sqlite3";
import { customAlphabet } from "nanoid";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = process.env.DB_PATH || path.join(__dirname, "..", "data.sqlite");

const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS players (
    playerId TEXT PRIMARY KEY,
    recoveryCode TEXT UNIQUE NOT NULL,
    createdAt INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_recovery_code ON players(recoveryCode);
  -- 累計戰績(大廳顯示勝/敗):獨立一張表,舊資料庫啟動時自動建立,不用搬移 players
  CREATE TABLE IF NOT EXISTS player_records (
    playerId TEXT PRIMARY KEY,
    wins INTEGER NOT NULL DEFAULT 0,
    losses INTEGER NOT NULL DEFAULT 0,
    draws INTEGER NOT NULL DEFAULT 0
  );
  -- 好友:對戰過的真人(NPC 不記),雙向各一列,server.js 在開房時寫入
  CREATE TABLE IF NOT EXISTS friends (
    playerId TEXT NOT NULL,
    friendId TEXT NOT NULL,
    lastMatchedAt INTEGER NOT NULL,
    PRIMARY KEY (playerId, friendId)
  );
  -- 暱稱:同上,獨立一張表
  CREATE TABLE IF NOT EXISTS player_profiles (
    playerId TEXT PRIMARY KEY,
    nickname TEXT
  );
`);

// displayId: 英數混合短碼,避開容易混淆的字元(0/O, 1/I/l)
const displayIdAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const genDisplayId = customAlphabet(displayIdAlphabet, 6);

// recoveryCode: 更長、更隨機,格式類似 7f3a-9c2e-1b8d
const recoveryAlphabet = "0123456789abcdef";
const genRecoverySegment = customAlphabet(recoveryAlphabet, 4);
function genRecoveryCode() {
  return `${genRecoverySegment()}-${genRecoverySegment()}-${genRecoverySegment()}`;
}

export const FRIENDS_MAX = 50;

const stmts = {
  insert: db.prepare(
    "INSERT INTO players (playerId, recoveryCode, createdAt) VALUES (?, ?, ?)"
  ),
  byId: db.prepare("SELECT * FROM players WHERE playerId = ?"),
  byRecoveryCode: db.prepare("SELECT * FROM players WHERE recoveryCode = ?"),
  record: db.prepare("SELECT wins, losses, draws FROM player_records WHERE playerId = ?"),
  nickname: db.prepare("SELECT nickname FROM player_profiles WHERE playerId = ?"),
  setNickname: db.prepare(`
    INSERT INTO player_profiles (playerId, nickname) VALUES (?, ?)
    ON CONFLICT(playerId) DO UPDATE SET nickname = excluded.nickname
  `),
  addFriend: db.prepare(`
    INSERT INTO friends (playerId, friendId, lastMatchedAt) VALUES (?, ?, ?)
    ON CONFLICT(playerId, friendId) DO UPDATE SET lastMatchedAt = excluded.lastMatchedAt
  `),
  friends: db.prepare(`
    SELECT f.friendId AS playerId, p.nickname FROM friends f
    LEFT JOIN player_profiles p ON p.playerId = f.friendId
    WHERE f.playerId = ? ORDER BY f.lastMatchedAt DESC LIMIT ${FRIENDS_MAX}
  `),
  addResult: db.prepare(`
    INSERT INTO player_records (playerId, wins, losses, draws) VALUES (@playerId, @w, @l, @d)
    ON CONFLICT(playerId) DO UPDATE SET
      wins = wins + excluded.wins, losses = losses + excluded.losses, draws = draws + excluded.draws
  `),
};

/** 玩家的累計戰績 { wins, losses, draws },沒打過就是全 0 */
export function getRecord(playerId) {
  return stmts.record.get(playerId) || { wins: 0, losses: 0, draws: 0 };
}

/** 暱稱,沒設過是 null */
export function getNickname(playerId) {
  return stmts.nickname.get(playerId)?.nickname ?? null;
}

export const NICKNAME_MAX = 12;

/** 整理暱稱:去頭尾空白、拿掉控制字元,1～12 個字;不合格回傳 null */
export function cleanNickname(raw) {
  if (typeof raw !== "string") return null;
  const s = raw.replace(/[\p{C}]/gu, "").trim();
  const n = Array.from(s).length;
  return n >= 1 && n <= NICKNAME_MAX ? s : null;
}

export function setNickname(playerId, nickname) {
  stmts.setNickname.run(playerId, nickname);
}

/** 兩位真人對戰過 → 互相加進好友(已經是好友就更新時間,排到最前面) */
export const addFriends = db.transaction((a, b) => {
  const now = Date.now();
  stmts.addFriend.run(a, b, now);
  stmts.addFriend.run(b, a, now);
});

/** 好友清單 [{ playerId, nickname }],最近對戰的在前面 */
export function getFriends(playerId) {
  return stmts.friends.all(playerId);
}

/** 記一場結果(outcome: "win" | "loss" | "draw"),回傳更新後的累計戰績 */
export function recordMatchResult(playerId, outcome) {
  stmts.addResult.run({
    playerId,
    w: outcome === "win" ? 1 : 0,
    l: outcome === "loss" ? 1 : 0,
    d: outcome === "draw" ? 1 : 0,
  });
  return getRecord(playerId);
}

/**
 * 建立一位新玩家,回傳 { playerId, recoveryCode, createdAt }
 * 若 displayId 意外撞號(極低機率),自動重試。
 */
export function createPlayer() {
  for (let attempt = 0; attempt < 5; attempt++) {
    const playerId = genDisplayId();
    const recoveryCode = genRecoveryCode();
    const createdAt = Date.now();
    try {
      stmts.insert.run(playerId, recoveryCode, createdAt);
      return { playerId, recoveryCode, createdAt, justCreated: true };
    } catch (err) {
      if (err.code === "SQLITE_CONSTRAINT_PRIMARYKEY" || err.code === "SQLITE_CONSTRAINT_UNIQUE") {
        continue; // 撞號,重試
      }
      throw err;
    }
  }
  throw new Error("無法產生唯一的玩家ID,請重試");
}

export function findPlayerById(playerId) {
  return stmts.byId.get(playerId) || null;
}

export function findPlayerByRecoveryCode(recoveryCode) {
  return stmts.byRecoveryCode.get(recoveryCode) || null;
}

export default db;
