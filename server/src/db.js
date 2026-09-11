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

const stmts = {
  insert: db.prepare(
    "INSERT INTO players (playerId, recoveryCode, createdAt) VALUES (?, ?, ?)"
  ),
  byId: db.prepare("SELECT * FROM players WHERE playerId = ?"),
  byRecoveryCode: db.prepare("SELECT * FROM players WHERE recoveryCode = ?"),
};

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
