# 貪食蛇對戰 — Flutter 客戶端

依照《手機連線對戰貪食蛇 — 遊戲規格文件》(`../docs/snake-battle-spec.md`)實作的第一版客戶端。
連線協定對應 `../server/src/events.js`。

## 目前已實作

- 連線/身份綁定(identify)、新帳號一次性還原碼提示、換裝置還原碼找回
- 隨機配對、好友ID邀請(發送/接受/拒絕/取消/逾時)
- 本地預測的蛇身移動與碰撞(撞牆/撞自己),死亡後送 `death_report` 給伺服器驗證
- 吃食物本地樂觀更新能量,由伺服器 `energy_update` 校正權威值
- 攻擊(直接/隨機效果)發動、0.3秒閃躲(放開搖桿觸發,見下方「已知限制」)
- 對手能量條、模糊小地圖(每2秒更新)、攻擊警示外框
- Random效果套用(加速影響移動間隔、暫停凍結操作、致盲遮蔽畫面)
- 防Spam自懲、對手斷線倒數、Double KO/勝負結果畫面
- 蛇頭/蛇身像素角色動畫、地圖障礙物(素描風羊皮紙地圖背景+障礙物圖示,撞到判死亡)(見下方「美術素材」)

## 已知限制 / 未做

- 音效、警示動畫節奏、攻擊動畫視覺 — 規格文件9.3/9.4節註明待後續設計,先卡流程位置不做視覺(已補上震動與文字警示)
- 閃躲操作:放開搖桿(`onPanEnd`)即嘗試閃躲,沒有攻擊來襲時放開是無害的no-op(伺服器與本地都會忽略),不需要額外的閃躲按鈕
- 能量滿量的脈動提示 — 目前只用靜態白框示意
- 搖桿死區/靈敏度、觸控熱區大小 — 待實機測試調整(規格9.2節)
- 沒有做 web/desktop 支援(僅 iOS/Android,與規格1節一致);WebSocket 用 `dart:io`,若未來要支援 web 需換成 `web_socket_channel`

## 美術素材

**角色**:`assets/sprites/hero.png`(蛇頭)、`assets/sprites/goblin.png`(蛇身,每一節都用)來自
"Puny Characters" 素材包(928x256,29欄x8列,每格32x32),分別是裡面現成的 `Human-Fighter` 和
`Goblin-Warrior` 精靈表,先當預設/佔位選擇,還沒套用規格2.4/2.5節討論的頭部客製化疊圖。已確認為
付費購買、可商用的授權,可以正式使用。渲染邏輯在 `lib/widgets/board.dart`:
- 列(row)= 方向,只用上下左右四個主列(`Direction.spriteRow`,見 `lib/models/point.dart`),對角列用不到
- 欄(col)= 走路動畫,1~4 四格循環,由 `GameController.moveTick`(每次實際移動+1)驅動,跟移動節奏天然同步
- 蛇頭用實際移動方向;蛇身每一節用「朝向前一節」的方向(`Direction.fromDelta`),做出跟隨感
- 素材圖片異步載入(`CharacterSprites.load()`,在 `main.dart` 啟動時觸發),載入完成前用原本的色塊當備援畫法

**地圖**:`assets/map/background.png` 是 Kenney Cartography Pack(CC0)的 `parchmentAncient` 羊皮紙
紋理,固定鋪滿整個棋盤(對應規格2.4節)。`assets/map/obstacle_*.png` 是同包裡的素描風山/樹/灌木小圖示,
座標由伺服器 `room.js` 的 `spawnInitialObstacles()` 在房間建立時各自獨立隨機生成(見規格2.3節,已實作
`obstacle_layout` 事件+撞到判死亡+伺服器端碰撞驗證),整局不變動,一格一個固定圖示(依座標決定,不是
每次重繪隨機換)。障礙物格加了白色外框(`lib/widgets/board.dart` 的 `obstacleBorder`)方便在地圖上辨識。
載入邏輯在 `lib/game/map_sprites.dart`,跟 `CharacterSprites` 共用 `lib/game/sprite_loader.dart` 的圖片載入函式。

