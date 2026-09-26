# 一場對局的流程（對應 Flutter client/lib/game/game_controller.dart 的對戰生命週期）。
#
# 模式：
#   本地單機（debug build 預設）：本地食物產生器；3-2-1 倒數後自動往右走；死亡後 1 秒重新倒數。
#   線上（release build 預設；debug 用 --online / SBG_ONLINE=1 / 勾 online；強制本地 --local，見 app_config.gd）：
#     連伺服器，大廳（ui/lobby_screen.gd）按「隨機配對」（或 M 鍵）排隊、「好友連線」用編號邀請；結束後顯示結算畫面（ui/result_screen.gd）；
#     obstacle_layout → 換地圖；food_spawned → 伺服器食物；match_found → 3-2-1 倒數 → 自動往右走；
#     每秒 snake_position_update；死亡送 death_report 等 game_over。
#     攻擊：攻擊鈕送 attack_request（等結果期間按鈕變灰）；attack_incoming → 閃避視窗（紅框、準星、震動），放開搖桿送 dodge_attempt；
#     attack_result → 命中時雙方停 2 秒 + 橫幅，直接攻擊防守方變長、隨機效果預告 1 秒後生效（加速/暫停/失明）。
#
# 斷線與重連（規格 6.2，照規格不照 Flutter）：
#   - 自己斷線（含切背景）：立刻凍結自己的蛇、顯示「連線中斷,重新連線中...」；net_client 自動重連，
#     伺服器回 identified(reconnected, inRoom) 後等 match_resumed 才恢復。
#   - 對手斷線：收到 opponent_disconnected 凍結自己的蛇、顯示倒數「對手連線中斷,等待重連... N」。
#   - 伺服器 match_resumed（同一則訊息同時送雙方）→ 雙方同時從凍結的位置繼續。
#   - 凍結期間本地的計時（開局倒數、座標回報）一起暫停。
extends Node

const NetClient := preload("res://scripts/net/net_client.gd")
const ServerFoodSource := preload("res://scripts/net/server_food_source.gd")
const Haptics := preload("res://scripts/haptics.gd")
const AppConfig := preload("res://scripts/app_config.gd")
const InviteOverlay := preload("res://scripts/ui/invite_overlay.gd")

const COUNTDOWN_S := 3            # 同 Flutter _startPreGameCountdown
const POSITION_SYNC_S := 1.0      # 同 Flutter _startPositionSync（CONFIG.SNAKE_POSITION_SYNC_MS）
const DEATH_REPLY_TIMEOUT_S := 5.0  # 同 Flutter：death_report 5 秒沒回應就回大廳

enum State { LOBBY, QUEUE, COUNTDOWN, PLAYING, DEAD, OVER }

@export var snake: Node3D
@export var chunk_manager: Node3D
@export var food_manager: Node3D
@export var overlay: CanvasLayer     # ui/status_overlay.gd
@export var result_screen: CanvasLayer   # ui/result_screen.gd（結算畫面）
@export var lobby: CanvasLayer           # ui/lobby_screen.gd（大廳，只有線上模式）
@export var touch_controls: CanvasLayer  # ui/touch_controls.gd（攻擊鈕、放開搖桿閃避）
@export var combat_hud: CanvasLayer      # ui/combat_hud.gd（被攻擊警示、命中橫幅、失明、一次性訊息）
@export var top_hud: CanvasLayer         # ui/top_hud.gd（頂部能量條 + 小地圖）
@export var online := false

var net: Node
var state := State.LOBBY
var my_energy := 0.0
var opp_energy := 0.0
var opponent_id := ""

var _food_src: Node
var _countdown_left := 0.0
var _sync_left := 0.0
var _dead_wait := 0.0
var _self_lost := false            # 自己斷線中
var _opp_grace_left := -1.0        # 對手斷線寬限倒數（秒），<0 = 沒有
var _local_restart := -1.0

