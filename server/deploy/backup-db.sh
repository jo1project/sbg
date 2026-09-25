#!/usr/bin/env bash
# 正式環境資料庫線上備份(VPS 上執行;每天由 systemd timer sbg-db-backup.timer 觸發,也可以部署前手動跑)。
#
# 資料庫是 WAL 模式,容器在跑的時候直接 cp data.sqlite 會漏掉還在 -wal 檔裡的資料,
# 所以在容器裡用 better-sqlite3 的 backup()(SQLite online backup API)做一致的快照,不用停服務。
# 備份完用 integrity_check 驗證、印出玩家數,再搬到 /root/sbg-backups/data.sqlite-YYYYMMDD-HHMM.sqlite,
# 最後刪掉超過 KEEP_DAYS 天的舊備份。任何一步失敗都以非 0 結束(systemd 會標成 failed)。
set -euo pipefail

CONTAINER="${CONTAINER:-snake-battle-server}"
SERVER_DIR="${SERVER_DIR:-/root/sbg/server}"   # 掛載進容器 /app 的資料夾
DEST="${DEST:-/root/sbg-backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"

TS="$(date +%Y%m%d-%H%M)"
TMP_NAME="data.sqlite-backup-${TS}"             # 先寫在掛載資料夾裡(符合 .gitignore 的 data.sqlite-*)
OUT="${DEST}/data.sqlite-${TS}.sqlite"

mkdir -p "$DEST"

docker exec "$CONTAINER" node -e "
const D = require('better-sqlite3');
const src = new D('data.sqlite', { readonly: true });
src.backup('${TMP_NAME}').then(() => {
  const b = new D('${TMP_NAME}');
  // 備份檔會沿用來源的 WAL 模式;改成一般 journal 模式,讓備份是單一個自足的檔案(關閉時不留 -wal/-shm)
  b.pragma('journal_mode = DELETE');
  const check = b.pragma('integrity_check', { simple: true });
  const players = b.prepare('select count(*) c from players').get().c;
  b.close();
  if (check !== 'ok') { console.error('integrity_check 失敗: ' + check); process.exit(1); }
  console.log('備份完成 integrity_check=ok players=' + players);
}).catch((e) => { console.error('備份失敗: ' + e.message); process.exit(1); });
"

mv "${SERVER_DIR}/${TMP_NAME}" "$OUT"
rm -f "${SERVER_DIR}/${TMP_NAME}-wal" "${SERVER_DIR}/${TMP_NAME}-shm"   # 保險:正常情況下已經不會有
echo "已存到 ${OUT} ($(stat -c %s "$OUT") bytes)"

# 保留最近 KEEP_DAYS 天:刪掉修改時間超過 KEEP_DAYS 天的每日備份
DELETED="$(find "$DEST" -maxdepth 1 -type f -name 'data.sqlite-*.sqlite' -mtime +"$((KEEP_DAYS - 1))" -print -delete)"
if [ -n "$DELETED" ]; then
  echo "刪除超過 ${KEEP_DAYS} 天的舊備份:"
  echo "$DELETED"
fi
echo "目前備份數: $(find "$DEST" -maxdepth 1 -type f -name 'data.sqlite-*.sqlite' | wc -l)"
