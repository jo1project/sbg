# Godot ↔ Flutter 功能對照表

目標：`godot/` 跟 Flutter 版（`client/`）功能完全一致，連同一台伺服器（`server/`）、訊息格式完全相同。
來源：`docs/snake-battle-spec.md`（下稱「規格」）＋ Flutter／伺服器實際程式碼。
**例外**：斷線與重連（第 1、13 節）已決定照規格 6.2、不照 Flutter；**Flutter 決定不改**，所以這幾列兩邊會不一樣（見文末差異 #1）。

**每次移植都要更新這份表**：改狀態、補上 Godot 實作位置、寫清楚怎麼驗證的。
手動測試步驟見 `godot/TEST_SCENARIOS.md`（表中「驗證方式」欄的編號），除錯指令見 `server/README.md`「開發用除錯指令」，
伺服器自動化測試：`cd server && npm test`（Node 22，見 `server/README.md`）。

狀態定義：

| 狀態 | 意思 |
|---|---|
| 未做 | Godot 還沒有 |
| 進行中 | 有部分實作，或行為跟 Flutter 還有差異 |
| 完成 | Godot 已實作，自測過（腳本/截圖/接本機伺服器），但還沒跟 Flutter 並排跑過手動情境 |
| 已驗證 | 接真的伺服器跑過對應的 TEST_SCENARIOS 情境，結果跟 Flutter 一致 |
| 之後再做 | 已決定這一版不做（Flutter 也還沒有） |

路徑省略前綴：Flutter 在 `client/lib/`，Godot 在 `godot/scripts/`，伺服器在 `server/src/`。
Godot 線上模式：命令列 `-- --online --sbg-server=ws://…`（或環境變數 `SBG_ONLINE=1`、`SBG_SERVER_URL`），預設是本地單機模式。

最後更新：2026-09-24

### 狀態摘要

| 狀態 | 列數 |
|---|---|
| 完成 | 32 |
| 進行中 | 8 |
| 未做 | 22 |
| 已驗證 | 0（還沒跟 Flutter 並排跑手動情境） |
| 之後再做 | 1 列（App 被殺掉後重開回到對戰）＋ 文末差異 #9、#13、#14、#15 |

---

## 1. 連線與重連

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| WebSocket 連線、JSON 訊息 `{type, ...欄位}`、伺服器網址可設定 | `net/socket_service.dart`、`config.dart`（`SERVER_URL`） | `net/net_client.gd` | 完成 | C-01 |
| release build 預設連正式站、網址建置時帶入（不寫在原始碼） | `config.dart` `String.fromEnvironment("SERVER_URL")`＋CI `--dart-define` | `app_config.gd`、`tools/write_build_config.sh`（產生 gitignore 的 `build_config.gd`；release 預設線上模式） | 完成 | C-08 |
| identify：本地保存 playerId、回報 deviceInfo | `game/game_controller.dart` `bootstrap()` `connectAndIdentify()` `_collectDeviceInfo()` | `net/net_client.gd`（`user://sbg_net.cfg`） | 完成 | C-01、C-02 |
| 新帳號還原碼只顯示一次、restore_account 找回帳號 | `main.dart` `_RecoveryCodeOverlay`；`game_controller.dart` `restoreAccount()` | — | 未做 | C-03、C-04 |
| 心跳 ping 每秒一次 | `game_controller.dart` `_startPing()` | `net/net_client.gd` | 完成 | C-05 |
| 心跳逾時：5 秒沒收到訊息 = 斷線（伺服器與 client 兩邊都判） | ⚠ Flutter 沒有 client 端判定；伺服器端 `server.js` 應用層心跳 | `net/net_client.gd` `SILENCE_TIMEOUT`；伺服器 `server.js` | 完成 | D-10、`test/d_reconnect.mjs` |
| 連線失敗：自動重試 | `game_controller.dart` `_onDisconnected()`；`main.dart` `_ConnectGate`（手動按重新連線） | `net/net_client.gd`（每 1 秒自動重試） | 進行中（Godot 沒有「連線失敗」畫面，只有狀態列文字） | C-06 |
| **對戰中斷線 → 自動重連 → 恢復**（規格 6.2） | ⚠ **Flutter 沒有**（斷線後畫面卡住；見差異 #1） | `net/net_client.gd`（自動重連、同 playerId identify）、`game_session.gd`（`_on_identified` 等 `match_resumed`） | 完成 | D-05、D-07～D-11、`test/d_reconnect.mjs` |
| App 切到背景 = 斷線（關連線、不送 leave_room），回前景自動重連 | ⚠ Flutter 目前是送 leave_room 直接判負（`main.dart` `didChangeAppLifecycleState()`，見差異 #1） | `net/net_client.gd` `go_background()` `come_foreground()`（電腦上 F5 模擬） | 完成 | C-07、D-09 |

