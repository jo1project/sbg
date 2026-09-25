# Godot client(HD-2D 版)

功能對照與移植進度見 `PARITY.md`,手動測試情境見 `TEST_SCENARIOS.md`。

## 執行模式與伺服器網址

設定集中在 `scripts/app_config.gd`:

| | debug build(編輯器、debug 匯出) | release build |
|---|---|---|
| 預設模式 | 本地單機 | **線上** |
| 預設伺服器網址 | `ws://localhost:8080` | 建置時帶入的 `SERVER_URL`(沒帶就顯示「沒有設定伺服器網址」) |

覆寫(優先於預設):`--online` / `--local`(或環境變數 `SBG_ONLINE=1` / `0`)、`--sbg-server=ws://...`(或 `SBG_SERVER_URL`)。
命令列參數要放在 `--` 後面,例如 `godot --path godot -- --online --sbg-server=ws://127.0.0.1:8080`。
在編輯器裡想用 release 的預設值測試:`-- --sbg-release-defaults`。

## 建置 release(正式站)

正式站網址不寫在原始碼裡(repo 是 public;對應 Flutter 的 `--dart-define=SERVER_URL`),匯出前產生 `build_config.gd`:

```bash
SERVER_URL=wss://your-domain.com/snake godot/tools/write_build_config.sh   # 產生 godot/build_config.gd(已 gitignore)
godot --headless --path godot --export-release "<preset 名稱>" <輸出路徑>
rm godot/build_config.gd                                                    # 本機建置完可以刪掉
```

CI 用跟 Flutter 同一個 repo secret `SERVER_URL`。`build_config.gd` 是一般腳本,匯出時會自動包進去,不用改 export filter。

Android 匯出要在 export preset 勾 `VIBRATE` 權限(被攻擊震動,見 `scripts/haptics.gd`)。
