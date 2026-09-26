import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MAPS_DIR = process.env.MAPS_DIR || path.join(__dirname, "..", "maps");

// 啟動時載入整個固定地圖池,之後配對時從記憶體取,不需每次讀檔(見規格文件2.3節)。
// 依地圖 JSON 的 mapSet 分組:沒寫的是 "classic"(12x24 小地圖,Flutter/Godot 都能玩),
// "large" 是 tools/gen_large_map.mjs 產生的多塊拼接大地圖(只有 identify 帶 mapSets 含 "large" 的 client 會拿到)。
const pools = {};
for (const f of fs.readdirSync(MAPS_DIR).filter((f) => f.endsWith(".json"))) {
  const map = JSON.parse(fs.readFileSync(path.join(MAPS_DIR, f), "utf-8"));
  (pools[map.mapSet || "classic"] ||= []).push(map);
}

if (!pools.classic?.length) {
  throw new Error(`classic 地圖池為空,請確認 ${MAPS_DIR} 目錄下有地圖 JSON 檔`);
}

/** 從指定地圖組隨機抽一張 */
export function pickRandomMap(mapSet = "classic") {
  const pool = pools[mapSet];
  return pool[Math.floor(Math.random() * pool.length)];
}

export function hasMapSet(mapSet) {
  return !!pools[mapSet]?.length;
}

export function getMapPoolSize(mapSet = "classic") {
  return pools[mapSet]?.length || 0;
}
