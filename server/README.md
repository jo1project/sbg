# 貪食蛇對戰伺服器(骨架版)

依照《手機連線對戰貪食蛇 — 遊戲規格文件》第7章架構實作的第一版伺服器骨架。
用 Node.js + `ws`(WebSocket)實作,權威伺服器 + 事件驅動,對應規格文件的攻擊判定時序與狀態機。

## 目前已實作

- WebSocket 連線 + `identify` 綁定玩家ID
- 隨機配對佇列(逾時8秒配對NPC)
- 好友ID配對(完整版:忙碌檢查、邀請通知、接受/拒絕/取消、30秒逾時)
- 房間管理(記憶體 Map,對戰結束即銷毀)
- 食物生成與吃食驗證(恆定3個,伺服器決定位置)
- 能量系統(乙案:封頂10計算,餘額保留)
- 兩種攻擊(direct / random)+ 1秒閃躲判定 + RTT延遲補償
- random攻擊的1秒預告延遲生效
- 防Spam機制(連續被閃躲3次反噬暫停3秒)
- 斷線10秒重連寬限期(規格6.2):斷線時整場凍結(`room.js` `pause()`,效果/閃躲視窗/預告/雙殺等待/小地圖/NPC 都停),
  同一個 playerId 在寬限期內重連後用同一則 `match_resumed` 同時恢復雙方;超時判負,斷線方回來時補送 `game_over`
- 應用層心跳:已 identify 的連線 5 秒沒收到任何訊息(client 每秒 ping)就視為斷線(`CONFIG.HEARTBEAT_TIMEOUT_MS`)
- 斷線當下閃躲視窗還開著:恢復時重送 `attack_incoming`(`resumed: true`)並重新給完整 1 秒(`CONFIG.DODGE_WINDOW_ON_RESUME = "full"`)
- 簡化版中等難度NPC(半隨機攻擊決策,5~10能量隨機門檻出手,30%閃躲成功率)
- 死亡判定(客戶端判定、伺服器驗證碰撞後才採信 death_report,含200ms Double KO窗口)
- 使用者ID系統的資料庫持久化(SQLite,含還原碼機制)
- 蛇身座標同步(客戶端每1秒回報,伺服器用於食物避讓與模糊小地圖來源)
- **修正**:食物改為每位玩家獨立生成(模式B兩人地圖互不相干,先前骨架誤寫成共用食物清單)

## 已知限制

- NPC 維持抽象能量模擬,沒有真實蛇身座標,因此玩家與NPC對戰時小地圖不會顯示NPC位置
- 蛇身座標同步僅伺服器內部使用,`snake_position_update` 頻率(1秒)與食物驗證的即時性有取捨,
  極端情況下食物仍有極小機率生成在玩家剛好1秒內移動到的新位置上(可接受的誤差範圍)

## 自動化測試

```bash
npm test                          # room.test.js + test/ 下全部情境腳本
node test/s10_fake_death.mjs      # 單獨跑一個
```

**Node 版本**:用 Node 22 LTS(`server/.nvmrc`)。`better-sqlite3@11` 沒有 Node 24 的預編譯檔,Node 24 上 `npm install`
會改成現場編譯,沒有 C++ 編譯工具就會失敗。沒有 nvm 時可以不動系統的 Node,只在這個指令裡用 Node 22:

```bash
npx -y -p node@22 -c "npm ci && npm test"
```

`test/` 下的腳本用 WebSocket 直接模擬玩家(情境對照 `godot/TEST_SCENARIOS.md`)。沒設 `SERVER_URL` 時每個腳本
會自己在隨機埠號起一台測試伺服器(開除錯指令、`DB_PATH` 指到暫存資料夾,不會碰 `data.sqlite`);
要測已經在跑的伺服器就設 `SERVER_URL=ws://127.0.0.1:8080`(那台要用 `SBG_DEBUG_COMMANDS=1` 啟動)。