# 攻擊與閃避（同 Flutter game_controller.dart；計時都用 _process 的 delta，斷線凍結時不推進）
const HIT_HOLD_S := 2.0            # 命中橫幅期間雙方停住（Flutter _triggerAttackHitBanner 2000ms）
const EFFECT_NAMES := {"speedup": "加速", "pause": "暫停", "blind": "失明"}
const INVITE_FAILED := {
	"target_offline": "對方不在線上（或編號不存在）",
	"target_busy": "對方正在對戰或配對中",
	"self_busy": "你正在配對中，或已經有邀請在等回應",
	"busy": "你正在配對中，或已經有邀請在等回應",
	"cannot_challenge_self": "不能邀請自己",
	"inviter_offline": "對方已經離線",
	"already_in_room": "對方已經在對戰中",
}
var invite_overlay: InviteOverlay
var _invite_name := ""             # 自己送出的邀請：對方的顯示名稱（等待畫面用）
const REJECT_REASONS := {
	"attacker_paused": "你正在暫停中",
	"attack_in_progress": "上一次攻擊還沒結算",
	"target_effect_active": "對手正受到效果影響",
	"no_energy": "能量不足",
	"match_paused": "對局暫停中",
}
var _attack_pending := false       # 送出 attack_request、還沒收到結果（Flutter pendingOutgoingAttack）
var _attacker_by_id := {}          # attackId -> attackerId
var _incoming_id := ""             # 正在被攻擊（閃避視窗中）的 attackId（Flutter incomingAttack）
var _incoming_left := 0.0          # 閃避提示還要顯示多久（視窗 + 0.1 秒）
var _effect := ""                  # 自己身上的效果：speedup / pause / blind（Flutter myEffect）
var _effect_left := 0.0
var _pending_effects: Array = []   # 預告中、還沒生效的效果 [{type, delay, duration}]
var _hit_hold := 0.0               # 命中停頓剩餘秒數

func _ready() -> void:
	var force_local := "--local" in OS.get_cmdline_user_args() + OS.get_cmdline_args()
	online = (online or AppConfig.online_default()) and not force_local
	snake.died.connect(_on_died)
	GameSettings.load_file()
	GameSettings.apply_shadows.call_deferred(get_tree())   # 等場景都 ready（月光、火把）
	lobby.start_pressed.connect(join_queue)
	result_screen.rematch_pressed.connect(join_queue)
	result_screen.lobby_pressed.connect(_to_lobby)
	touch_controls.attack_requested.connect(attack)
	touch_controls.dodge_requested.connect(try_dodge)
	if online:
		net = NetClient.new()
		net.name = "Net"
		add_child(net)
		net.identified.connect(_on_identified)
		net.message_received.connect(_on_message)
		net.connection_lost.connect(_on_connection_lost)
		var sp = lobby.settings_page
		sp.nickname_submitted.connect(func(n): _send_or_notice("set_nickname", {"nickname": n}))
		sp.recovery_code_requested.connect(func(): _send_or_notice("get_recovery_code"))
		sp.restore_submitted.connect(net.restore_account)
		# 好友連線
		invite_overlay = InviteOverlay.new()
		invite_overlay.name = "InviteOverlay"
		add_child(invite_overlay)
		var fp = lobby.friends_page
		fp.refresh_requested.connect(func(): _send_or_notice("get_friends"))
		fp.invite_requested.connect(_send_invite)
		invite_overlay.cancel_pressed.connect(func():
			net.send("invite_cancel")
			invite_overlay.hide_all())
		invite_overlay.accept_pressed.connect(func():
			net.send("invite_accept")
			invite_overlay.hide_all())
		invite_overlay.reject_pressed.connect(func():
			net.send("invite_reject")
			invite_overlay.hide_all())
		lobby.show()
		if net.server_url == "":
			lobby.set_ready(false, "這個版本沒有設定伺服器網址\n（建置時要用 SERVER_URL 產生 build_config.gd）")
			overlay.set_status("無法連線")
			return
		net.connect_to_server()
		overlay.set_status("連線中… %s" % _display_url(net.server_url))
		snake.set_frozen(false)
	else:
		lobby.hide()
		top_hud.show()
		food_manager.use_local_source()
		_begin_countdown()
		overlay.set_status("本地模式")

