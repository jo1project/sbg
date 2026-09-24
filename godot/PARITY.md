# Godot ↔ Flutter 功能對照表

目標：`godot/` 跟 Flutter 版（`client/`）功能完全一致，連同一台伺服器（`server/`）、訊息格式完全相同。
來源：`docs/snake-battle-spec.md`（下稱「規格」）＋ Flutter／伺服器實際程式碼。

**每次移植都要更新這份表**：改狀態、補上 Godot 實作位置、寫清楚怎麼驗證的。
手動測試步驟見 `godot/TEST_SCENARIOS.md`（表中「情境」欄的編號），除錯指令見 `server/README.md`「開發用除錯指令」。

狀態定義：

| 狀態 | 意思 |
|---|---|
| 未做 | Godot 還沒有 |
| 進行中 | 有部分實作（例如只有本地版、還沒接伺服器），或行為跟 Flutter 還有差異 |
| 完成 | Godot 已實作，在 Godot 內自測過（腳本/截圖），但還沒跟伺服器＋Flutter 對照跑過情境 |
| 已驗證 | 接真的伺服器跑過對應的 TEST_SCENARIOS 情境，結果跟 Flutter 一致 |

路徑省略前綴：Flutter 在 `client/lib/`，Godot 在 `godot/scripts/`，伺服器在 `server/src/`。

最後更新：2026-09-24（Godot 還沒接伺服器，所以目前沒有任何一列是「已驗證」）

---

## 1. 連線與重連

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| WebSocket 連線、JSON 訊息 `{type, ...欄位}`、伺服器網址用 build-time 設定 | `net/socket_service.dart`、`config.dart`（`SERVER_URL`） | — （只有除錯面板 `debug/debug_panel.gd` 有獨立的除錯連線） | 未做 | 情境 C-01 |
| identify：本地保存 playerId、回報 deviceInfo | `game/game_controller.dart` `bootstrap()` `connectAndIdentify()` `_collectDeviceInfo()` | — | 未做 | C-01、C-02 |
| 新帳號還原碼只顯示一次、restore_account 找回帳號 | `main.dart` `_RecoveryCodeOverlay`；`game_controller.dart` `restoreAccount()` | — | 未做 | C-03、C-04 |
| 心跳 ping 每秒一次（伺服器算 RTT） | `game_controller.dart` `_startPing()` | — | 未做 | C-05 |
| 連線失敗/斷線：大廳顯示「重新連線」 | `game_controller.dart` `_onDisconnected()`；`main.dart` `_ConnectGate` | — | 未做 | C-06 |
| **對戰中自己斷線、10 秒內重連繼續** | ⚠ **Flutter 沒有實作**：斷線後停掉移動計時器，對戰畫面卡住，重新連線按鈕只在大廳（伺服器端有支援：同 playerId 在寬限期內 identify 會回 `reconnected: true`） | — | 未做 | D-05（目前 Flutter 預期會失敗，見文末差異 #1） |
| App 切到背景 → 主動 leave_room（避免殭屍連線卡 busy） | `main.dart` `didChangeAppLifecycleState()` | — | 未做 | C-07 |

## 2. 配對

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 隨機配對 join_queue、等待畫面、取消（送 leave_room） | `main.dart` `_LobbyMenu` `_WaitingView`；`game_controller.dart` `joinQueue()` `leaveRoom()` | — | 未做 | M-01、M-02 |
| 8 秒沒有真人 → NPC 補位 | 伺服器 `matchmaking.js` `joinQueue()`（client 只收 match_found） | — | 未做 | M-03 |
| 好友 ID 邀請：送出、等待中鎖定、取消、被邀請方接受/拒絕、30 秒逾時、對方不在線/忙碌 | `main.dart` `_LobbyMenu` `_IncomingInviteOverlay`；`game_controller.dart` `challengeFriend()` `acceptInvite()` `rejectInvite()` `cancelInvite()`、`invite_*` 訊息處理 | — | 未做 | M-04 ～ M-10 |
| 連線記錄（最近 10 位對手） | `game_controller.dart` `_recordOpponent()`；`main.dart` `_LobbyMenu` | — | 未做 | M-11 |
| 開局：obstacle_layout / food_spawned 先於 match_found 到達，不能被清掉 | `game_controller.dart` `_startMatch()` 註解 | — | 未做 | M-12 |
| 開局 3-2-1 倒數後才開始移動 | `game_controller.dart` `_startPreGameCountdown()`；`screens/game_screen.dart` `_PreGameCountdown` | `snake_train.gd`：**暫時用「等第一次方向輸入才開始走」代替** | 進行中 | M-13 |

