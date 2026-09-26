# 跟伺服器的 WebSocket 連線（訊息格式同 Flutter client/lib/net/socket_service.dart：一則 JSON {type, ...欄位}）。
# - 連上後送 identify（playerId 存在 user://，第一次沒有就讓伺服器發一個；附 deviceInfo）
# - 每秒送 ping（伺服器 5 秒沒收到任何訊息就當斷線）；自己這邊 5 秒沒收到任何訊息也當斷線
# - 斷線後自動重連，用同一個 playerId 送 identify；伺服器在寬限期內會回 reconnected: true
# - App 切到背景：主動關掉連線（不送 leave_room），讓伺服器立刻進入 10 秒寬限；回到前景自動重連
# - 輸入繼承碼（restore_account）：重新連線，先送 restore_account，收到 account_restored 換成那個 playerId 再 identify；
#   restore_failed 就用原本的 playerId identify（restore_failed 會轉給 message_received 顯示原因）
# 伺服器網址：見 app_config.gd（命令列 > 環境變數 > 建置時的 build_config.gd > debug 預設 localhost）。
extends Node

signal identified(msg: Dictionary)        # identified 訊息（含 reconnected / inRoom / recoveryCode）
signal message_received(msg: Dictionary)  # 其他所有伺服器訊息
signal connection_lost                    # 已連上的連線斷掉（或切到背景）

const AppConfig := preload("res://scripts/app_config.gd")

const SAVE_PATH := "user://sbg_net.cfg"
const PING_INTERVAL := 1.0
const SILENCE_TIMEOUT := 5.0   # 這麼久沒收到任何訊息（正常每秒有 pong）就當斷線，同伺服器 CONFIG.HEARTBEAT_TIMEOUT_MS
const RETRY_INTERVAL := 1.0

var server_url := ""   # 空字串 = 沒有設定（release build 沒帶 SERVER_URL 建置）

var player_id := ""
var is_identified := false
var in_background := false

var _ws: WebSocketPeer
var _want_connection := false
var _was_open := false
var _ping_left := 0.0
var _silence := 0.0
var _retry_left := -1.0
var _restore_code := ""   # 非空 = 這次連上後先送 restore_account

func _ready() -> void:
	server_url = AppConfig.server_url()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		player_id = cfg.get_value("net", "player_id", "")

func connect_to_server() -> void:
	if server_url == "":
		push_error("沒有設定伺服器網址（release build 要用 tools/write_build_config.sh 帶 SERVER_URL 建置）")
		return
	_want_connection = true
	_open()

func send(type: String, payload: Dictionary = {}) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var o := payload.duplicate()
	o["type"] = type
	_ws.send_text(JSON.stringify(o))

static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

# 繼承帳號：斷掉目前連線、用繼承碼重連（只在大廳用，不在對戰中）
func restore_account(code: String) -> void:
	_restore_code = code
	_close_and_notify()
	_open()

# ---------- 背景/前景（手機） ----------
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		go_background()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		come_foreground()

# 切背景 = 斷線：直接關連線，不送 leave_room
func go_background() -> void:
	if in_background:
		return
	in_background = true
	_close_and_notify()

func come_foreground() -> void:
	if not in_background:
		return
	in_background = false
	if _want_connection:
		_open()

# ---------- 內部 ----------
func _open() -> void:
	if in_background:
		return
	_ws = WebSocketPeer.new()
	_was_open = false
	_retry_left = -1.0
	var err := _ws.connect_to_url(server_url)
	if err != OK:
		_schedule_retry()

func _schedule_retry() -> void:
	if _want_connection and not in_background:
		_retry_left = RETRY_INTERVAL

func _close_and_notify() -> void:
	var had := is_identified
	is_identified = false
	if _ws:
		_ws.close()
		_ws = null
	_was_open = false
	if had:
		connection_lost.emit()

func _process(delta: float) -> void:
	if _retry_left >= 0.0:
		_retry_left -= delta
		if _retry_left < 0.0:
			_open()
		return
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_silence = 0.0
				if _restore_code != "":
					send("restore_account", {"recoveryCode": _restore_code})
				else:
					_identify()
			while _ws.get_available_packet_count() > 0:
				_silence = 0.0
				var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if typeof(msg) == TYPE_DICTIONARY:
					_on_message(msg)
			if is_identified:
				_ping_left -= delta
				if _ping_left <= 0.0:
					_ping_left = PING_INTERVAL
					send("ping", {"clientTime": now_ms()})
				_silence += delta
				if _silence > SILENCE_TIMEOUT:
					print("[net] %.1f 秒沒收到訊息，視為斷線" % _silence)
					_close_and_notify()
					_schedule_retry()
		WebSocketPeer.STATE_CLOSED:
			var had := is_identified
			is_identified = false
			_ws = null
			_was_open = false
			if had:
				connection_lost.emit()
			_schedule_retry()

func _identify() -> void:
	var o := {"deviceInfo": "Godot %s %s" % [OS.get_name(), OS.get_model_name()]}
	if player_id != "":
		o["playerId"] = player_id
	send("identify", o)

func _on_message(msg: Dictionary) -> void:
	if msg.get("type") in ["account_restored", "restore_failed"]:
		_restore_code = ""
		if msg.type == "account_restored":
			player_id = str(msg.get("playerId", player_id))
		else:
			message_received.emit(msg)
		_identify()
	elif msg.get("type") == "identified":
		player_id = str(msg.get("playerId", ""))
		is_identified = true
		_ping_left = 0.0
		var cfg := ConfigFile.new()
		cfg.set_value("net", "player_id", player_id)
		cfg.save(SAVE_PATH)
		identified.emit(msg)
	else:
		message_received.emit(msg)