# ---------- 每幀：倒數 / 座標回報 / 對手寬限倒數（凍結時暫停） ----------
func _process(delta: float) -> void:
	if _opp_grace_left >= 0.0:
		_opp_grace_left = maxf(0.0, _opp_grace_left - delta)
		overlay.show_banner("對手連線中斷,等待重連... %d" % ceili(_opp_grace_left))
	if _local_restart >= 0.0:
		_local_restart -= delta
		if _local_restart < 0.0:
			snake.reset_to(chunk_manager.map.spawn)
			_begin_countdown()
	if _is_frozen():
		return
	_tick_combat(delta)
	match state:
		State.COUNTDOWN:
			_countdown_left -= delta
			overlay.set_countdown(ceili(_countdown_left))
			if _countdown_left <= 0.0:
				overlay.set_countdown(0)
				state = State.PLAYING
				snake.start()
				_sync_left = POSITION_SYNC_S
		State.PLAYING:
			if online:
				_sync_left -= delta
				if _sync_left <= 0.0:
					_sync_left = POSITION_SYNC_S
					var body: Array = snake.occupied_cells()
					net.send("snake_position_update", {"headPos": _pt(body[0]), "bodyCells": body.map(_pt)})
		State.DEAD:
			if online:
				_dead_wait -= delta
				if _dead_wait <= 0.0:
					_to_lobby("連線異常,已返回大廳")

func _is_frozen() -> bool:
	return _self_lost or _opp_grace_left >= 0.0

func _in_match() -> bool:
	return state in [State.COUNTDOWN, State.PLAYING, State.DEAD]

func _begin_countdown() -> void:
	state = State.COUNTDOWN
	_countdown_left = COUNTDOWN_S
	overlay.set_countdown(COUNTDOWN_S)

func _apply_freeze() -> void:
	_sync_snake()
	combat_hud.hold(_is_frozen())
	if not _is_frozen():
		overlay.hide_banner()

# 蛇停住的原因：斷線凍結、對局結束、暫停效果、命中停頓（Flutter _tick() 的 isPaused / _frozenByDisconnect / showAttackHitBanner）
func _sync_snake() -> void:
	snake.set_frozen(_is_frozen() or state == State.OVER or _effect == "pause" or _hit_hold > 0.0)
	snake.set_speedup(_effect == "speedup")
	combat_hud.set_blind(_effect == "blind")
	touch_controls.set_attack_enabled(not _attack_pending)

# ---------- 攻擊與閃避 ----------

func attack(attack_type: String) -> void:
	if not online:
		combat_hud.show_message("本地模式沒有對手，攻擊要在線上對戰才有作用")
		return
	if state != State.PLAYING or _attack_pending or _effect == "pause":
		return
	_attack_pending = true
	net.send("attack_request", {"attackType": attack_type, "clientTime": _now_ms()})
	_sync_snake()

# 放開搖桿：正在被攻擊才送 dodge_attempt（同 Flutter tryDodge）
func try_dodge() -> void:
	if _incoming_id == "":
		return
	net.send("dodge_attempt", {"attackId": _incoming_id, "clientActionTime": _now_ms()})
	_set_incoming("")

func _set_incoming(attack_id: String, window_s := 0.0) -> void:
	_incoming_id = attack_id
	_incoming_left = window_s + 0.1
	combat_hud.set_incoming(attack_id != "")

func _on_attack_result(msg: Dictionary) -> void:
	var attack_id := str(msg.get("attackId", ""))
	var attacker = _attacker_by_id.get(attack_id)
	_attacker_by_id.erase(attack_id)
	var i_attacked: bool = attacker == net.player_id
	var i_defended: bool = attacker != null and not i_attacked
	if i_attacked:
		_attack_pending = false
	_set_incoming("")
	if msg.get("dodged", false):
		combat_hud.show_message("對方閃躲成功" if i_attacked else "閃躲成功!")
		_sync_snake()
		return
	# 命中：雙方都播橫幅並停住 2 秒
	_hit_hold = HIT_HOLD_S
	combat_hud.play_hit_banner()
	var effect_type := str(msg.get("effectType", ""))
	if effect_type == "direct_lengthen":
		if i_defended:
			snake.grow(int(msg.get("lengthenBy", 0)))
		combat_hud.show_message("命中!對手變長了" if i_attacked else "被直接攻擊命中,身體變長了")
	else:
		# 隨機效果：預告 previewDelayMs 後才生效，只套在防守方
		var name: String = EFFECT_NAMES.get(effect_type, effect_type)
		combat_hud.show_message(("命中!對手即將受到「%s」效果" if i_attacked else "即將發動:「%s」效果") % name)
		if i_defended and effect_type != "":
			_pending_effects.append({
				"type": effect_type,
				"delay": float(msg.get("previewDelayMs", 0)) / 1000.0,
				"duration": float(msg.get("effectDuration", 0)) / 1000.0,
			})
	_sync_snake()