## 3. 地圖

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 地圖 JSON 解析（rooms/corridors 含端點、spawnPos、obstacles） | `models/game_map.dart` | `map_loader.gd`（目前讀本地 `assets/maps/map_03.json`，還沒從 obstacle_layout 收） | 進行中 | G-01 |
| 地板選圖（floor_1 88%、其餘 12%，依座標固定） | `game/map_sprites.dart` `floorFor()` | `map_loader.gd` `floor_variant()`、`map_art.gd` | 完成 | G-02 |
| 障礙物 crate / column / monster（7 種待機動畫） | `widgets/board.dart` `_obstacleImage()` `_drawObstacle()` | `map_art.gd`、`chunk_manager.gd` `_add_map_obstacle()` | 完成 | G-03 |
| 障礙物 **chest（寶箱）** | `game/map_sprites.dart`（`chest_full_open_anim_f0.png`） | ⚠ 沒有：遇到會印警告並用 crate 代替 | 未做 | G-03 |
| 大型怪物 size:"big" 佔 (x,y)+(x+1,y) 兩格、置中 | `models/game_map.dart` `MapObstacle.cells`；`board.dart` `_drawObstacle()` | `chunk_manager.gd`、`snake_train.gd` `_death_cause()`、`local_food_source.gd` | 完成 | G-04 |
| 火把（房間左右邊緣各 ≤3 支、柱頂各 1 支） | `widgets/board.dart` `_paintTorches()` | `chunk_manager.gd` `_plan_torches()`、`map_art.gd` `make_torch()`（3D 版） | 完成 | G-05 |

## 4. 移動與死亡判定

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 移動 325ms/格 | `config.dart` `moveTickMs`；`game_controller.dart` `_tick()` | `snake_train.gd` `step_time`（量測 3.07 格/秒） | 完成 | S-01 |
| 開局 4 節、spawnPos 往左排、面向右 | `game_controller.dart` `_startMatch()`、`config.dart` `initialSnakeLength` | `snake_train.gd` `_reset()` | 完成 | S-02 |
| 轉向：搖桿 4 方向切法、死區 10dp、不能 180 度迴轉、下一格生效 | `widgets/joystick.dart`；`game_controller.dart` `setDirection()` | `ui/joystick.gd`、`ui/touch_controls.gd`、`snake_train.gd` `set_direction()` | 進行中（差異：Godot 用轉向佇列，見差異 #7） | S-03、S-04 |
| 死亡判定：出界/虛空=wall、撞身體（尾巴那格不算）=self、障礙物（含大型怪物第二格）=obstacle | `game/collision.dart` `checkDeath()` | `snake_train.gd` `_death_cause()` | 完成（只做本地判定：印「死亡」並重新開始） | S-05 ～ S-08 |
| 送 death_report（cause、headPos、bodyCells）、5 秒沒回應強制回大廳、death_report_rejected | `game_controller.dart` `_tick()`、`_onMessage()` | — | 未做 | S-09、S-10 |
| 每秒 snake_position_update（headPos、bodyCells） | `game_controller.dart` `_startPositionSync()` | — | 未做 | S-11 |
| 暫停解除瞬間前方是身體 → 死亡 | 由暫停 + `_tick()` 自然產生 | — | 未做 | E-07 |

## 5. 食物與能量

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 顯示伺服器給的食物（food_spawned，恆定 3 個） | `game_controller.dart` `myFoods`；`board.dart` `_paintFoods()` | `food_manager.gd`、`gem.gd`；來源介面 `food_source.gd`（目前用本地產生器 `local_food_source.gd`） | 進行中 | F-01、F-02 |
| 蛇頭進食物格 → 本地移除、能量 +1（樂觀預測）、送 food_eaten_request | `game_controller.dart` `_tick()` | `food_manager.gd` `_on_head_arrived()`（本地），`report_eaten()` 還沒送伺服器；能量還沒做 | 進行中 | F-03、F-04 |
| energy_update 更新雙方能量（以伺服器為準） | `game_controller.dart` `_onMessage()` | — | 未做 | F-05 |
| 自己能量條（綠<50%/黃<100%/紅、滿量白框）、對手能量條（一律黃）、數值 | `widgets/energy_bar.dart`；`game_screen.dart` `_TopBar` | — | 未做 | U-01 |