## 2. 配對

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 隨機配對 join_queue、等待畫面、取消（送 leave_room） | `main.dart` `_LobbyMenu` `_WaitingView`；`game_controller.dart` `joinQueue()` `leaveRoom()` | `game_session.gd` `join_queue()`、`ui/lobby_screen.gd`「開始配對」按鈕（M 鍵） | 進行中（等待畫面維持原樣、沒有「取消」） | M-01、M-02 |
| 大廳畫面：設定齒輪、鑽石（預留）、Logo 橫幅、玩家資訊卡（頭像／暱稱預留、勝／敗）、造型預覽、開始配對、底部導覽（造型／排行榜／好友） | `main.dart` `_LobbyMenu`（Flutter 是按鈕選單，沒有這些區塊；決定只改 Godot） | `ui/lobby_screen.gd`；勝／敗來自伺服器 `identified.record`、`game_over.stats[id].record`（`db.js` `player_records`） | 進行中（設定、鑽石、頭像、暱稱、造型選擇、排行榜、好友都是「敬請期待」） | L-01 ～ L-04 |
| 8 秒沒有真人 → NPC 補位 | 伺服器 `matchmaking.js`（client 只收 match_found） | 同左（Godot 排隊後等 match_found） | 完成 | M-03 |
| 好友 ID 邀請：送出、等待中鎖定、取消、接受/拒絕、30 秒逾時、對方不在線/忙碌 | `main.dart` `_LobbyMenu` `_IncomingInviteOverlay`；`game_controller.dart` `challengeFriend()` 等 | — | 未做 | M-04 ～ M-10 |
| 連線記錄（最近 10 位對手） | `game_controller.dart` `_recordOpponent()`；`main.dart` `_LobbyMenu` | — | 未做 | M-11 |
| 開局：obstacle_layout / food_spawned 先於 match_found 到達 | `game_controller.dart` `_startMatch()` | `game_session.gd` `_on_message()` | 完成 | M-12 |
| 開局 3-2-1 倒數後自動往右走（倒數中可先輸入方向） | `game_controller.dart` `_startPreGameCountdown()`；`screens/game_screen.dart` `_PreGameCountdown` | `game_session.gd` `_begin_countdown()`、`ui/status_overlay.gd`、`snake_train.gd` `start()` | 完成 | M-13 |

## 3. 地圖

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 地圖 JSON 解析（本地檔或伺服器 obstacle_layout） | `models/game_map.dart` | `map_loader.gd`、`chunk_manager.gd` `load_map_data()` | 完成 | G-01 |
| 地板選圖（floor_1 88%、其餘 12%，依座標固定） | `game/map_sprites.dart` `floorFor()` | `map_loader.gd` `floor_variant()`、`map_art.gd` | 完成 | G-02 |
| 障礙物 crate / column / chest / monster（7 種待機動畫） | `widgets/board.dart` `_obstacleImage()` `_drawObstacle()` | `map_art.gd`（chest 是 3D 箱：蓋子 + 正面，`make_chest()`）、`chunk_manager.gd` | 完成 | G-03 |
| 大型怪物 size:"big" 佔兩格、置中 | `models/game_map.dart` `MapObstacle.cells`；`board.dart` | `chunk_manager.gd`、`snake_train.gd`、`local_food_source.gd` | 完成 | G-04 |
| 火把 | `widgets/board.dart` `_paintTorches()` | `chunk_manager.gd` `_plan_torches()`、`map_art.gd` | 完成 | G-05 |

