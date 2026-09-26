# 設定頁（大廳左上齒輪打開，蓋在大廳上面）。
#   畫面：陰影開關、顯示 FPS（本機設定 game_settings.gd，改了立刻套用並存檔）
#   個人資料：修改暱稱（伺服器 set_nickname）、修改頭像（未做，敬請期待）
#   帳號繼承：顯示繼承碼（伺服器 get_recovery_code）、輸入繼承碼（net_client restore_account，按兩次「繼承」才換帳號）
# 送伺服器的動作用訊號交給 game_session（它有 net）。
extends Control

signal nickname_submitted(nickname: String)
signal recovery_code_requested
signal restore_submitted(code: String)
signal avatar_pressed

const DP := UiStyle.DP
const CODE_HIDDEN := "已隱藏"
const NICKNAME_MAX := 12   # 同伺服器 db.js NICKNAME_MAX

const PANEL_BG := Color("1e1a16")
const PANEL_BORDER := Color("3a3228")
const GOLD := Color("fac775")
const GREY := Color("888780")
const TEXT := Color("d3d1c7")
const RED := Color("f0997b")

var _nickname: LineEdit
var _code: Label
var _restore: LineEdit
var _armed_code := ""   # 按過一次「繼承」的碼，再按一次同一組才送出
var _notice: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # 已經在樹裡，只設 anchors 會保留目前 0 大小
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("14110d")
	add_child(bg)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", int(10 * DP))
	outer.name = "Outer"
	add_child(outer)

	var title := UiStyle.label("設定", 24, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(12 * DP))
	scroll.add_child(col)

	var video := _section(col, "畫面")
	video.add_child(_toggle_row("陰影", "關掉可以提升低階手機的 FPS", GameSettings.shadows, func(on):
		GameSettings.shadows = on
		GameSettings.apply_shadows(get_tree())
		GameSettings.save()))
	video.add_child(_toggle_row("顯示 FPS", "", GameSettings.show_fps, func(on):
		GameSettings.show_fps = on
		GameSettings.save()))

	var profile := _section(col, "個人資料")
	var nick_row := _row(profile, "暱稱")
	_nickname = UiStyle.line_edit("1～%d 個字" % NICKNAME_MAX, NICKNAME_MAX)
	nick_row.add_child(_nickname)
	_nickname.text_submitted.connect(_save_nickname.unbind(1))   # 鍵盤的確定鍵 = 儲存
	nick_row.add_child(UiStyle.small_button("儲存", _save_nickname))
	var avatar_row := _row(profile, "頭像")
	var soon := UiStyle.label("尚未開放", 13, GREY)
	soon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar_row.add_child(soon)
	avatar_row.add_child(UiStyle.small_button("修改", avatar_pressed.emit))

	var account := _section(col, "帳號繼承")
	var code_row := _row(account, "繼承碼")
	_code = UiStyle.label(CODE_HIDDEN, 16, GOLD)
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.clip_text = true   # 文字寬度不要撐開整頁（手機窄的時候會超出螢幕）
	_code.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	code_row.add_child(_code)
	code_row.add_child(UiStyle.small_button("顯示", recovery_code_requested.emit))
	code_row.add_child(UiStyle.small_button("複製", func():
		if "-" in _code.text and _code.text != CODE_HIDDEN:
			DisplayServer.clipboard_set(_code.text)
			set_notice("已複製繼承碼")))
	var restore_row := _row(account, "輸入")
	_restore = UiStyle.line_edit("xxxx-xxxx-xxxx", 14)
	_restore.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS   # 英數鍵盤，見 UiStyle.dismiss_keyboard
	_restore.text_submitted.connect(_submit_restore.unbind(1))   # 確定鍵 = 按一次「繼承」
	restore_row.add_child(_restore)
	restore_row.add_child(UiStyle.small_button("繼承", _submit_restore))
	var warn := UiStyle.label("繼承後這台裝置會換成那個帳號。目前帳號請先記下繼承碼，不然就找不回來了。", 12, GREY)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	account.add_child(warn)

	_notice = UiStyle.label("", 13, RED)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_notice)

	var back := UiStyle.button(UiStyle.box(Color("2c2c2a"), Color("5f5e5a"), 1, 8, 0), UiStyle.box(Color("1f1f1d"), Color("5f5e5a"), 1, 8, 0))
	back.custom_minimum_size.y = 50 * DP
	var bl := UiStyle.label("返回", 16, TEXT)
	bl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back.add_child(bl)
	back.pressed.connect(hide)
	outer.add_child(back)
	hide()

# 大廳 _layout() 呼叫：避開安全區域
func set_margins(left: float, top: float, right: float, bottom: float) -> void:
	var o := get_node("Outer") as Control
	o.offset_left = left
	o.offset_top = top
	o.offset_right = -right
	o.offset_bottom = -bottom

func open() -> void:
	_notice.text = ""
	_code.text = CODE_HIDDEN   # 每次打開都要再按一次「顯示」，避免被旁邊的人看到
	_restore.text = ""
	_armed_code = ""
	show()

func set_nickname(nickname: String) -> void:
	_nickname.text = nickname

func show_recovery_code(code: String) -> void:
	_code.text = code

func set_notice(text: String) -> void:
	_notice.text = text

func _save_nickname() -> void:
	var s := _nickname.text.strip_edges()
	_nickname.release_focus()
	if s == "":
		set_notice("暱稱不能空白")
		return
	nickname_submitted.emit(s)

# 要按兩次才送出（第一次只提示），確定鍵也算一次
func _submit_restore() -> void:
	var c := _restore.text.strip_edges().to_lower()
	_restore.release_focus()
	if c == "":
		set_notice("請輸入繼承碼")
		return
	if c != _armed_code:
		_armed_code = c
		set_notice("目前的帳號會從這台裝置登出，確定的話再按一次「繼承」")
		return
	_armed_code = ""
	set_notice("繼承中…")
	restore_submitted.emit(c)

# 點輸入框以外的地方收起鍵盤
func _input(event: InputEvent) -> void:
	if visible:
		UiStyle.dismiss_keyboard(event, get_viewport())

func get_notice() -> String:
	return _notice.text

# ---------- 小工具 ----------

func _section(parent: Control, title: String) -> VBoxContainer:
	parent.add_child(UiStyle.label(title, 13, GREY))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 1.5, 10, 12))
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(10 * DP))
	panel.add_child(v)
	return v

func _row(parent: Control, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * DP))
	row.custom_minimum_size.y = 44 * DP
	var l := UiStyle.label(title, 15, TEXT)
	l.custom_minimum_size.x = 72 * DP
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	parent.add_child(row)
	return row

func _toggle_row(title: String, hint: String, on: bool, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44 * DP
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UiStyle.label(title, 15, TEXT))
	if hint != "":
		v.add_child(UiStyle.label(hint, 11, GREY))
	row.add_child(v)
	# 開／關膠囊按鈕（Godot 內建 CheckButton 的圖示在手機上太小）
	var off := UiStyle.box(Color("2c2c2a"), Color("5f5e5a"), 1.5, 16, 0)
	var b := UiStyle.button(off, UiStyle.box(Color("173404"), Color("639922"), 1.5, 16, 0))
	b.toggle_mode = true
	b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
	b.custom_minimum_size = Vector2(64, 34) * DP
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UiStyle.label("", 14, TEXT)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	var show_state := func(v: bool): l.text = "開" if v else "關"
	b.button_pressed = on
	show_state.call(on)
	b.toggled.connect(func(v):
		show_state.call(v)
		cb.call(v))
	row.add_child(b)
	return row
