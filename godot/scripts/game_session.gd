# 一場對局的流程（對應 Flutter client/lib/game/game_controller.dart 的對戰生命週期）。
#
# 模式：
#   本地單機（debug build 預設）：本地食物產生器；3-2-1 倒數後自動往右走；死亡後 1 秒重新倒數。
#   線上（release build 預設；debug 用 --online / SBG_ONLINE=1 / 勾 online；強制本地 --local，見 app_config.gd）：
#     連伺服器，按「隨機配對」（或 M 鍵）排隊；
#     obstacle_layout → 換地圖；food_spawned → 伺服器食物；match_found → 3-2-1 倒數 → 自動往右走；
#     每秒 snake_position_update；死亡送 death_report 等 game_over。
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

const COUNTDOWN_S := 3            # 同 Flutter _startPreGameCountdown
const POSITION_SYNC_S := 1.0      # 同 Flutter _startPositionSync（CONFIG.SNAKE_POSITION_SYNC_MS）
const DEATH_REPLY_TIMEOUT_S := 5.0  # 同 Flutter：death_report 5 秒沒回應就回大廳

enum State { LOBBY, QUEUE, COUNTDOWN, PLAYING, DEAD, OVER }

@export var snake: Node3D
@export var chunk_manager: Node3D
@export var food_manager: Node3D
@export var overlay: CanvasLayer     # ui/status_overlay.gd
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

func _ready() -> void:
	var force_local := "--local" in OS.get_cmdline_user_args() + OS.get_cmdline_args()
	online = (online or AppConfig.online_default()) and not force_local
	snake.died.connect(_on_died)
	overlay.match_pressed.connect(join_queue)
	if online:
		net = NetClient.new()
		net.name = "Net"
		add_child(net)
		net.identified.connect(_on_identified)
		net.message_received.connect(_on_message)
		net.connection_lost.connect(_on_connection_lost)
		if net.server_url == "":
			overlay.show_banner("這個版本沒有設定伺服器網址\n（建置時要用 SERVER_URL 產生 build_config.gd）")
			overlay.set_status("無法連線")
			return
		net.connect_to_server()
		overlay.set_status("連線中… %s" % _display_url(net.server_url))
		snake.set_frozen(false)
	else:
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
					overlay.show_banner("連線異常,已返回大廳")
					_to_lobby()

func _is_frozen() -> bool:
	return _self_lost or _opp_grace_left >= 0.0

func _in_match() -> bool:
	return state in [State.COUNTDOWN, State.PLAYING, State.DEAD]

func _begin_countdown() -> void:
	state = State.COUNTDOWN
	_countdown_left = COUNTDOWN_S
	overlay.set_countdown(COUNTDOWN_S)

func _apply_freeze() -> void:
	snake.set_frozen(_is_frozen())
	if not _is_frozen():
		overlay.hide_banner()

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
	overlay.show_match_button(false)
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
		overlay.set_status("連線中斷,重新連線中...")
		overlay.show_match_button(false)
		if state == State.QUEUE:
			state = State.LOBBY   # 伺服器會把斷線的人移出佇列

func _to_lobby() -> void:
	state = State.LOBBY
	snake.set_frozen(false)
	overlay.set_countdown(0)
	overlay.show_match_button(true)
	overlay.set_status("ID %s · 按「隨機配對」（或 M 鍵）開始" % net.player_id)

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
			my_energy = 0
			opp_energy = 0
			overlay.hide_banner()
			overlay.show_match_button(false)
			_self_lost = false
			_opp_grace_left = -1.0
			_apply_freeze()   # 上一場 game_over 時凍結的蛇要解開
			_update_status()
			_begin_countdown()
		"energy_update":
			if msg.playerId == net.player_id:
				my_energy = msg.energy
			else:
				opp_energy = msg.energy
			_update_status()
		"attack_incoming":
			if msg.attackerId != net.player_id:
				Haptics.heavy_impact()   # 同 Flutter HapticFeedback.heavyImpact()（規格 9.3）
				print("[attack] 被攻擊了（%s）" % msg.attackType)
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
			overlay.show_banner("死亡回報未通過伺服器驗證,已返回大廳")
			_to_lobby()
		"game_over":
			_self_lost = false
			_opp_grace_left = -1.0
			snake.set_frozen(true)
			var text := "平手(Double KO)" if msg.get("draw", false) else ("你贏了!" if msg.get("winnerId") == net.player_id else "你輸了")
			overlay.show_banner("%s\n（%s）" % [text, msg.get("reason", "")])
			overlay.set_countdown(0)
			state = State.OVER
			overlay.show_match_button(true)
		"match_waiting":
			pass
		"attack_rejected":
			print("[attack] 攻擊未成立: %s" % msg.get("reason"))

func _update_status() -> void:
	overlay.set_status("能量 %d · 對手 %s 能量 %d" % [int(my_energy), opponent_id, int(opp_energy)])

# 狀態列不攤開完整網址（正式站網址是建置時帶入的），debug build 例外
static func _display_url(url: String) -> String:
	if OS.is_debug_build():
		return url
	return url.get_slice("://", 0) + "://…"

static func _pt(c: Vector2i) -> Dictionary:
	return {"x": c.x, "y": c.y}