## 4. 移動與死亡判定

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 移動 325ms/格 | `config.dart` `moveTickMs`；`game_controller.dart` `_tick()` | `snake_train.gd` `step_time` | 完成 | S-01 |
| 開局 4 節、spawnPos 往左排、面向右 | `game_controller.dart` `_startMatch()` | `snake_train.gd` `reset_to()` | 完成 | S-02 |
| 轉向：4 方向、死區 10dp、不能 180 度迴轉、轉向佇列 | `widgets/joystick.dart`；`game_controller.dart` `setDirection()`（只存最後一個） | `ui/joystick.gd`、`snake_train.gd` `set_direction()`（佇列，規格 9.2 已寫明） | 完成 | S-03、S-04 |
| 死亡判定：wall / self / obstacle | `game/collision.dart` `checkDeath()` | `snake_train.gd` `_death_cause()` | 完成 | S-05 ～ S-08 |
| 送 death_report（bodyCells 含頭）、5 秒沒回應回大廳、death_report_rejected | `game_controller.dart` `_tick()`、`_onMessage()` | `game_session.gd` `_on_died()`、`_process()` | 完成 | S-09、S-10（`test/s10_fake_death.mjs`） |
| 每秒 snake_position_update | `game_controller.dart` `_startPositionSync()` | `game_session.gd` `_process()` | 完成 | S-11 |
| 暫停解除瞬間前方是身體 → 死亡 | 由暫停 + `_tick()` 自然產生 | —（暫停效果未做） | 未做 | E-07（伺服器端：`test/e07_pause_body_death.mjs`） |

## 5. 食物與能量

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 顯示伺服器給的食物（food_spawned，恆定 3 個） | `game_controller.dart` `myFoods`；`board.dart` `_paintFoods()` | `net/server_food_source.gd`、`food_manager.gd`、`gem.gd`（本地模式用 `local_food_source.gd`） | 完成 | F-01、F-02 |
| 蛇頭進食物格 → 本地移除、能量 +1（樂觀預測）、送 food_eaten_request | `game_controller.dart` `_tick()` | `food_manager.gd` `_on_head_arrived()`、`net/server_food_source.gd` `report_eaten()` | 進行中（沒有樂觀 +1，能量等 energy_update） | F-03、F-04（`test/f04_fake_food.mjs`） |
| energy_update 更新雙方能量 | `game_controller.dart` `_onMessage()` | `game_session.gd`（只顯示在狀態列文字） | 進行中 | F-05 |
| 自己/對手能量條 | `widgets/energy_bar.dart`；`game_screen.dart` `_TopBar` | — | 未做 | U-01 |

## 6. 攻擊

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 兩顆攻擊按鈕：點擊發動、長按顯示說明、放開不發動 | `widgets/attack_button.dart`；`game_screen.dart` `_BottomBelt` | `ui/attack_button.gd`、`ui/touch_controls.gd`（J/K 鍵）→ `attack_requested` 訊號 | 完成 | A-01 |
| 送 attack_request，等結果期間按鈕 disabled（不在本地先扣能量，規格 7.5 已改） | `game_controller.dart` `attack()`、`pendingOutgoingAttack` | `game_session.gd` `attack()`、`_attack_pending`、`touch_controls.gd` `set_attack_enabled()` | 完成（Godot 另外擋「不在 PLAYING 狀態」，開局倒數中按了不送） | A-02、A-08 |
| attack_rejected 顯示原因（含新的 match_paused） | `game_controller.dart` `_onMessage()` | `game_session.gd` `REJECT_REASONS`、`ui/combat_hud.gd` `show_message()` | 完成（**Godot 把 reason 翻成中文**，Flutter 顯示原始英文代碼） | A-05 ～ A-08、D-07 |
| 直接攻擊命中 → 防守方變長 | `game_controller.dart` `_handleAttackResult()` `_growthPending` | `snake_train.gd` `grow()`（每步多一節，尾巴留在原地） | 完成 | A-03 |
| 能量封頂 10、超過保留 | 伺服器 `room.js`、`player.js` | 同左（伺服器） | 完成（伺服器端） | EN-02、EN-03 |

## 7. 閃避

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 被攻擊震動（heavy impact，規格 9.3 已改成要震動） | `game_controller.dart`（`HapticFeedback.heavyImpact()`） | `haptics.gd` `heavy_impact()`（`Input.vibrate_handheld(40ms, 最大強度)`），`game_session.gd` 收到 attack_incoming 時呼叫 | 完成（電腦上只 print；Android 匯出要勾 VIBRATE 權限） | D-01 |
| attack_incoming 警示：紅框 + 準星 + 文字 | `game_screen.dart` `_DodgeAlert` `_AttackCrosshairIndicator` | `ui/combat_hud.gd` `set_incoming()`（準星投影到 3D 蛇頭上方；斷線恢復重送的 attack_incoming 同樣重新顯示） | 完成 | D-01 |
| 放開搖桿 = 閃避（送 dodge_attempt） | `widgets/joystick.dart` `onRelease`；`game_controller.dart` `tryDodge()` | `ui/touch_controls.gd` `dodge_requested` → `game_session.gd` `try_dodge()`（電腦：空白鍵） | 完成 | D-02 |
| 閃避結果訊息 | `game_controller.dart` `_handleAttackResult()` | `game_session.gd` `_on_attack_result()`、`combat_hud.gd` `show_message()`（3 秒） | 完成 | D-02、D-03 |

