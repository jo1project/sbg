# sbg — 1v1 連線對戰貪食蛇

**這個 repo 是 public**:不要 commit 正式站網址以外的主機資訊(VPS IP、金鑰、密碼、secret)。正式站網址也不寫死在 client 原始碼裡(建置時帶入)。

## 資料夾

| 路徑 | 內容 |
|---|---|
| `client/` | Flutter 版 client(現行上架版本,iOS TestFlight / Android APK,CI 在 `.github/workflows/`,只能手動觸發) |
| `godot/` | Godot 4.7 HD-2D 版 client(移植中,目標跟 Flutter 版功能一致) |
| `server/` | Node.js + WebSocket 權威伺服器(`src/`)、情境測試(`test/`)、正式環境設定(`docker-compose.yml`、`deploy/`) |
| `docs/snake-battle-spec.md` | 遊戲規格(規則、數值、協定、斷線處理) |

## 重要文件

- `docs/snake-battle-spec.md`:規格,規則以這份為準(v1.1 起已跟實作對齊)
- `godot/PARITY.md`:Godot ↔ Flutter 功能對照表與狀態、規格 vs Flutter 差異的決定。**每次移植都要更新**
- `godot/TEST_SCENARIOS.md`:依規格逐條的手動測試情境(含除錯指令用法、自動化腳本指令)
- `godot/README.md`:Godot 執行模式、伺服器網址、release 建置
- `server/README.md`:協定說明、除錯指令、自動化測試、**「部署到 VPS」章節**(部署/備份/檢查/退回)
- `client/README.md`:Flutter 開發、美術素材來源、發布到 TestFlight

## 已定案的原則

- **伺服器為準**:能量、食物位置、攻擊/閃避判定、效果、勝負都由伺服器決定。移動、碰撞、吃到判定依規格在 client 本地先做(客戶端判定、伺服器驗證)。
- **Godot 不自創遊戲規則**:client 端邏輯照 Flutter(`client/lib/game/`)移植,行為不同的地方要記在 PARITY.md 並經過決定。
- **兩個 client 的訊息格式必須完全一致**(同一台伺服器兩個 client 都能用);訊息定義在 `server/src/events.js`。改協定要兩邊 client 一起考慮。
- **斷線處理照規格 6.2**(雙方凍結、自動重連、切背景 = 斷線)——Godot 已做,Flutter 決定不改。
- **除錯指令只能在開發環境**:`SBG_DEBUG_COMMANDS=1` 且 `NODE_ENV` 不是 `production` 才載入(`server/src/debug.js`);Godot 除錯面板只在 debug build。
- 已決定的數值:閃躲視窗 1 秒、斷線寬限 10 秒、心跳逾時 5 秒、斷線時閃避視窗恢復後重給完整 1 秒(`server/src/events.js` CONFIG)。

## 正式伺服器

細節與指令見 `server/README.md`「部署到 VPS」。重點:

- VPS 上是 **Docker 容器 `snake-battle-server`**(`server/docker-compose.yml`),程式碼掛載 `/root/sbg/server`;前面是另一個專案(calendar-call-reminder)的 **Caddy**,用網路別名 `snake:9090` 轉發 `wss://<網域>/snake`。
- SSH 在 **port 2222**(22 沒開)。這台 VPS 還跑著其他服務(股票通知、行事曆),不要動它們的容器/設定。
- 部署前先備份資料庫(`server/deploy/backup-db.sh`,每天 04:30 也會自動備份到 `/root/sbg-backups/`,保留 14 天);容器必須帶 `NODE_ENV=production`;部署後確認 log 沒有「除錯指令已啟用」。
- 資料庫是 SQLite WAL 模式,**不要直接 `cp` 正在用的 data.sqlite**,用 backup-db.sh(線上備份)。
- 防火牆:80/443 只接受 Cloudflare(`/usr/local/sbin/geo-firewall.sh`,屬於 calendar-call-reminder 專案)。網域必須維持 Cloudflare 代理,否則網站和憑證續期都會壞。
- 不要對正式站跑測試腳本(會建立測試帳號、需要除錯指令)。

## 常用指令

```bash
# 伺服器
cd server && npm test                          # 全部情境測試(需要 Node 22;沒有 nvm 用:npx -y -p node@22 -c "npm ci && npm test")
node test/d_reconnect.mjs                      # 單獨跑一個(沒設 SERVER_URL 會自己起測試伺服器)
SBG_DEBUG_COMMANDS=1 npm start                 # 本機開發伺服器(ws://localhost:8080,開除錯指令)

# Godot(命令列參數放在 -- 後面)
godot --path godot                                               # debug:本地單機模式
godot --path godot -- --online --sbg-server=ws://127.0.0.1:8080  # 連本機伺服器(F5 模擬切背景、F3 除錯面板、M 配對)
godot --headless --path godot --quit-after 120                   # 檢查腳本有沒有解析錯誤
SERVER_URL=wss://… godot/tools/write_build_config.sh             # release 建置前帶入正式站網址(產生 gitignore 的 build_config.gd)
```

Godot 跑過之後 `godot/project.godot` 常被編輯器自動重排格式,commit 前確認只 commit 真正要改的設定。
