# 貪食蛇對戰 — Flutter 客戶端

依照《手機連線對戰貪食蛇 — 遊戲規格文件》(`../docs/snake-battle-spec.md`)實作的第一版客戶端。
連線協定對應 `../server/src/events.js`。

## 目前已實作

- 連線/身份綁定(identify)、新帳號一次性還原碼提示、換裝置還原碼找回
- 隨機配對、好友ID邀請(發送/接受/拒絕/取消/逾時)
- 本地預測的蛇身移動與碰撞(撞牆/撞自己),死亡後送 `death_report` 給伺服器驗證
- 吃食物本地樂觀更新能量,由伺服器 `energy_update` 校正權威值
- 攻擊(直接/隨機效果)發動、0.3秒閃躲(點擊搖桿區域觸發)
- 對手能量條、模糊小地圖(每2秒更新)、攻擊警示外框
- Random效果套用(加速影響移動間隔、暫停凍結操作、致盲遮蔽畫面)
- 防Spam自懲、對手斷線倒數、Double KO/勝負結果畫面

## 已知限制 / 未做

- 音效、震動、警示動畫節奏、攻擊動畫視覺 — 規格文件9.3/9.4節註明待後續設計,先卡流程位置不做視覺
- 能量滿量的脈動提示 — 目前只用靜態白框示意
- 搖桿死區/靈敏度、觸控熱區大小 — 待實機測試調整(規格9.2節)
- 沒有做 web/desktop 支援(僅 iOS/Android,與規格1節一致);WebSocket 用 `dart:io`,若未來要支援 web 需換成 `web_socket_channel`

## 開發

```bash
flutter pub get
flutter test      # 跑 test/collision_test.dart(碰撞判定邏輯的自我檢查)
flutter analyze
flutter run        # 需要實機或模擬器(iOS/Android)
```

伺服器位址在App內的連線畫面輸入(存於本機 `shared_preferences`),本機測試預設 `ws://localhost:8080`;
Android模擬器連本機伺服器要用 `ws://10.0.2.2:8080`。
