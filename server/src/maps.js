import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MAPS_DIR = process.env.MAPS_DIR || path.join(__dirname, "..", "maps");

// 啟動時載入整個固定地圖池,之後配對時從記憶體隨機抽取,不需每次讀檔(見規格文件2.3節)
const mapPool = fs
  .readdirSync(MAPS_DIR)
  .filter((f) => f.endsWith(".json"))
  .map((f) => JSON.parse(fs.readFileSync(path.join(MAPS_DIR, f), "utf-8")));

if (mapPool.length === 0) {
  throw new Error(`地圖池為空,請確認 ${MAPS_DIR} 目錄下有地圖 JSON 檔`);
}

/** 隨機抽一張地圖(雙方各自獨立呼叫,允許抽到相同或不同地圖) */
export function pickRandomMap() {
  return mapPool[Math.floor(Math.random() * mapPool.length)];
}

export function getMapPoolSize() {
  return mapPool.length;
}
