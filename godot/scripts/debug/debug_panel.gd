# 除錯面板（只在 debug build 出現，release 匯出時一進場就把自己刪掉）：
# 用獨立的 WebSocket 連線送伺服器的開發用除錯指令（server/src/debug.js，伺服器要用 SBG_DEBUG_COMMANDS=1 啟動）。
# 除錯連線不是玩家，用 playerId 指定要操作誰——目前 Godot 還沒接伺服器，可以拿來操作 Flutter 版的玩家；
# 之後 Godot 接上伺服器，就選自己的 playerId。對照測試情境見 godot/TEST_SCENARIOS.md。
# 開關：畫面左上角的 DBG 按鈕，或 F3。伺服器網址預設 ws://localhost:8080，
# 可用環境變數 SBG_SERVER_URL 或命令列參數 --sbg-server=ws://... 覆寫，也可在面板上改。
extends CanvasLayer

const FONT_SIZE := 30

var _ws := WebSocketPeer.new()
var _connected := false
var _panel: PanelContainer
var _toggle: Button
var _url: LineEdit
var _status: Label
var _target: OptionButton
var _energy: SpinBox
var _atk_type: OptionButton
var _atk_delay: SpinBox
var _atk_energy: SpinBox
var _auto_attack: CheckButton
var _log: RichTextLabel
var _players: Array = []   # debug_list 回來的玩家資料，跟 _target 的順序一致

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 20
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	theme.default_font_size = FONT_SIZE

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	_toggle = Button.new()
	_toggle.text = "DBG"
	_toggle.position = Vector2(16, 200)
	_toggle.pressed.connect(func(): _panel.visible = not _panel.visible)
	root.add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(16, 270)
	_panel.custom_minimum_size = Vector2(1048, 0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.85)
	bg.set_content_margin_all(16)
	bg.set_corner_radius_all(12)
	_panel.add_theme_stylebox_override("panel", bg)
	root.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)

	var r := _row(v, "伺服器")
	_url = LineEdit.new()
	_url.text = _default_url()
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(_url)
	r.add_child(_button("連線", _connect))
	_status = Label.new()
	_status.text = "未連線"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1000, 0)
	v.add_child(_status)

	r = _row(v, "目標玩家")
	_target = OptionButton.new()
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.clip_text = true
	r.add_child(_target)
	r.add_child(_button("重新整理", func(): _send({"type": "debug_list"})))

	r = _row(v, "下次隨機效果")
	r.add_child(_button("加速", _force_effect.bind("speedup")))
	r.add_child(_button("暫停", _force_effect.bind("pause")))
	r.add_child(_button("失明", _force_effect.bind("blind")))
	r.add_child(_button("取消", _force_effect.bind(null)))

	r = _row(v, "設定能量")
	_energy = _spin(0, 99, 10)
	r.add_child(_energy)
	r.add_child(_button("設定", func(): _send_target({"type": "debug_set_energy", "energy": _energy.value})))

	r = _row(v, "NPC 攻擊")
	_atk_type = OptionButton.new()
	_atk_type.add_item("direct")
	_atk_type.add_item("random")
	r.add_child(_atk_type)
	r.add_child(_small_label("延遲ms"))
	_atk_delay = _spin(0, 60000, 1000)
	r.add_child(_atk_delay)
	r.add_child(_small_label("能量"))
	_atk_energy = _spin(-1, 99, 5)   # -1 = 不改 NPC 能量
	r.add_child(_atk_energy)
	r.add_child(_button("發動", _npc_attack))

	r = _row(v, "NPC 閃避")
	r.add_child(_button("永遠閃避", _npc_dodge.bind("always")))
	r.add_child(_button("永遠不閃", _npc_dodge.bind("never")))
	r.add_child(_button("正常 30%", _npc_dodge.bind("default")))

	_auto_attack = CheckButton.new()
	_auto_attack.text = "NPC 自動攻擊"
	_auto_attack.button_pressed = true
	_auto_attack.toggled.connect(func(on): _send_target({"type": "debug_npc_auto_attack", "enabled": on}))
	v.add_child(_auto_attack)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 320)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 24)
	v.add_child(_log)

func _default_url() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--sbg-server="):
			return a.trim_prefix("--sbg-server=")
	var env := OS.get_environment("SBG_SERVER_URL")
	return env if env != "" else "ws://localhost:8080"

func _row(parent: Control, title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	parent.add_child(h)
	return h

func _small_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 22)
	return l

func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b

func _spin(lo: float, hi: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = val
	s.custom_minimum_size = Vector2(150, 0)
	return s

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()

# ---------- 連線 ----------
func _connect() -> void:
	_ws.close()
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(_url.text.strip_edges())
	_status.text = "連線中…" if err == OK else "連線失敗: %s" % error_string(err)
	_connected = false

func _process(_delta: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _connected:
		_connected = true
		_status.text = "已連線 %s（伺服器要用 SBG_DEBUG_COMMANDS=1 啟動才會回應）" % _url.text
		_send({"type": "debug_list"})
	elif st == WebSocketPeer.STATE_CLOSED and _connected:
		_connected = false
		_status.text = "連線中斷（%d）" % _ws.get_close_code()
	while _ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY:
			_on_message(msg)

func _send(o: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_log_line("[color=orange]還沒連線[/color]")
		return
	_ws.send_text(JSON.stringify(o))
	_log_line("→ %s" % JSON.stringify(o))

func _send_target(o: Dictionary) -> void:
	var p := _selected()
	if p.is_empty():
		_log_line("[color=orange]先按「重新整理」選目標玩家[/color]")
		return
	o["playerId"] = p.playerId
	_send(o)

func _selected() -> Dictionary:
	var i := _target.selected
	return _players[i] if i >= 0 and i < _players.size() else {}

# ---------- 指令 ----------
func _force_effect(effect) -> void:
	_send_target({"type": "debug_force_next_effect", "effect": effect})

func _npc_attack() -> void:
	var o := {"type": "debug_npc_attack", "attackType": _atk_type.get_item_text(_atk_type.selected), "delayMs": _atk_delay.value}
	if _atk_energy.value >= 0:
		o["energy"] = _atk_energy.value
	_send_target(o)

func _npc_dodge(mode: String) -> void:
	_send_target({"type": "debug_npc_dodge", "mode": mode})

func _on_message(msg: Dictionary) -> void:
	match msg.get("type"):
		"debug_ack":
			if msg.command == "debug_list":
				_fill_players(msg.detail.players)
			else:
				_log_line("[color=lightgreen]✓ %s[/color] %s" % [msg.command, JSON.stringify(msg.get("detail"))])
		"debug_error":
			_log_line("[color=salmon]✗ %s: %s[/color]" % [msg.command, msg.message])

func _fill_players(list: Array) -> void:
	var prev: String = _selected().get("playerId", "")
	_players.clear()
	_target.clear()
	# 只列真人（NPC 由它對手的 playerId 操作），在房間裡的排前面
	var humans := list.filter(func(p): return not p.isNpc)
	humans.sort_custom(func(a, b): return a.roomId != null and b.roomId == null)
	for p in humans:
		var label: String = "%s  能量%s" % [p.playerId, p.energy]
		if p.roomId:
			label += "  vs %s" % p.opponentId
		if p.activeEffect:
			label += "  [%s %dms]" % [p.activeEffect.type, p.activeEffect.msLeft]
		_players.append(p)
		_target.add_item(label)
		if p.playerId == prev:
			_target.select(_players.size() - 1)
	_log_line("玩家 %d 位" % _players.size())

func _log_line(t: String) -> void:
	_log.append_text(t + "\n")