| 腳本 | 情境 |
|---|---|
| `test/c04_account_db.mjs` | C-02～C-04 玩家 ID/還原碼寫進 SQLite、重開伺服器後還在、restore_account(唯一真的讀寫資料庫的測試) |
| `test/s10_fake_death.mjs` | S-10 假的 death_report 被拒絕 |
| `test/f04_fake_food.mjs` | F-04 foodId 對、headPos 錯的吃食回報被忽略 |
| `test/w03_double_ko.mjs` | W-03 200ms 內雙方死亡 = 平手;超過 = 先回報的輸 |
| `test/e07_pause_body_death.mjs` | E-07 暫停結束瞬間撞身體,death_report self 被採信 |
| `test/d_reconnect.mjs` | D-07～D-10 斷線凍結、效果剩餘時間、閃避視窗重給 1 秒、切背景 5/12 秒、5 秒心跳逾時 |

## 死亡回報的碰撞驗證

`death_report` 需附上 `cause`("wall" | "self")、死亡當下的 `headPos`,撞自己時再附上 `bodyCells`。
伺服器據此做邏輯驗證(見 `src/room.js` 的 `validateDeathReport`):

- 撞牆:`headPos` 是否真的在地圖邊界外(不受延遲影響,100%準確)
- 撞自己:`headPos` 是否真的落在回報的 `bodyCells` 其中一格

驗證不通過時回傳 `death_report_rejected`,不判定死亡。這是邏輯自洽驗證,不是伺服器重新模擬整場移動——
座標仍由客戶端提供,擋的是「完全沒碰撞卻謊報死亡」這類明顯造假,詳見規格文件6.1節的取捨說明。

## 尚未實作(需要接續開發)

- TLS/WSS 加密連線(正式上線前需搭配憑證,純 `ws://` 僅適合本機測試)

## 使用者ID與還原碼機制說明

- 客戶端第一次連線時送 `identify`(不帶 playerId)→ 伺服器建立新玩家,
  回傳 `playerId` 與 `recoveryCode`(僅此一次回傳,前端應立即提示玩家
  在「備份帳號」畫面截圖/抄下還原碼)
- 之後連線都送 `identify`(帶上本地儲存的 playerId)即可自動辨識身份
- 換裝置或重灌後,送 `restore_account`(帶 recoveryCode)→ 伺服器回傳
  對應的 playerId → 前端再用這個 playerId 送一次 `identify` 完成綁定
- 資料庫檔案預設為專案根目錄的 `data.sqlite`,可用環境變數 `DB_PATH` 指定其他路徑
- `players` 資料表目前只有 playerId / recoveryCode / createdAt 三個欄位,
  未來要加成就、角色外觀,直接在這張表加欄位即可,不需重構

## 安裝與啟動

```bash
npm install
npm start
```

預設監聽埠號 `8080`,可用環境變數 `PORT` 覆寫;預設綁 `0.0.0.0`(本機測試方便直連),
可用環境變數 `HOST` 覆寫(正式環境搭配 Nginx 時建議設 `127.0.0.1`,見下方部署步驟):

```bash
PORT=3000 npm start
```

## 開發用除錯指令(只限開發環境)

手動測試規格用(情境清單見 `godot/TEST_SCENARIOS.md`,Godot debug build 裡有除錯面板可以送這些指令)。
**預設關閉**,必須同時符合兩個條件才會啟用:

1. 環境變數 `SBG_DEBUG_COMMANDS=1`
2. `NODE_ENV` 不是 `production`(正式環境即使誤設 `SBG_DEBUG_COMMANDS=1`,伺服器也會拒絕並印出錯誤)

沒啟用時 `src/debug.js` 根本不會被載入,`debug_*` 訊息一律當成未知訊息忽略。啟用時啟動訊息會印出警告。

```bash
SBG_DEBUG_COMMANDS=1 npm start
```

除錯連線不需要 `identify`,用 `playerId` 指定要操作的玩家(或他所在的房間/NPC 對手)。
回應是 `{ type: "debug_ack", command, detail }` 或 `{ type: "debug_error", command, message }`。

