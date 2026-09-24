# 跟伺服器的 WebSocket 連線（訊息格式同 Flutter client/lib/net/socket_service.dart：一則 JSON {type, ...欄位}）。
# - 連上後送 identify（playerId 存在 user://，第一次沒有就讓伺服器發一個；附 deviceInfo）
# - 每秒送 ping（伺服器 5 秒沒收到任何訊息就當斷線）；自己這邊 5 秒沒收到任何訊息也當斷線
# - 斷線後自動重連，用同一個 playerId 送 identify；伺服器在寬限期內會回 reconnected: true
# - App 切到背景：主動關掉連線（不送 leave_room），讓伺服器立刻進入 10 秒寬限；回到前景自動重連
# 伺服器網址：命令列 --sbg-server=ws://... > 環境變數 SBG_SERVER_URL > server_url。
extends Node

signal identified(msg: Dictionary)        # identified 訊息（含 reconnected / inRoom / recoveryCode）
signal message_received(msg: Dictionary)  # 其他所有伺服器訊息
signal connection_lost                    # 已連上的連線斷掉（或切到背景）

const SAVE_PATH := "user://sbg_net.cfg"
const PING_INTERVAL := 1.0
const SILENCE_TIMEOUT := 5.0   # 這麼久沒收到任何訊息（正常每秒有 pong）就當斷線，同伺服器 CONFIG.HEARTBEAT_TIMEOUT_MS
const RETRY_INTERVAL := 1.0

@export var server_url := "ws://localhost:8080"

var player_id := ""
var is_identified := false
var in_background := false

var _ws: WebSocketPeer
var _want_connection := false
var _was_open := false
var _ping_left := 0.0
var _silence := 0.0
var _retry_left := -1.0

func _ready() -> void:
	server_url = _resolve_url()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		player_id = cfg.get_value("net", "player_id", "")

func _resolve_url() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--sbg-server="):
			return a.trim_prefix("--sbg-server=")
	var env := OS.get_environment("SBG_SERVER_URL")
	return env if env != "" else server_url

func connect_to_server() -> void:
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
				var o := {"deviceInfo": "Godot %s %s" % [OS.get_name(), OS.get_model_name()]}
				if player_id != "":
					o["playerId"] = player_id
				send("identify", o)
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

func _on_message(msg: Dictionary) -> void:
	if msg.get("type") == "identified":
		player_id = str(msg.get("playerId", ""))
		is_identified = true
		_ping_left = 0.0
		var cfg := ConfigFile.new()
		cfg.set_value("net", "player_id", player_id)
		cfg.save(SAVE_PATH)
		identified.emit(msg)
	else:
		message_received.emit(msg)