## 8. 三種負面效果

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 效果在 previewDelayMs 後生效，持續 effectDuration | `game_controller.dart` `_handleAttackResult()` | `game_session.gd` `_pending_effects`、`_tick_combat()`（斷線凍結時不倒數，跟伺服器延長 endsAt 一致） | 完成（**效果名稱翻成中文**：加速／暫停／失明） | E-01 |
| 加速 160ms/格 | `config.dart` `speedupTickMs`；`_tick()` | `snake_train.gd` `set_speedup()` | 完成 | E-02 |
| 暫停：不動、不能轉向、不能攻擊 | `game_controller.dart` `isPaused` | `game_session.gd` `_sync_snake()`（`snake.set_frozen()`）、`attack()` | 完成 | E-03、E-04 |
| 失明：只看得到蛇頭和前方 2 格 | `widgets/board.dart` `_visible()` `_paintBlindMask()` | `ui/combat_hud.gd` `_update_blind()`：3 格（含角色高度）投影到螢幕取凸包，shader 把外面塗黑（邊緣柔化） | 完成 | E-05 |

## 9. 防騷擾懲罰

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 被同一對手閃避累計 3 次 → 自己暫停 3 秒（觸發當下計數歸零，規格 4.4 已改） | 伺服器 `room.js` `registerDodgeSuccess()`；`game_controller.dart` | `game_session.gd`（`self_paused_by_spam` → 暫停效果 + 訊息） | 完成 | P-01 ～ P-03 |

## 10. 攻擊命中橫幅與停頓

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 命中時雙方顯示橫幅 2 秒（規格 4.2 已寫入） | `game_controller.dart` `_triggerAttackHitBanner()`；`game_screen.dart` `_AttackHitBanner` | `ui/combat_hud.gd` `play_hit_banner()`（右→中→左，2 秒；圖 `assets/sprites/attack_banner.png` 跟 Flutter 同一張） | 完成 | H-01 |
| 橫幅期間雙方蛇停止移動（規格 4.2 已寫入；斷線凍結時這 2 秒也要暫停） | `game_controller.dart` `_tick()` | `game_session.gd` `_hit_hold`（斷線凍結時不倒數，橫幅動畫也停住） | 完成（**Godot 停頓期間不接受轉向**，Flutter 可以先輸入；跟斷線凍結的處理一致） | H-02 |

## 11. 對手資訊

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 對手能量條 | `widgets/energy_bar.dart`（`mine: false`） | — | 未做 | U-01 |
| 模糊小地圖：每 2 秒、-2～+2 對稱雜訊（伺服器已改）；對 NPC 不顯示 | `game_screen.dart` `_MiniMap`；伺服器 `room.js` `startMinimapBroadcast()` | — | 未做 | U-02、U-03 |

## 12. 勝負與雙殺

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| game_over：你贏了／你輸了／平手 | `game_screen.dart` `_GameOverOverlay` | `ui/result_screen.gd`、`game_session.gd` `_show_result()` | 完成（**Godot 版較多**，見下） | W-01、W-02 |
| 結算畫面：勝／負／平手配色、2x2 戰績（得分比數＝本場寶石數 我方:對手、收集寶石數、存活時間、最長身長）、「再戰一場」（直接重新排隊）／「返回大廳」 | 沒有（只有文字 + 返回大廳；決定只改 Godot，Flutter 維持原樣） | `ui/result_screen.gd`；數據來自伺服器 `game_over.stats`（`room.js` `matchStats()`，舊版 client 會忽略這個欄位） | 完成 | W-05（`test/w05_match_stats.mjs`） |
| 雙殺 ≤200ms | 伺服器 `room.js` `handleDeathReport()` | 同左 | 完成（伺服器端） | W-03（`test/w03_double_ko.mjs`） |
| 主動離開對戰 → 對手獲勝 | `game_controller.dart` `leaveRoom()` | — | 未做 | W-04 |