| 指令 | 欄位 | 作用 |
|---|---|---|
| `debug_list` | — | 列出線上玩家、房間、能量、效果、閃躲計數、NPC 設定 |
| `debug_force_next_effect` | `playerId`, `effect`: `speedup`/`pause`/`blind`/`null` | 該玩家房間的下一次隨機效果攻擊固定是這個效果(不論誰發動,用一次就清掉;`null` 取消) |
| `debug_set_energy` | `playerId`, `energy` | 直接設定權威能量(真人或 NPC 都可),照常廣播 `energy_update` |
| `debug_npc_attack` | `playerId`, `attackType`: `direct`/`random`, `delayMs`, `energy`(選填) | 該玩家的 NPC 對手在 `delayMs` 後發動攻擊;有給 `energy` 就先把 NPC 能量設成這個值。被狀態鎖擋下會回 `debug_error` 附原因 |
| `debug_npc_dodge` | `playerId`, `mode`: `always`/`never`/`default` | NPC 被攻擊時永遠閃避/永遠不閃避/照規格 30% |
| `debug_npc_auto_attack` | `playerId`, `enabled` | 關掉/打開 NPC 自己的自動攻擊,避免干擾手動測試的時序 |

## 部署到 VPS(正式環境:Docker + Caddy)

### 架構

```
手機 App ──wss://my1st123.pp.ua/snake──▶ Caddy(容器 calendar-call-reminder-caddy-1,:80/:443,Let's Encrypt)
                                           │  reverse_proxy /snake* snake:9090
                                           ▼  (docker 網路 calendar-call-reminder_default)
                                  snake-battle-server 容器(node:24-bookworm,NODE_ENV=production)
                                           │  掛載 /root/sbg/server → /app
                                           ▼
                                  /root/sbg/server/data.sqlite(玩家 ID / 還原碼)
```

- VPS:SSH 在 **port 2222**(22 沒開),`ssh -p 2222 root@<VPS IP>`。**VPS 的 IP 不要寫進 repo**(這個 repo 是 public,
  網域走 Cloudflare 代理,公開 IP 等於讓人繞過 Cloudflare 直接打到主機);建議在自己電腦的 `~/.ssh/config` 設別名:
  `Host sbg-vps` / `HostName <VPS IP>` / `Port 2222` / `User root`,之後 `ssh sbg-vps` 即可
- 程式碼:`/root/sbg`(git clone 的 repo),伺服器在 `/root/sbg/server`,容器設定是 `server/docker-compose.yml`
- Caddy 設定在另一個 compose 專案:`/opt/calendarreminder/Caddyfile`(`my1st123.pp.ua` 區塊裡 `reverse_proxy /snake* snake:9090`),
  跟這台 VPS 上其他服務共用,改之前先確認不會影響別的站
- 遊戲容器不對外開 port,只透過 docker 網路別名 `snake` 讓 Caddy 連
- `deploy/nginx.conf.example` 是早期的 Nginx 方案,正式環境**沒有用**,只留作參考

### 防火牆(80/443 只接受 Cloudflare)

來源主機的 80/443 **只接受 Cloudflare 的 IP**,其他人直接連 VPS IP 會被丟掉(網站、`wss://…/snake` 都要經過 Cloudflare)。

- **管理方式**:`/usr/local/sbin/geo-firewall.sh`(原始檔在 `/opt/calendarreminder/deploy/geo-firewall.sh`,
  **屬於 calendar-call-reminder 專案,不在這個 repo**;那個專案重新部署時要確認沒有把這支腳本蓋回舊版)。
  - 80/443 是 Docker 發佈的 port,流量不經過 INPUT,**ufw 規則對它們沒有作用**;規則在 `DOCKER-USER` chain(註解 `geo-tw`)
  - Cloudflare IP 清單從 `https://www.cloudflare.com/ips-v4` 下載到 `/var/lib/geo-firewall/cf.v4`,載入 ipset `cf_origin`
  - `geo-firewall.service` 開機時套用;`geo-firewall-update.timer` 每週更新清單(台灣/VPN 清單 + Cloudflare 清單)再套用
  - **防呆**:下載失敗會保留上一份清單;完全沒有清單時退回舊規則(443 只允許台灣、80 全開),不會讓網站整個斷掉
- **不受影響**:容器對外連線(私有網段先 RETURN)、SSH(port 2222)、IPv6(80/443 本來就全擋)
- **網域必須維持 Cloudflare 代理(橘色雲朵)**。改成 DNS only 的話,網站會連不上,Let's Encrypt 的 HTTP-01 續期也會失敗
  (驗證請求要經過 Cloudflare 才進得來)

