#!/usr/bin/env bash
# 建置（匯出）前產生 godot/build_config.gd，把正式站網址帶進 release build（對應 Flutter 的 --dart-define=SERVER_URL）。
# 這個檔案在 .gitignore 裡，不會進版控（repo 是 public）。CI 用 repo secret SERVER_URL：
#   SERVER_URL=wss://your-domain.com/snake godot/tools/write_build_config.sh
# 本機要回到「沒有建置設定」的狀態：rm godot/build_config.gd
set -euo pipefail

: "${SERVER_URL:?需要 SERVER_URL 環境變數,例如 SERVER_URL=wss://your-domain.com/snake}"
case "$SERVER_URL" in
  ws://*|wss://*) ;;
  *) echo "SERVER_URL 要以 ws:// 或 wss:// 開頭:$SERVER_URL" >&2; exit 1 ;;
esac
case "$SERVER_URL" in
  *'"'*|*'\'*|*$'\n'*) echo "SERVER_URL 不能含有引號、反斜線或換行" >&2; exit 1 ;;
esac

OUT="$(cd "$(dirname "$0")/.." && pwd)/build_config.gd"
cat > "$OUT" <<EOF
# 建置時由 tools/write_build_config.sh 產生，不要 commit（見 godot/.gitignore）
extends RefCounted

const SERVER_URL := "$SERVER_URL"
EOF
echo "已寫入 $OUT(伺服器網址長度 ${#SERVER_URL})"