## 13. 斷線寬限（規格 6.2，已改成整場凍結）

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 自己斷線：立刻凍結、顯示「連線中斷,重新連線中...」 | ⚠ Flutter 沒有 | `game_session.gd` `_on_connection_lost()` | 完成 | D-04 |
| 對手斷線：凍結、顯示「對手連線中斷,等待重連... N」 | `game_controller.dart` `_startDisconnectCountdown()`；`_DisconnectBanner` | `game_session.gd`（`opponent_disconnected`）、`ui/status_overlay.gd` | 完成 | D-04 |
| 伺服器凍結整場計時（效果、閃避視窗、預告、雙殺等待、小地圖、NPC），恢復時從暫停處繼續 | 伺服器 `room.js` `pause()` `resume()` `setTimer()` | 同左 | 完成 | D-07、`test/d_reconnect.mjs` |
| 同一則 match_resumed 讓雙方同時恢復 | ⚠ Flutter 靠 `opponent_reconnected` 解凍（仍會收到，舊版相容） | `game_session.gd`（`match_resumed`） | 完成 | D-11 |
| 10 秒沒重連 → 斷線方判負；回來時補送 game_over | 伺服器 `server.js` | `game_session.gd` `_on_identified()`（inRoom: false） | 完成 | D-06、D-09 |
| 斷線時閃避視窗開著：恢復後重新給完整 1 秒（重送 `attack_incoming`，`resumed: true`） | 伺服器 `room.js` `resumePendingAttacks()`、`CONFIG.DODGE_WINDOW_ON_RESUME = "full"` | 同左（Godot 收到 `attack_incoming resumed: true`；警示 UI 本身還沒做） | 完成 | D-08、`test/d_reconnect.mjs` |
| App 被系統殺掉後重開，回到進行中的對戰 | — | — | 之後再做 | D-12（備註見下） |

## 14. 其他 UI

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 版面：上方能量條+小地圖、底部搖桿+攻擊鈕、避開安全區域 | `game_screen.dart` | `ui/touch_controls.gd`（底部）、`ui/status_overlay.gd`（狀態列/橫幅） | 進行中（上方能量條、小地圖未做） | U-04 |
| 一次性訊息橫幅（3 秒自動消失） | `game_controller.dart` `_setBanner()`；`_Banner` | — | 未做 | U-05 |
| 設定：光影特效開關 | `screens/settings_screen.dart` | — | 未做 | U-06 |
| 開發用除錯指令＋除錯面板 | （Flutter 沒有） | `debug/debug_panel.gd`；伺服器 `debug.js` | 完成 | T-01 ～ T-04 |

---

## 規格 vs Flutter 實作的差異：決定與處理狀態

| # | 項目 | 決定 | 處理狀態 |
|---|---|---|---|
| 1 | 對戰中斷線重連 | **照規格 6.2**：自動重連、恢復對戰 | 伺服器已改；Godot 已做；**Flutter 待改**（見下方「Flutter 最小改動範圍」） |
| 2 | 斷線時凍結 | **照規格 6.2**：雙方都凍結、伺服器暫停所有計時、同一則 match_resumed 同時恢復 | 伺服器已改；Godot 已做；Flutter 待改（目前只有沒斷線的那方凍結） |
| 3 | 閃躲視窗 | 照現況 1000ms | 規格 1、2.1、4.2、9.1 已改成 1 秒 |
| 4 | 震動 | 保留震動 | 規格 9.3 已改；Godot 已做（`haptics.gd`） |
| 5 | 防騷擾計數歸零 | 照現況：觸發當下歸零 | 規格 4.4 已改 |
| 6 | 攻擊時本地先扣能量 | 照現況：不先扣，等 energy_update | 規格 7.5 已改 |
| 7 | 轉向輸入 | Godot 轉向佇列保留 | 規格 9.2 已補說明（Flutter 只存最後一個，刻意的差異） |
| 8 | 開局 | 照 Flutter：3-2-1 倒數後自動往右走 | Godot 已改 |
| 9 | 長按說明顯示數值 | — | **之後再做** |
| 10 | 命中後雙方橫幅與停 2 秒 | 照現況 | 規格 4.2、9.3 已寫入 |
| 11 | 小地圖雜訊 | 改成對稱 -2～+2 | 伺服器已改（`room.js`）；規格 2.1 已改 |
| 12 | death_report 的 bodyCells | 含頭 | `events.js` 註解已改；規格 7.4 已寫明 |
| 13 | 閃躲成功格擋特效 | — | **之後再做** |
| 14 | 能量條滿量脈動 | — | **之後再做** |
| 15 | 警示音效 | — | **之後再做** |
| 16 | 斷線時閃避視窗開著 | **已決定：重新給完整 1 秒** | 伺服器 `CONFIG.DODGE_WINDOW_ON_RESUME = "full"`；規格 6.2、D-08 已更新 |
| 17 | App 被系統殺掉後重開回到對戰 | **之後再做** | 見下方備註 |
| 18 | 心跳逾時 | **5 秒**（Flutter 不改、沒有重連，3 秒太容易把網路抖動變成判負） | 伺服器 `CONFIG.HEARTBEAT_TIMEOUT_MS = 5000`、Godot `net_client.gd` `SILENCE_TIMEOUT = 5.0`；規格 6.2、7.4 已更新 |