```bash
/usr/local/sbin/geo-firewall.sh status     # 看 ipset 數量與目前的 DOCKER-USER 規則
iptables -S DOCKER-USER                    # 應該有「--match-set cf_origin src ... ACCEPT」和 80,443 的 DROP
/usr/local/sbin/geo-firewall.sh cf         # 手動更新 Cloudflare 清單並重新套用
systemctl list-timers geo-firewall-update.timer
```

從外面確認(在非 Cloudflare 的網路上):直連 `<VPS IP>` 的 80/443 要**連不上**,經過網域要正常;
`curl -sI http://<網域>/.well-known/acme-challenge/x` 要看到 Caddy 的 `308` 轉址(代表 Cloudflare → 來源 :80 通,憑證續期沒問題)。

退回改之前的規則:改動前的腳本與 iptables/ipset 狀態備份在 `/root/firewall-backups/`,

```bash
cp /root/firewall-backups/geo-firewall.sh.<時間> /usr/local/sbin/geo-firewall.sh
/usr/local/sbin/geo-firewall.sh apply
```

### 部署步驟

```bash
ssh -p 2222 root@<VPS IP>     # 或 ssh sbg-vps
cd /root/sbg

# 0. 看一下 repo 有沒有別人在 VPS 上直接改、還沒 commit 的檔案(有的話先處理,不要被 pull 蓋掉)
git status --short

# 1. 部署前備份資料庫
/root/sbg/server/deploy/backup-db.sh

# 2. 更新程式碼
git pull --ff-only

# 3. package-lock.json 有變動時才需要:在容器裡重裝依賴(better-sqlite3 要用容器裡的 Node 24)
git diff --stat HEAD@{1} HEAD -- server/package-lock.json
docker run --rm -v /root/sbg/server:/app -w /app node:24-bookworm npm ci --omit=dev

# 4. 先在正在跑的容器裡試跑新版(另一個 port + 暫存資料庫,不影響線上),看到「伺服器已啟動」才繼續
docker exec snake-battle-server sh -c 'PORT=9191 HOST=127.0.0.1 NODE_ENV=production DB_PATH=/tmp/preflight.sqlite timeout 4 node src/server.js; rm -f /tmp/preflight.sqlite*'

# 5. 確認現在沒人在玩(重啟會斷掉進行中的對局)
nsenter -t $(docker inspect -f '{{.State.Pid}}' snake-battle-server) -n ss -tn state established '( sport = :9090 )' | tail -n +2 | wc -l

# 6. 重啟,載入新程式碼(容器設定沒變時用 restart 就好)
docker restart snake-battle-server
```

### 備份資料庫

資料庫是 WAL 模式,容器在跑的時候直接 `cp data.sqlite` 會漏掉還在 `-wal` 檔裡的資料,要用 SQLite 的線上備份。
`deploy/backup-db.sh` 在容器裡用 better-sqlite3 的 `backup()` 做一致的快照(不用停服務),轉成單一檔案、
跑 `integrity_check`、印出玩家數,存到 `/root/sbg-backups/data.sqlite-YYYYMMDD-HHMM.sqlite`,並刪掉超過 14 天的舊備份。
部署前手動跑一次:

```bash
/root/sbg/server/deploy/backup-db.sh
```

### 資料庫自動備份(每天 04:30)

systemd timer 每天 04:30(Asia/Taipei)跑 `deploy/backup-db.sh`,保留最近 14 天。unit 檔在 repo 的
`deploy/systemd/`,安裝(或改了 unit 檔之後重新安裝):

```bash
cp /root/sbg/server/deploy/systemd/sbg-db-backup.{service,timer} /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now sbg-db-backup.timer
```

確認有正常執行:

```bash
systemctl list-timers sbg-db-backup.timer          # 下次/上次執行時間
systemctl status sbg-db-backup.service --no-pager  # 上次結果(Active: inactive (dead) + status=0/SUCCESS 是正常的)
journalctl -u sbg-db-backup.service -n 20 --no-pager   # 每次的輸出:「備份完成 integrity_check=ok players=N」
ls -la /root/sbg-backups/                           # 每天多一個檔、最多約 14 個
systemctl start sbg-db-backup.service               # 想馬上手動跑一次
```

**容器設定有變**(改了 `docker-compose.yml`,或第一次從手動 `docker run` 的容器換成 compose 管理)時,步驟 6 改成:

