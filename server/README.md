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
- 兩種攻擊(direct / random)+ 0.3秒閃躲判定 + RTT延遲補償
- random攻擊的1秒預告延遲生效
- 防Spam機制(連續被閃躲3次反噬暫停3秒)
- 斷線10秒重連寬限期
- 簡化版中等難度NPC(半隨機攻擊決策,5~10能量隨機門檻出手,30%閃躲成功率)
- 死亡判定(客戶端判定、伺服器驗證碰撞後才採信 death_report,含200ms Double KO窗口)
- 使用者ID系統的資料庫持久化(SQLite,含還原碼機制)
- 蛇身座標同步(客戶端每1秒回報,伺服器用於食物避讓與模糊小地圖來源)
- **修正**:食物改為每位玩家獨立生成(模式B兩人地圖互不相干,先前骨架誤寫成共用食物清單)

## 已知限制

- NPC 維持抽象能量模擬,沒有真實蛇身座標,因此玩家與NPC對戰時小地圖不會顯示NPC位置
- 蛇身座標同步僅伺服器內部使用,`snake_position_update` 頻率(1秒)與食物驗證的即時性有取捨,
  極端情況下食物仍有極小機率生成在玩家剛好1秒內移動到的新位置上(可接受的誤差範圍)

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

## 部署到小型VPS的建議步驟

1. VPS 安裝 Node.js 20+(`nvm install 20` 或發行版套件管理員)
2. 把整個 `snake-server/` 資料夾上傳到VPS(或用git clone)
3. `npm install --production`
4. 用 `pm2` 或 `systemd` 讓程式常駐並自動重啟,並把 `HOST` 設成只接受本機連線、`NODE_ENV` 設成
   `production`(除錯指令的第二道保險:就算環境裡誤設了 `SBG_DEBUG_COMMANDS=1` 也不會啟用):
   ```bash
   npm install -g pm2
   NODE_ENV=production HOST=127.0.0.1 pm2 start src/server.js --name snake-server
   pm2 save
   ```
   啟動後確認 log 裡**沒有**「除錯指令已啟用」這行。
5. 前面加一層 Nginx 終止 `wss://` 再轉給本機的 `ws://127.0.0.1:8080`,並用 Let's Encrypt 申請憑證
   (手機App連線正式環境建議一律走加密連線)。設定範例、certbot指令見 `deploy/nginx.conf.example`

## 檔案結構

```
snake-server/
├── package.json
├── README.md
├── .gitignore
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
