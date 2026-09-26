# 好友邀請的彈窗（蓋在大廳、結算畫面上面）：
#   送出邀請後：「等待 X 回應… N」+ 取消（伺服器 30 秒沒回應會送 invite_timeout）
#   收到邀請：「X 邀請你對戰」+ 拒絕／接受
# 由 game_session 依伺服器訊息 show_outgoing / show_incoming / hide_all。
extends CanvasLayer

signal cancel_pressed
signal accept_pressed
signal reject_pressed

const DP := UiStyle.DP
const GOLD := Color("fac775")
const GREY := Color("888780")
const TEXT := Color("d3d1c7")

var _page: Control
var _title: Label
var _body: Label
var _count: Label
var _cancel: Button
var _reject: Button
var _accept: Button
var _left := 0.0

func _ready() -> void:
	layer = 14   # 結算畫面（13）上面
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	theme.default_font_size = int(14 * DP)
	_page = Control.new()
	_page.theme = theme
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.add_to_group("blocks_joystick")   # 顯示時按下不會變成浮動搖桿
	add_child(_page)
	var mask := ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.75)
	_page.add_child(mask)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300 * DP
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color("1e1a16"), Color("378add"), 2, 12, 20))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(12 * DP))
	panel.add_child(v)
	_title = UiStyle.label("", 15, GREY)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_body = UiStyle.label("", 22, GOLD)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_body)
	_count = UiStyle.label("", 14, TEXT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_count)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * DP))
	v.add_child(row)
	_cancel = _button(row, "取消", Color("2c2c2a"), Color("5f5e5a"), TEXT, cancel_pressed)
	_reject = _button(row, "拒絕", Color("2c2c2a"), Color("5f5e5a"), TEXT, reject_pressed)
	_accept = _button(row, "接受", Color("173404"), Color("639922"), Color("eaf3de"), accept_pressed)
	hide_all()

func show_outgoing(display_name: String, seconds: float) -> void:
	_title.text = "好友連線"
	_body.text = "等待 %s 回應…" % display_name
	_open(seconds, true)

func show_incoming(display_name: String, seconds: float) -> void:
	_title.text = "收到對戰邀請"
	_body.text = "%s 邀請你對戰" % display_name
	_open(seconds, false)

func hide_all() -> void:
	_page.hide()
	_left = 0.0

func _open(seconds: float, outgoing: bool) -> void:
	_left = seconds
	_cancel.visible = outgoing
	_reject.visible = not outgoing
	_accept.visible = not outgoing
	_page.show()

func _process(delta: float) -> void:
	if not _page.visible:
		return
	_left = maxf(0.0, _left - delta)   # 只是顯示用，逾時以伺服器 invite_timeout 為準
	_count.text = "%d 秒" % ceili(_left)

func _button(parent: Control, text: String, bg: Color, border: Color, fg: Color, sig: Signal) -> Button:
	var b := UiStyle.button(UiStyle.box(bg, border, 1.5, 8, 0), UiStyle.box(bg.lightened(0.1), border, 1.5, 8, 0))
	b.custom_minimum_size.y = 50 * DP
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UiStyle.label(text, 17, fg)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	b.pressed.connect(sig.emit)
	parent.add_child(b)
	return b