func _set_effect(type: String, secs: float) -> void:
	_effect = type
	_effect_left = secs
	_sync_snake()

# 每幀推進攻擊相關計時（斷線凍結時 _process 不會呼叫這裡）
func _tick_combat(delta: float) -> void:
	if _incoming_id != "":
		_incoming_left -= delta
		if _incoming_left <= 0.0:
			_set_incoming("")
	for pe in _pending_effects.duplicate():
		pe["delay"] -= delta
		if pe["delay"] <= 0.0:
			_pending_effects.erase(pe)
			_set_effect(pe["type"], pe["duration"])
	if _effect != "":
		_effect_left -= delta
		if _effect_left <= 0.0:
			_set_effect("", 0.0)
	if _hit_hold > 0.0:
		_hit_hold = maxf(0.0, _hit_hold - delta)
	_sync_snake()

# 開局、結束、回大廳時清掉（Flutter _startMatch 的重設）
func _reset_combat() -> void:
	_attack_pending = false
	_attacker_by_id.clear()
	_set_incoming("")
	_effect = ""
	_effect_left = 0.0
	_pending_effects.clear()
	_hit_hold = 0.0
	combat_hud.clear()
	_sync_snake()

static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

# ---------- 本地模式 ----------
func _on_died(cause: String, head: Vector2i, body: Array) -> void:
	if not online:
		print("死亡: %s（本地模式，1 秒後重新開始）" % cause)
		state = State.DEAD
		_local_restart = 1.0
		return
	# 線上：同 Flutter，送 death_report（bodyCells = 移動前的完整蛇身，含頭），等伺服器 game_over
	state = State.DEAD
	_dead_wait = DEATH_REPLY_TIMEOUT_S
	net.send("death_report", {"cause": cause, "headPos": _pt(head), "bodyCells": body.map(_pt)})

# ---------- 線上模式 ----------
func join_queue() -> void:
	if not online or not net.is_identified or state not in [State.LOBBY, State.OVER]:
		return
	net.send("join_queue")
	state = State.QUEUE
	result_screen.hide()
	lobby.hide()
	top_hud.hide()
	overlay.hide_banner()
	overlay.set_status("配對中…(8 秒沒有真人會配電腦)")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_M:
		join_queue()
	elif event.physical_keycode == KEY_F5 and online and OS.is_debug_build():
		# 電腦測試：模擬 App 切到背景 / 回到前景
		if net.in_background:
			print("[debug] 模擬回到前景")
			net.come_foreground()
		else:
			print("[debug] 模擬切到背景")
			net.go_background()

func _on_identified(msg: Dictionary) -> void:
	var nickname = msg.get("nickname")
	lobby.set_player(net.player_id, msg.get("record", {}) if msg.get("record") is Dictionary else {},
		nickname if nickname is String else "")
	if lobby.settings_page.get_notice() == "繼承中…":   # 失敗的話 restore_failed 先到、已經換成錯誤訊息
		lobby.settings_page.set_notice("已繼承帳號 %s" % net.player_id)
	if msg.get("reconnected", false):
		if _in_match() and msg.get("inRoom", false):
			overlay.show_banner("已重新連線,等待恢復…")   # 等伺服器 match_resumed
			return
		if _in_match():
			# 寬限期已過，對局在斷線期間結束了（伺服器會接著補送 game_over）
			_self_lost = false
			_apply_freeze()
			return
	_self_lost = false
	_apply_freeze()
	if state == State.LOBBY:
		_to_lobby()