## 開發

```bash
flutter pub get
flutter test      # 跑 test/collision_test.dart(碰撞判定邏輯的自我檢查)
flutter analyze
flutter run        # 需要實機或模擬器(iOS/Android)
```

伺服器位址寫死在 `lib/config.dart` 的 `GameConfig.serverUrl`(目前是正式站 `wss://my1st123.pp.ua/snake`),
本機測試要接本機伺服器的話直接改這個常數(Android模擬器連本機伺服器要用 `ws://10.0.2.2:8080`),
改完記得改回來或用git分支,別把本機網址推上TestFlight。

## 發布到 TestFlight(沒有Mac,用GitHub Actions建置)

Xcode只能跑在macOS,這個repo沒有Mac可以本地建置。改用GitHub Actions的macOS runner遠端建置+
簽章+上傳,workflow定義在 `.github/workflows/ios-testflight.yml`(手動觸發,GitHub repo → Actions →
iOS TestFlight → Run workflow)。以下材料需要在**自己的電腦**準備好(不需要Mac,openssl就能做,
私鑰全程留在自己手上,只有簽出來的結果貼進GitHub secrets):

### 1. Apple Developer 網站註冊 Bundle ID
developer.apple.com/account → Certificates, IDs & Profiles → Identifiers → + → App IDs → App
→ Bundle ID (Explicit) 填 `com.sbg.snakeBattle`(跟 `ios/Runner.xcodeproj` 裡設定的一致),
Capabilities先不用勾,存檔。

### 2. 產生 Distribution 憑證(CSR用openssl做,不需要Mac)
```bash
openssl genrsa -out ios_distribution.key 2048
openssl req -new -key ios_distribution.key -out ios_distribution.csr \
  -subj "/emailAddress=你的AppleID信箱/CN=你的名字/C=TW"
```
把 `ios_distribution.csr` 上傳到 developer.apple.com/account → Certificates → + →
Apple Distribution,下載回來的 `.cer` 轉成 p12(密碼自己設一組,等下要填進secret):
```bash
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export -inkey ios_distribution.key -in distribution.pem \
  -out distribution.p12 -passout pass:換成你自己的密碼
```

### 3. 產生 App Store 用的 Provisioning Profile
developer.apple.com/account → Profiles → + → App Store → 選步驟1的App ID → 選步驟2的憑證 →
下載 `.mobileprovision`。

### 4. App Store Connect 建立App + API Key
- appstoreconnect.apple.com → My Apps → + → New App,Bundle ID選 `com.sbg.snakeBattle`,填名稱/SKU
- appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → +,
  角色選 App Manager,產生後**立刻下載 `.p8`(只能下載一次,沒存到要重產)**,記下 Key ID 和 Issuer ID

### 5. 把材料填進 GitHub repo secrets
GitHub repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret 名稱 | 內容 |
|---|---|
| `IOS_DIST_CERTIFICATE_P12_BASE64` | `base64 -w0 distribution.p12` 的輸出 |
| `IOS_DIST_CERTIFICATE_PASSWORD` | 步驟2轉p12時設的密碼 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `base64 -w0 xxx.mobileprovision` 的輸出 |
| `APPSTORE_ISSUER_ID` | 步驟4的 Issuer ID |
| `APPSTORE_API_KEY_ID` | 步驟4的 Key ID |
| `APPSTORE_API_PRIVATE_KEY` | 步驟4下載的 `.p8` 檔案整個內容(含 BEGIN/END PRIVATE KEY 那兩行) |

Team ID 和 Provisioning Profile 名稱workflow會自動從profile檔案裡讀出來,不用另外填。

### 6. 觸發建置
GitHub repo → Actions → iOS TestFlight → Run workflow。macOS runner較慢,約10幾分鐘跑完。
上傳後App Store Connect那邊還要跑幾分鐘processing,跑完會出現在 TestFlight分頁。**第一次**要在
App Store Connect補完「出口合規」等基本問題(沒用到加密的話選No)才會真的推送給測試員的手機。
把自己加進內部測試員名單,手機上裝 TestFlight App 就能收到安裝通知。