## 6. 攻擊

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 兩顆攻擊按鈕：點擊發動、長按顯示說明、放開不發動 | `widgets/attack_button.dart`；`game_screen.dart` `_BottomBelt` | `ui/attack_button.gd`、`ui/touch_controls.gd`（J/K 鍵），目前只 print | 進行中 | A-01 |
| 送 attack_request（attackType、clientTime），等結果期間按鈕 disabled、暫停中不能發 | `game_controller.dart` `attack()`、`pendingOutgoingAttack` | — | 未做 | A-02、A-08 |
| attack_rejected 顯示原因 | `game_controller.dart` `_onMessage()` | — | 未做 | A-05 ～ A-08 |
| 直接攻擊命中 → 防守方變長 lengthenBy 格 | `game_controller.dart` `_handleAttackResult()` `_growthPending` | — （`snake_train.gd` 目前不會變長） | 未做 | A-03 |
| 能量封頂 10、超過 10 的部分保留 | 伺服器 `room.js`、`player.js`（client 只顯示） | — | 未做 | EN-02、EN-03 |

## 7. 閃避

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| attack_incoming 警示：紅色外框 + 蛇頭上方閃爍準星 + 「被攻擊了！放開搖桿閃躲」 + 震動 | `game_screen.dart` `_DodgeAlert` `_AttackCrosshairIndicator`；`game_controller.dart`（`HapticFeedback`） | — | 未做 | D-01 |
| 放開搖桿 = 閃避（送 dodge_attempt，有來襲攻擊時才送） | `widgets/joystick.dart` `onRelease`；`game_controller.dart` `tryDodge()` | `ui/touch_controls.gd` `_on_joystick_released()`（空的 hook） | 進行中 | D-02 |
| 閃避結果訊息（「閃躲成功！」/「對方閃躲成功」） | `game_controller.dart` `_handleAttackResult()` | — | 未做 | D-02、D-03 |

## 8. 三種負面效果

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 效果在 previewDelayMs（1 秒）後才生效，持續 effectDuration | `game_controller.dart` `_handleAttackResult()` | — | 未做 | E-01 |
| 加速：160ms/格 | `config.dart` `speedupTickMs`；`game_controller.dart` `_tick()` | — | 未做 | E-02 |
| 暫停：不動、不能轉向、不能攻擊 | `game_controller.dart` `isPaused`、`setDirection()`、`attack()`、`_tick()` | — | 未做 | E-03、E-04 |
| 失明：只看得到蛇頭和前方 2 格 | `widgets/board.dart` `_visible()` `_paintBlindMask()` | — | 未做 | E-05 |

## 9. 防騷擾懲罰

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 被同一對手閃避累計 3 次 → self_paused_by_spam，自己暫停 3 秒 | 伺服器 `room.js` `registerDodgeSuccess()`；Flutter `game_controller.dart`（套用 pause + 橫幅） | — | 未做 | P-01 ～ P-03 |

## 10. 攻擊命中橫幅與暫停

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 命中（沒閃掉）時雙方畫面顯示橫幅 2 秒（右→中→左） | `game_controller.dart` `_triggerAttackHitBanner()`；`game_screen.dart` `_AttackHitBanner`、`assets/sprites/attack_banner.png` | — | 未做 | H-01 |
| 橫幅期間雙方蛇都停止移動（client 規則，規格沒寫） | `game_controller.dart` `_tick()` | — | 未做 | H-02 |

## 11. 對手資訊

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 對手能量條 | `widgets/energy_bar.dart`（`mine: false`） | — | 未做 | U-01 |
| 模糊小地圖：opponent_position_fuzzy 每 2 秒、±2 格雜訊；對 NPC 時不顯示 | `game_screen.dart` `_MiniMap`；伺服器 `room.js` `startMinimapBroadcast()` | — | 未做 | U-02、U-03 |

## 12. 勝負與雙殺

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| game_over：你贏了／你輸了／平手（Double KO），返回大廳 | `game_screen.dart` `_GameOverOverlay`；`game_controller.dart` | — | 未做 | W-01 ～ W-04 |
| 雙方死亡回報相差 ≤200ms → 平手 | 伺服器 `room.js` `handleDeathReport()` | — | 未做 | W-03 |
| 主動離開對戰 → 對手獲勝（opponent_left） | `game_controller.dart` `leaveRoom()` | — | 未做 | W-04 |