func _on_connection_lost() -> void:
	if _in_match():
		_self_lost = true
		_apply_freeze()
		overlay.show_banner("連線中斷,重新連線中...")
	else:
		invite_overlay.hide_all()   # 伺服器那邊的邀請 30 秒後自己逾時
		overlay.set_status("連線中斷,重新連線中...")
		lobby.set_ready(false, "連線中斷,重新連線中...")
		if state == State.QUEUE:
			state = State.LOBBY   # 伺服器會把斷線的人移出佇列
			lobby.show()

# notice：大廳按鈕下方的小字（為什麼回到大廳）
func _to_lobby(notice := "") -> void:
	state = State.LOBBY
	snake.set_frozen(false)
	overlay.set_countdown(0)
	overlay.hide_banner()
	overlay.set_status("")
	result_screen.hide()
	top_hud.hide()
	_reset_combat()
	lobby.set_ready(net.is_identified, notice)
	lobby.show()

func _on_message(msg: Dictionary) -> void:
	match msg.get("type"):
		"obstacle_layout":
			# 房間建立時最先到（在 food_spawned、match_found 之前）
			chunk_manager.load_map_data(msg.map)
			_food_src = ServerFoodSource.new()
			_food_src.name = "ServerFoodSource"
			_food_src.net = net
			food_manager.use_source(_food_src)
			snake.reset_to(chunk_manager.map.spawn)
		"food_spawned":
			if _food_src:
				_food_src.spawn(str(msg.foodId), Vector2i(int(msg.position.x), int(msg.position.y)))
		"match_found":
			opponent_id = str(msg.get("opponentId", ""))
			invite_overlay.hide_all()
			lobby.friends_page.hide()
			result_screen.hide()   # 在結算畫面接受邀請也會直接開局
			my_energy = 0
			opp_energy = 0
			overlay.hide_banner()
			lobby.hide()
			_self_lost = false
			_opp_grace_left = -1.0
			_begin_countdown()
			_reset_combat()
			_apply_freeze()   # 上一場 game_over 時凍結的蛇要解開
			overlay.set_status("")   # 對戰中能量改看頂部 HUD
			top_hud.set_opponent_pos(null)
			top_hud.show()
			_update_status()
		"energy_update":
			if msg.playerId == net.player_id:
				my_energy = msg.energy
			else:
				opp_energy = msg.energy
			_update_status()
		"attack_incoming":
			# 斷線恢復時伺服器會重送同一個 attackId（resumed: true），一樣重新開始閃避視窗
			var attack_id := str(msg.get("attackId", ""))
			_attacker_by_id[attack_id] = str(msg.get("attackerId", ""))
			if msg.get("attackerId") != net.player_id:
				_set_incoming(attack_id, float(msg.get("dodgeWindowMs", 1000)) / 1000.0)
				Haptics.heavy_impact()   # 同 Flutter HapticFeedback.heavyImpact()（規格 9.3）
		"opponent_position_fuzzy":
			var p = msg.get("position")
			if p is Dictionary:
				top_hud.set_opponent_pos(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))
		"attack_result":
			_on_attack_result(msg)
		"attack_rejected":
			_attack_pending = false
			var reason := str(msg.get("reason", ""))
			combat_hud.show_message("攻擊未成立:%s" % REJECT_REASONS.get(reason, reason))
			_sync_snake()
		"self_paused_by_spam":
			# 連續被閃躲 3 次的反噬：自己立刻暫停（規格 4.4）
			var ms := int(msg.get("durationMs", 3000))
			_set_effect("pause", ms / 1000.0)
			combat_hud.show_message("連續被閃躲,自己暫停%d秒" % roundi(ms / 1000.0))
		"opponent_disconnected":
			if _in_match():
				_opp_grace_left = float(msg.get("graceMs", 10000)) / 1000.0
				_apply_freeze()
		"opponent_reconnected":
			pass   # 等 match_resumed 才恢復（雙方同一個時間點）
		"match_resumed":
			print("[net] match_resumed，凍結了 %d ms" % int(msg.get("pausedMs", 0)))
			_self_lost = false
			_opp_grace_left = -1.0
			_apply_freeze()
		"death_report_rejected":
			_to_lobby("死亡回報未通過伺服器驗證,已返回大廳")
		"game_over":
			_self_lost = false
			_opp_grace_left = -1.0
			snake.set_frozen(true)
			overlay.hide_banner()
			overlay.set_countdown(0)
			state = State.OVER
			_reset_combat()
			_show_result(msg)
		"match_waiting":
			pass
		# 好友連線
		"friends":
			lobby.friends_page.set_friends(msg.get("friends") if msg.get("friends") is Array else [])
		"invite_sent":
			invite_overlay.show_outgoing(_invite_name, float(msg.get("timeoutMs", 30000)) / 1000.0)
		"invite_received":
			var nick = msg.get("fromNickname")
			var from := str(msg.get("fromPlayerId", ""))
			invite_overlay.show_incoming(nick if nick is String and nick != "" else "玩家 %s" % from, 30.0)
		"invite_failed":
			_invite_notice("邀請失敗:%s" % INVITE_FAILED.get(str(msg.get("reason", "")), str(msg.get("reason", ""))))
		"invite_rejected":
			_invite_notice("對方拒絕了邀請")
		"invite_timeout":
			_invite_notice("邀請逾時,沒有回應")
		"invite_cancelled":
			_invite_notice("對方撤回了邀請")
		# 設定頁
		"nickname_updated":
			lobby.set_nickname(str(msg.get("nickname", "")), net.player_id)
			lobby.settings_page.set_notice("暱稱已更新")
		"recovery_code":
			lobby.settings_page.show_recovery_code(str(msg.get("recoveryCode", "")))
		"restore_failed":
			lobby.settings_page.set_notice("找不到這個繼承碼")
		"error":
			if msg.get("reason") == "invalid_nickname":
				lobby.settings_page.set_notice("暱稱要 1～12 個字")

