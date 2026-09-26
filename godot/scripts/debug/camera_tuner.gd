# 鏡頭調整面板：在實機上即時調俯角、FOV、距離、角色垂直位置、景深，直向／橫向各存一組（GameSettings.camera_profiles）。
# 「複製數值」把目前方向的參數複製成文字，貼回來設成 follow_camera.gd 的 DEFAULTS；「重設」回到 DEFAULTS。
#
# 開關方式（release build 也能用，TestFlight 版就是 release）：
#   - 三根手指同時點兩下（效能面板是三指按住 1 秒，不衝突）
#   - debug build 另外可以按 F6
# TODO 正式上架前把 ENABLED 改成 false。
extends CanvasLayer

const ENABLED := true
const FINGERS := 3
const DOUBLE_TAP := 0.4   # 兩次三指點擊的最大間隔（秒）

# [key, 標題, 最小, 最大, 步進, 顯示格式, 顯示倍率]
const SLIDERS := [
	["pitch", "俯角", 25.0, 70.0, 1.0, "%d°", 1.0],
	["fov", "FOV", 10.0, 50.0, 1.0, "%d°", 1.0],
	["distance", "距離", 10.0, 50.0, 0.5, "%.1f", 1.0],
	["screen_y", "角色位置", 0.5, 0.8, 0.01, "由上 %d%%", 100.0],
	["dof_margin", "對焦範圍", 0.0, 30.0, 0.5, "%.1f", 1.0],
	["dof_blur", "模糊強度", 0.0, 1.0, 0.01, "%.2f", 1.0],
]

var _root: PanelContainer
var _title: Label
var _auto: CheckButton
var _rows := {}           # key -> [HSlider, 數值 Label]
var _touches := {}
var _last_tap := -10.0
var _syncing := false     # 程式設定滑桿值時不要當成使用者拖動

func _ready() -> void:
	if not ENABLED:
		set_process_input(false)
		return
	layer = 31
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	theme.default_font_size = 30
	_root = PanelContainer.new()
	_root.theme = theme
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.72)
	bg.set_content_margin_all(18)
	bg.set_corner_radius_all(12)
	_root.add_theme_stylebox_override("panel", bg)
	_root.position = Vector2(24, 200)
	_root.custom_minimum_size.x = 1032
	_root.visible = false
	_root.add_to_group("blocks_joystick")   # 面板打開時按在上面不會變成浮動搖桿
	add_child(_root)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_root.add_child(v)
	_title = Label.new()
	v.add_child(_title)
	for s in SLIDERS:
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = s[1]
		name_l.custom_minimum_size.x = 170
		row.add_child(name_l)
		var slider := HSlider.new()
		slider.min_value = s[2]
		slider.max_value = s[3]
		slider.step = s[4]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = 64
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_on_slider.bind(s[0]))
		slider.drag_ended.connect(func(_changed): GameSettings.save())
		row.add_child(slider)
		var val := Label.new()
		val.custom_minimum_size.x = 190
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		v.add_child(row)
		_rows[s[0]] = [slider, val]
		if s[0] == "distance":
			_auto = CheckButton.new()
			_auto.text = "距離自動（看到 9 格寬）"
			_auto.focus_mode = Control.FOCUS_NONE
			_auto.toggled.connect(_on_auto)
			v.add_child(_auto)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	for b in [["複製數值", _copy], ["重設", _reset], ["關閉", func(): _root.visible = false]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(200, 72)
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	v.add_child(buttons)
	var hint := Label.new()
	hint.text = "三指點兩下開關 · 直向／橫向分開存"
	hint.add_theme_font_size_override("font_size", 22)
	hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(hint)

func _camera():   # follow_camera.gd（不標型別，才能呼叫它自己的方法）
	return get_viewport().get_camera_3d()

func _saved() -> Dictionary:
	var o: String = _camera().orientation()
	if not GameSettings.camera_profiles.has(o):
		GameSettings.camera_profiles[o] = {}
	return GameSettings.camera_profiles[o]

func _on_slider(value: float, key: String) -> void:
	if _syncing:
		return
	_saved()[key] = value
	_sync()

func _on_auto(on: bool) -> void:
	if _syncing:
		return
	# 關掉自動時從目前實際距離開始調，畫面不會跳
	_saved()["distance"] = 0.0 if on else snappedf(_camera().current_distance(), 0.5)
	GameSettings.save()
	_sync()

func _copy() -> void:
	var cam = _camera()
	DisplayServer.clipboard_set("鏡頭 %s（實際距離 %.2f）: %s" % [cam.orientation(), cam.current_distance(), JSON.stringify(cam.profile())])

func _reset() -> void:
	GameSettings.camera_profiles.erase(_camera().orientation())
	GameSettings.save()
	_sync()

# 滑桿、文字跟著目前方向的參數更新
func _sync() -> void:
	var cam = _camera()
	if not cam or not cam.has_method("profile"):
		return
	var p: Dictionary = cam.profile()
	_syncing = true
	_title.text = "鏡頭調整（%s）" % ("直向" if cam.orientation() == "portrait" else "橫向")
	_auto.button_pressed = p.distance <= 0.0
	for s in SLIDERS:
		var shown: float = cam.current_distance() if s[0] == "distance" else p[s[0]]
		_rows[s[0]][0].set_value_no_signal(shown)
		var n: float = shown * s[6]
		_rows[s[0]][1].text = s[5] % (roundi(n) if s[5].contains("%d") else n)
	_syncing = false

func toggle() -> void:
	_root.visible = not _root.visible
	if _root.visible:
		_sync()

# 用 _input 看所有觸控（不攔截）
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
			if _touches.size() == FINGERS:
				var now := Time.get_ticks_msec() / 1000.0
				if now - _last_tap <= DOUBLE_TAP:
					_last_tap = -10.0
					toggle()
				else:
					_last_tap = now
		else:
			_touches.erase(event.index)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F6 and OS.is_debug_build():
		toggle()
