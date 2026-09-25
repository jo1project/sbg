// 一次跑完 server/test/ 下所有情境測試:npm test(或 node test/run-all.mjs)
// 每個腳本在獨立的子行程裡跑、各自起一台測試伺服器;有設 SERVER_URL 就全部連那台。
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const scripts = [
  "c04_account_db.mjs",
  "s10_fake_death.mjs",
  "f04_fake_food.mjs",
  "w03_double_ko.mjs",
  "e07_pause_body_death.mjs",
  "d_reconnect.mjs",
  "w05_match_stats.mjs",
];

const results = [];
for (const s of scripts) {
  console.log(`\n===== ${s} =====`);
  const r = spawnSync(process.execPath, [path.join(here, s)], { stdio: "inherit", env: process.env });
  results.push([s, r.status === 0]);
}

console.log("\n===== 總結 =====");
for (const [s, ok] of results) console.log(`${ok ? "PASS" : "FAIL"}  ${s}`);
const failed = results.filter(([, ok]) => !ok).length;
console.log(failed === 0 ? "全部通過" : `${failed} 個腳本失敗`);
process.exitCode = failed ? 1 : 0;
