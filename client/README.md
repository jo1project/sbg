# 貪食蛇對戰 — Flutter 客戶端

依照《手機連線對戰貪食蛇 — 遊戲規格文件》(`../docs/snake-battle-spec.md`)實作的第一版客戶端。
連線協定對應 `../server/src/events.js`。

## 目前已實作

- 連線/身份綁定(identify)、新帳號一次性還原碼提示、換裝置還原碼找回
- 隨機配對、好友ID邀請(發送/接受/拒絕/取消/逾時)
- 對戰開始前3-2-1倒數(`GameController._startPreGameCountdown`,純client端各自倒數,不等伺服器同步),
  倒數期間畫面已顯示雙方初始蛇身/地圖,但移動/位置回報都還沒開始
- 本地預測的蛇身移動與碰撞(撞牆/撞自己),死亡後送 `death_report` 給伺服器驗證
- 吃食物本地樂觀更新能量,由伺服器 `energy_update` 校正權威值
- 攻擊(直接/隨機效果)發動、1秒閃躲(放開搖桿觸發,見下方「已知限制」)
- 對手能量條、模糊小地圖(每2秒更新)、攻擊警示雙重提示(邊緣閃爍外框 + 蛇頭正上方閃爍瞄準圖案)
- Random效果套用(加速影響移動間隔、暫停凍結操作、致盲遮蔽畫面)
- 防Spam自懲、對手斷線倒數、Double KO/勝負結果畫面
- 蛇頭/蛇身像素角色動畫、固定地圖池(手工設計房間+走廊+障礙物,雙方各自獨立隨機抽一張,撞到障礙物或牆體判死亡)(見下方「美術素材」)
- 地圖滿版鋪整個畫面(`widgets/board.dart` 沒有AspectRatio限制,格子按畫面實際寬高分開計算),
  能量條/小地圖/搖桿/攻擊鍵都是半透明浮在地圖上的overlay(`screens/game_screen.dart`)

## 已知限制 / 未做

- 音效 — 規格文件9.3/9.4節註明待後續設計,先卡流程位置不做視覺(已補上震動、文字警示、攻擊命中橫幅圖片)
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
- 欄(col)= 動畫,由 `GameController.moveTick`(每次實際移動+1)驅動,跟移動節奏天然同步:上下移動用
  走路循環(1~4格),左右移動改用素材裡的攻擊動畫循環(5~8格,`CharacterSprites.attackFrameCols`)
- 蛇頭用實際移動方向;蛇身每一節用「朝向前一節」的方向(`Direction.fromDelta`),做出跟隨感
- 素材圖片異步載入(`CharacterSprites.load()`,在 `main.dart` 啟動時觸發),載入完成前用原本的色塊當備援畫法