### 備註：App 被殺掉後重開回到對戰（#17，之後再做）

現在重連只靠 client 記憶體裡的狀態，App 程序還活著（切背景、網路斷掉）才能恢復。App 被系統殺掉重開時需要：

1. **伺服器在重連時送狀態快照**（例如新訊息 `match_state`，接在 `identified { reconnected: true, inRoom: true }` 之後）：
   - 地圖（伺服器有 `room.maps[playerId]`，現在只在開局送一次 `obstacle_layout`）
   - 場上的食物（`room.foods[playerId]`，現在只送 `food_spawned` 增量）
   - 雙方能量、自己生效中的效果與剩餘時間、進行中還沒結算的攻擊（對手打過來的 / 自己打出去的）
   - 對手 ID、房間 ID、開局倒數是否已結束
2. **`snake_position_update` 加欄位**：現在只有 `headPos`、`bodyCells`，要再加**移動方向**（含轉向佇列）和**待增長節數**（直接攻擊命中還沒長完的格數），
   伺服器才能把完整的蛇還給重開的 client。回報間隔是 1 秒，重開後的位置最多差 1 秒的移動量（凍結期間不會再動，所以斷線當下最後一次回報要在凍結前送出）。
3. client 端：開機時如果本地記得「上次在對戰中」，identify 後收到 `match_state` 就直接進對戰畫面、套用快照、等 `match_resumed`。

### Flutter 最小改動範圍（配合 #1、#2）——**已決定不改**，留作參考

伺服器改完之後，Flutter 還能連、能打，但斷線相關的行為跟 Godot 不同：

- **伺服器現在會凍結整場**，Flutter 斷線的那一方卻不知道要凍結（它的蛇計時器已停，但重連不回來），對手會看到凍結倒數 10 秒後獲勝——結果跟以前一樣，只是多等了凍結時間。
- **心跳縮短成 5 秒**（原本最多 60 秒）：Flutter 已經每秒 ping，正常情況不受影響；但 Flutter 沒有重連，一次 5 秒以上的網路停頓就會變成 10 秒後判負。因此心跳設 5 秒而不是 3 秒（#18）。

要讓 Flutter 跟 Godot 行為一致，最小要改這些（都在 `game/game_controller.dart`、`main.dart`、`net/socket_service.dart`）：

1. `main.dart` `didChangeAppLifecycleState()`：`paused` 時改成關閉 WebSocket（不送 leave_room）；`resumed` 時重連。
2. `game_controller.dart` `_onDisconnected()`：對戰中不要停掉對局狀態，改成凍結（跟 `_frozenByDisconnect` 同一套）＋顯示「連線中斷,重新連線中...」，並排程自動重連（`connectAndIdentify()` 重試）。
3. `identified` 處理：`reconnected: true` 時不要重設對局，`inRoom: false` 時等補送的 `game_over`。
4. 新增 `match_resumed` 處理：解除凍結（取代現在收到 `opponent_reconnected` 就解凍）；凍結期間要一起暫停的本地計時：移動 tick、座標同步、開局倒數、命中橫幅的 2 秒、效果的剩餘時間（`myEffect.endsAt` 要往後延 `pausedMs`）、閃躲警示的本地計時。
5. `socket_service.dart`：5 秒沒收到任何訊息就自行判定斷線（不然網路靜默斷掉時 Flutter 可能好幾十秒才發現）。

預估改動：`game_controller.dart` 約 60～80 行、`main.dart` 約 10 行、`socket_service.dart` 約 15 行，不需要改畫面結構。