```bash
cd /root/sbg/server
docker compose config            # 先看展開後的設定對不對
docker rm -f snake-battle-server # 第一次換成 compose 時需要:舊容器不是 compose 建的,名字會衝突
docker compose up -d
```

### 部署後檢查(確認除錯指令沒開)

```bash
docker logs --tail 20 snake-battle-server
#   要有「貪食蛇對戰伺服器已啟動,監聽埠號 9090」
#   **不能**有「開發用除錯指令已啟用」;有「拒絕啟用除錯指令」代表有人設了 SBG_DEBUG_COMMANDS 但被 NODE_ENV 擋下

docker exec snake-battle-server sh -c 'env | grep -E "NODE_ENV|SBG_"'
#   要看到 NODE_ENV=production,而且沒有 SBG_DEBUG_COMMANDS
```

從外面確認(在任何裝了 node 的電腦上,server/ 目錄裡跑;只做握手和送一個除錯指令,不 identify,不會在正式資料庫建帳號):

```bash
node -e '
import("ws").then(({default: WebSocket}) => {
  const ws = new WebSocket("wss://my1st123.pp.ua/snake"); const got = [];
  ws.on("open", () => { console.log("連線 OK"); ws.send(JSON.stringify({type: "debug_list"}));
    setTimeout(() => { console.log(got.length ? "!! 除錯指令有回應,正式環境不該這樣" : "除錯指令沒有回應 OK"); ws.close(); }, 2500); });
  ws.on("message", (m) => got.push(m.toString())); ws.on("close", () => process.exit(0));
});'
```

### 退回舊版

程式碼掛載在容器外,退回 = 把程式碼切回舊的 commit 再重啟:

```bash
cd /root/sbg
git log --oneline -5 -- server/          # 找要退回的 commit
git checkout <舊commit> -- server/src server/package.json server/package-lock.json
docker restart snake-battle-server
# 確認沒問題後,之後要回到最新版:git checkout HEAD -- server/ && docker restart snake-battle-server
```

資料庫要一起退回時(一般不需要,資料表結構目前沒變過):

```bash
docker stop snake-battle-server
cp /root/sbg-backups/data.sqlite-YYYYMMDD-HHMM.sqlite /root/sbg/server/data.sqlite   # 先用 backup-db.sh 備份現在的
rm -f /root/sbg/server/data.sqlite-wal /root/sbg/server/data.sqlite-shm
docker start snake-battle-server
```

容器設定也要退回時:`git checkout <舊commit> -- server/docker-compose.yml`,再照上面「容器設定有變」重建。

## 檔案結構

```
snake-server/
├── package.json
├── docker-compose.yml  # 正式環境容器設定(見「部署到 VPS」)
├── deploy/
│   ├── backup-db.sh      # 資料庫線上備份(每天由 systemd timer 執行)
│   ├── systemd/          # sbg-db-backup.service / .timer
│   └── nginx.conf.example  # 早期 Nginx 方案,正式環境沒用
├── README.md
├── .gitignore
├── test/               # 情境自動化測試(npm test)
└── src/
    ├── server.js       # 進入點,WebSocket連線與訊息路由
    ├── events.js        # 事件類型常數 + 數值設定(CONFIG)
    ├── db.js             # SQLite持久化(玩家ID/還原碼)
    ├── debug.js          # 開發用除錯指令(只在 SBG_DEBUG_COMMANDS=1 且非 production 時載入)
    ├── player.js         # 玩家狀態(能量/效果/RTT/邀請狀態)
    ├── room.js           # 房間邏輯(食物/攻擊判定核心)
    ├── matchmaking.js    # 配對佇列 + 好友邀請流程 + NPC填充
    └── npc.js            # 簡化版NPC行為
```

## 快速測試連線(不用寫客戶端,先用 wscat)

```bash
npm install -g wscat
wscat -c ws://localhost:8080

# 連上後手動送出測試訊息:
{"type":"identify","playerId":"test_A"}
{"type":"join_queue"}
```

再開一個終端機視窗用另一個 `playerId` 連線,約8秒內兩邊應該會收到 `match_found`
(若只開一個視窗,8秒後會自動配對到NPC)。