# 結算畫面：伺服器 game_over { reason, winnerId, draw, stats: { [playerId]: { gems, survivalMs, maxLength } } }
func _show_result(msg: Dictionary) -> void:
	var won: bool = msg.get("winnerId") == net.player_id
	var kind := "draw" if msg.get("draw", false) else ("win" if won else "lose")
	var subtitle := ""
	match msg.get("reason", ""):
		"double_ko":
			subtitle = "雙方同時陣亡(Double KO)"
		"opponent_left":
			subtitle = "對手離開了對戰" if won else "你離開了對戰"
		"opponent_disconnect_timeout":
			subtitle = "對手斷線超過 10 秒" if won else "斷線超過 10 秒"
	var stats: Dictionary = msg.get("stats") if msg.get("stats") is Dictionary else {}
	var mine: Dictionary = stats.get(net.player_id, {})
	var opp_gems := -1
	for id in stats:
		if id != net.player_id:
			opp_gems = int(stats[id].get("gems", -1))
	result_screen.show_result(kind, subtitle, mine, opp_gems)
	if mine.get("record") is Dictionary:
		lobby.set_record(mine.record)   # 大廳的勝／敗

# 好友連線：送出邀請（好友頁的輸入框或清單），等 invite_sent 再顯示等待畫面
func _send_invite(player_id: String, display_name: String) -> void:
	if state not in [State.LOBBY, State.OVER]:
		return
	_invite_name = display_name
	lobby.friends_page.set_notice("")
	_send_or_notice("challenge_friend", {"targetPlayerId": player_id})

# 邀請結束（失敗／拒絕／逾時／撤回）：關掉彈窗，原因顯示在好友頁與大廳
func _invite_notice(text: String) -> void:
	invite_overlay.hide_all()
	lobby.friends_page.set_notice(text)
	lobby.set_notice(text)

# 設定頁要送伺服器的動作：還沒連上就提示
func _send_or_notice(type: String, payload := {}) -> void:
	if net.is_identified:
		net.send(type, payload)
	else:
		lobby.settings_page.set_notice("還沒連上伺服器")
		lobby.friends_page.set_notice("還沒連上伺服器")

func _update_status() -> void:
	top_hud.set_energy(my_energy, opp_energy)

# 狀態列不攤開完整網址（正式站網址是建置時帶入的），debug build 例外
static func _display_url(url: String) -> String:
	if OS.is_debug_build():
		return url
	return url.get_slice("://", 0) + "://…"

static func _pt(c: Vector2i) -> Dictionary:
	return {"x": c.x, "y": c.y}