## 13. 斷線寬限

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 對手斷線：顯示「對手連線中斷,等待重連... N」倒數、自己的蛇凍結 | `game_controller.dart` `_startDisconnectCountdown()`；`game_screen.dart` `_DisconnectBanner` | — | 未做 | D-04 |
| 對手重連：解除凍結 | `game_controller.dart`（`opponent_reconnected`） | — | 未做 | D-05 |
| 10 秒沒重連 → 斷線方判負（opponent_disconnect_timeout） | 伺服器 `server.js` | — | 未做 | D-06 |

## 14. 其他 UI

| 功能 | Flutter 實作位置 | Godot 實作位置 | 狀態 | 驗證方式 |
|---|---|---|---|---|
| 版面：上方能量條+小地圖、底部搖桿+兩顆攻擊鈕、半透明、避開安全區域 | `game_screen.dart` | `ui/touch_controls.gd`（底部已完成；上方資訊列未做） | 進行中 | U-04 |
| 一次性訊息橫幅（3 秒自動消失，可手動關） | `game_controller.dart` `_setBanner()`；`game_screen.dart` `_Banner` | — | 未做 | U-05 |
| 設定：光影特效開關（低階裝置） | `screens/settings_screen.dart`、`config.dart` `highQualityLighting` | — | 未做 | U-06 |
| 開發用除錯指令＋除錯面板 | （Flutter 沒有） | `debug/debug_panel.gd`（只在 debug build）；伺服器 `debug.js` | 完成 | 見 TEST_SCENARIOS「除錯工具自檢」 |

---

## 規格 vs Flutter 實作的差異（移植前要決定照哪個）

「跟 Flutter 一致」和「跟規格一致」在下面這些地方不是同一件事。Godot 預設照 **Flutter + 伺服器實際行為**（這樣同一台伺服器兩個 client 行為才會一樣），有要改的話兩邊一起改。

| # | 項目 | 規格寫的 | Flutter / 伺服器實際 |
|---|---|---|---|
| 1 | 對戰中斷線重連 | 6.2：10 秒內重連，恢復完整狀態繼續 | 伺服器有支援；**Flutter 沒做**（斷線後畫面卡住、App 切背景直接 leave_room 判負） |
| 2 | 斷線時凍結 | 6.2：雙方蛇皆靜止 | 伺服器不凍結時鐘；只有「沒斷線的那方」client 自己凍結（`_frozenByDisconnect`） |
| 3 | 閃躲視窗 | 1、2.1、4.2 寫 0.3 秒 | `CONFIG.DODGE_WINDOW_MS = 1000`（7.4/7.5 節也寫 1 秒） |
| 4 | 震動 | 9.3：不使用震動 | Flutter 被攻擊時 `HapticFeedback.heavyImpact()` |
| 5 | 防騷擾計數歸零 | 4.4：暫停**執行完畢後**歸零 | 伺服器在**觸發的當下**就歸零 |
| 6 | 攻擊時本地先扣能量 | 7.5 步驟 1：客戶端立即扣能量 | Flutter 不先扣，等 energy_update |
| 7 | 轉向輸入 | 規格沒寫 | Flutter 只存最後一個方向；**Godot 改成佇列（依序套用）**，是依需求刻意的差異 |
| 8 | 開局 | 規格沒寫 | Flutter 3-2-1 倒數後自動往右走；Godot 目前等第一次輸入 |
| 9 | 長按說明 | 9.2：顯示效果內容與數值（如「持續 2s」） | Flutter 是固定文字（「直接攻擊 · 對手變長」「隨機效果 · 加速/暫停/致盲」） |
| 10 | 命中後雙方停 2 秒 | 規格沒寫 | Flutter 命中橫幅期間雙方都停止移動 |
| 11 | 小地圖雜訊 | 2.1：約半個地圖格；7.3：±2 格 | 伺服器 `Math.floor((random*2-1)*2)`，實際是 **-2～+1 格**（不對稱，+2 幾乎不會出現） |
| 12 | death_report 的 bodyCells | `events.js` 註解寫「不含頭」 | Flutter 送整條（含頭），伺服器驗證不受影響 |
| 13 | 閃躲成功特效 | 4.2：格擋特效 | Flutter 只有文字橫幅 |
| 14 | 能量條滿量 | 2.1：脈動提示 | Flutter 只有靜態白框（README 已知限制） |
| 15 | 警示音效 | 2.1、9.3：音效 | 還沒做（README 已知限制） |