**地圖**:改採**固定地圖池架構**(取代先前的即時隨機演算法),素材是 `assets/dungeon/` 下的
[0x72 DungeonTilesetII](https://0x72.itch.io/dungeontileset-ii)(CC0授權)石磚地牢風格。地圖是
12欄(x軸)x 24列(y軸)的直向比例棋盤(`GameConfig.mapWidth`/`mapHeight`),資料格式由伺服器
`server/maps/*.json` 定義(見規格文件7.7節):房間+走廊的矩形範圍(`rooms`/`corridors`)、蛇重生點
(`spawnPos`)、障礙物清單(`obstacles`,含 `type`/`species`)。伺服器啟動時把整個地圖池讀進記憶體
(`server/src/maps.js`),每次配對成功時**雙方各自獨立隨機抽一張**(可能拿到不同張),透過
`obstacle_layout` 事件把整包地圖資料送給該玩家自己(`{ map }`),解析成 `lib/models/game_map.dart`
的 `GameMap`。目前只有「地圖1」一張定案地圖(`server/maps/map_01.json`):4個房間、3段錯位走廊。

- **地板**:房間/走廊範圍內逐格鋪 `floor_1`~`floor_8`(約88%用`floor_1`,其餘12%依座標雜湊固定選一張
  裂痕/苔蘚變化貼圖,同一格每次重繪都一樣,見 `MapSprites.floorFor()`),範圍以外一律黑色虛空
- **牆體**:沿每個房間矩形外緣一圈用 `wall_top_left/mid/right`、`wall_left/right` 拼牆,素材包沒有
  專門的底牆圖磚,底部邊界用頂牆圖磚上下翻轉湊成(見 `board.dart` 的 `_paintRoomWalls()`);牆體外緣
  若剛好是走廊銜接的開口(該格本身可通行)就跳過不畫,自然形成出入口
- **走廊**:不畫實體牆、維持淨空,只在上下邊緣(非開口處)疊一條半透明白線標示地板邊界
  (`_paintCorridorEdges()`,ponytail簡化版,沒有另外接素材包的`wall_edge_*`薄磚)
- **障礙物**(4類,見規格2.4節):`crate`木箱、`column`石柱、`chest`寶箱(`chest_full_open_anim_f0`)、
  `monster`怪物哨兵(固定原地不動,4格待機動畫循環播放,物種`species`由伺服器指定,動畫frame跟
  `moveTick`同步循環,見`MapSprites.monsterIdle`)。小型怪物(goblin/skelet/imp/chort)佔1格;
  大型怪物(big_demon/big_zombie/ogre,`size:"big"`)素材寬度是一般的兩倍,水平多佔右邊一格
  (`MapObstacle.cells`,兩格都算碰撞範圍),`_drawObstacle()`會依`cells.length`把寬度基準改成
  整個footprint、置中對齊,而不是塞進單一格子。圖案本身比16x16高(木箱/石柱/怪物立繪),錨定格子
  底部往上延伸畫,不是硬塞進單一格子裡拉伸。撞到障礙物或牆體(含房間/走廊範圍外的虛空)皆判死亡,
  伺服器端也會驗證(`room.js` 的 `validateDeathReport()`/`obstacleCells()` 吃地圖資料)。載入邏輯在
  `lib/game/map_sprites.dart`,跟 `CharacterSprites` 共用 `lib/game/sprite_loader.dart` 的圖片載入函式。
  目前地圖池有三張(`server/maps/map_01~03.json`):地圖1/2是房間+走廊佈局、只用小型怪物;地圖3是
  單一大房間、放了三隻大型怪物。

**放大與外框**(`lib/widgets/board.dart`):蛇身每一節用 `_spriteScale`(3倍)為基準放大畫,再各自乘上
`_heroScale`(蛇頭,0.75倍,即再縮小25%)/`_goblinScale`(蛇身,0.5倍,即再縮小50%),邊長固定用
`min(cellW, cellH)` 算(維持正方形,不會因為棋盤非正方形而被拉伸變形),中心點對齊原本的格子中心,
蓋過鄰近格子,格線也拿掉了。障礙物改用 `_obstacleScale`(1.4倍)錨定格子底部放大(見上方「地圖」),
沒有再疊白色外框(0x72素材本身輪廓對比已經夠清楚)。蛇身改成從尾畫到頭,確保放大後蛇頭蓋在身體上面。

**攻擊命中橫幅**(`lib/screens/game_screen.dart` 的 `_AttackHitBanner`):從畫面中央的右邊滑入、短暫停留、
再繼續往左滑出畫面(`TweenSequence` 驅動一個2秒的 `AnimationController`,在 `GameController.showAttackHitBanner`
從false翻true的當下觸發一次進場→停留→出場的完整動畫,不是像舊版那樣單純在兩個位置間來回)。

**UI**:`assets/ui/crosshair.png` 是 Kenney Crosshair Pack(CC0授權)裡的 `PNG/Outline (2x)/crosshair-051.png`,
用於攻擊來襲雙重警示的第二種提示(見上方「目前已實作」)。渲染邏輯在 `lib/screens/game_screen.dart` 的
`_AttackCrosshairIndicator`:只在 `c.incomingAttack != null` 時才 mount 這個 StatefulWidget,用
`AnimationController`(300ms、`repeat(reverse: true)`)驅動 `FadeTransition` 做閃爍效果,State生命週期
跟著攻擊視窗自動開始/結束,不需要另外在 `GameController` 裡管理計時器。位置用 `LayoutBuilder` 包住外層
`Stack` 拿到的畫面尺寸換算 `cellW`/`cellH`(跟 `Board` 的 `CustomPaint` 算法一致),疊在自己蛇頭
(`c.mySnake.first`)那一格的正上方。

`assets/ui/food_gem.png` 是 Kenney Simplified Platformer Pack(CC0授權)裡的
`PNG/Items/platformPack_item010.png`(橘色切割寶石),裁掉原圖(64x64)四周的透明留白後存檔。
`board.dart` 畫食物時直接把這張圖等比縮放到約0.7倍格子大小,置中畫在食物生成的座標上,固定顯示、
沒有動畫或方向變化(取代原本的紅色圓點)。

## 開發

```bash
flutter pub get
flutter test      # 跑 test/collision_test.dart(碰撞判定邏輯的自我檢查)
flutter analyze
flutter run        # 需要實機或模擬器(iOS/Android),不帶--dart-define預設接本機伺服器
```

伺服器位址是`lib/config.dart`裡`GameConfig.serverUrl`的build-time環境變數(`String.fromEnvironment`),
不寫死在原始碼裡——這個repo是public的。預設值是`ws://localhost:8080`(Android模擬器連本機伺服器要用
`ws://10.0.2.2:8080`,用`--dart-define=SERVER_URL=ws://10.0.2.2:8080`帶入)。要接正式站測試:

```bash
flutter run --dart-define=SERVER_URL=wss://your-domain.com/snake
```

CI(`.github/workflows/*.yml`)build正式站版本是靠repo secret `SERVER_URL`帶進去,見下面「發布到
TestFlight」一節需要準備的secrets清單。

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
| `SERVER_URL` | 正式站WebSocket網址,例如 `wss://your-domain.com/snake`(見「開發」一節) |

Team ID 和 Provisioning Profile 名稱workflow會自動從profile檔案裡讀出來,不用另外填。Android APK
build(`.github/workflows/android-apk.yml`)不用簽章secrets,但也要設`SERVER_URL`這個secret。

### 6. 觸發建置
GitHub repo → Actions → iOS TestFlight → Run workflow。macOS runner較慢,約10幾分鐘跑完。
上傳後App Store Connect那邊還要跑幾分鐘processing,跑完會出現在 TestFlight分頁。**第一次**要在
App Store Connect補完「出口合規」等基本問題(沒用到加密的話選No)才會真的推送給測試員的手機。
把自己加進內部測試員名單,手機上裝 TestFlight App 就能收到安裝通知。
