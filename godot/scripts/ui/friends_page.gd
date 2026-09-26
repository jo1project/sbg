# 好友頁（蓋在大廳上面），兩種模式：
#   "connect"（大廳「好友連線」按鈕）：左邊是自己的好友編號（可複製），右邊輸入對方編號 +「送出邀請」
#   "list"（底部導覽「好友」）：跟真人對戰過的人（伺服器 get_friends，NPC 不會出現），點「邀請」直接送連線請求
# 邀請送出後的等待／收到邀請的畫面在 ui/invite_overlay.gd。送伺服器的動作用訊號交給 game_session。
extends Control

signal invite_requested(player_id: String, display_name: String)
signal refresh_requested

const DP := UiStyle.DP
const ID_LEN := 6   # 伺服器 db.js displayId 長度

const PANEL_BG := Color("1e1a16")
const PANEL_BORDER := Color("3a3228")
const GOLD := Color("fac775")
const GREY := Color("888780")
const TEXT := Color("d3d1c7")
const RED := Color("f0997b")
const ONLINE := Color("97c459")
const BLUE_BG := Color("0c2340")
const BLUE := Color("378add")
const BLUE_TEXT := Color("e6f1fb")

var _title: Label
var _connect: Control
var _list_box: Control
var _list: VBoxContainer
var _my_id: Label
var _input: LineEdit
var _notice: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # 已經在樹裡，只設 anchors 會保留目前 0 大小
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("14110d")
	add_child(bg)

	var outer := VBoxContainer.new()
	outer.name = "Outer"
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", int(12 * DP))
	add_child(outer)
	_title = UiStyle.label("", 24, GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_title)

	# ---- 好友連線：左右兩塊 ----
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * DP))
	_connect = row
	outer.add_child(row)

	var left := _panel(row)
	left.add_child(UiStyle.label("我的好友編號", 13, GREY))
	_my_id = UiStyle.label("------", 30, GOLD)
	_my_id.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_my_id.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_my_id.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.add_child(_my_id)
	var copy := UiStyle.small_button("複製", func():
		DisplayServer.clipboard_set(_my_id.text)
		set_notice("已複製好友編號"))
	copy.size_flags_horizontal = Control.SIZE_FILL
	left.add_child(copy)
	var hint := UiStyle.label("把編號告訴朋友，讓他邀請你", 11, GREY)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)

	var right := _panel(row)
	right.add_child(UiStyle.label("邀請好友", 13, GREY))
	_input = UiStyle.line_edit("輸入 %d 碼編號" % ID_LEN, ID_LEN)
	_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.add_theme_font_size_override("font_size", int(20 * DP))
	right.add_child(_input)
	var send := UiStyle.small_button("送出邀請", func():
		var id := _input.text.strip_edges().to_upper()
		if id.length() != ID_LEN:
			set_notice("好友編號是 %d 碼" % ID_LEN)
			return
		if id == _my_id.text:
			set_notice("不能邀請自己")
			return
		_input.release_focus()
		invite_requested.emit(id, id), BLUE_TEXT, BLUE_BG, BLUE)
	send.size_flags_horizontal = Control.SIZE_FILL
	right.add_child(send)
	var hint2 := UiStyle.label("對方要在線上、停在大廳", 11, GREY)
	hint2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint2)

	# ---- 好友清單 ----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_box = scroll
	outer.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", int(8 * DP))
	scroll.add_child(_list)

	# 好友連線模式時把「返回」推到底
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.name = "Fill"
	outer.add_child(fill)

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
	set_friends([])
	hide()

# 大廳 _layout() 呼叫：避開安全區域
func set_margins(left: float, top: float, right: float, bottom: float) -> void:
	var o := get_node("Outer") as Control
	o.offset_left = left
	o.offset_top = top
	o.offset_right = -right
	o.offset_bottom = -bottom

# mode："connect" 好友連線 / "list" 好友清單（打開時跟伺服器要最新清單）
func open(mode: String) -> void:
	var is_list := mode == "list"
	_title.text = "好友" if is_list else "好友連線"
	_connect.visible = not is_list
	_list_box.visible = is_list
	get_node("Outer/Fill").visible = not is_list
	_notice.text = ""
	_input.text = ""
	show()
	if is_list:
		refresh_requested.emit()

func set_my_id(id: String) -> void:
	_my_id.text = id

func set_notice(text: String) -> void:
	_notice.text = text

# friends：伺服器 friends 訊息的 [{ playerId, nickname, online }]，最近對戰的在前面
func set_friends(friends: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	if friends.is_empty():
		var empty := UiStyle.label("還沒有好友。\n跟真人對戰過就會出現在這裡（電腦對手不算）。\n也可以用「好友連線」輸入編號邀請。", 14, GREY)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		return
	for f in friends:
		if not f is Dictionary:
			continue
		var id := str(f.get("playerId", ""))
		var nick = f.get("nickname")
		var name: String = nick if nick is String and nick != "" else "玩家 %s" % id
		var online: bool = f.get("online", false) == true
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 1.5, 10, 10))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", int(10 * DP))
		card.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := UiStyle.label(name, 16, TEXT)
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(n)
		v.add_child(UiStyle.label("ID %s · %s" % [id, "在線" if online else "離線"], 11, ONLINE if online else GREY))
		h.add_child(v)
		var b := UiStyle.small_button("邀請", invite_requested.emit.bind(id, name), BLUE_TEXT, BLUE_BG, BLUE)
		if not online:
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.35)
		h.add_child(b)
		_list.add_child(card)

func _panel(parent: Control) -> VBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	p.custom_minimum_size.y = 220 * DP
	p.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 1.5, 10, 12))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(8 * DP))
	p.add_child(v)
	return v
