# 攻擊按鈕，照 Flutter client/lib/widgets/attack_button.dart：
# 52 圓、深橘色半透明（disabled 變灰）、白色細框；點一下發動攻擊；長按（0.5 秒）在按鈕上方顯示說明氣泡，
# 長按後放開只收起氣泡、不發動攻擊。尺寸單位是 dp，實際大小由外層 touch_controls.gd 用 scale 換算。
extends Control

signal pressed

enum Icon { FLASH, CASINO }   # Flutter 用 Icons.flash_on / Icons.casino

const SIZE := 52.0
const LONG_PRESS := 0.5       # Flutter 預設長按時間 500ms
const TAP_SLOP := 18.0        # Flutter kTouchSlop：手指移動超過就不算點擊
const DEEP_ORANGE := Color("ff5722")

var icon := Icon.FLASH
var tooltip := ""
var disabled := false

var _touch := -1
var _down_pos := Vector2.ZERO
var _held := 0.0
var _show_tip := false
var _tap_ok := false
var _font: Font

func _init() -> void:
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 預設字型沒有中文字，用系統字型
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft JhengHei", "PingFang TC", "Noto Sans CJK TC", "Noto Sans TC", "sans-serif"])
	_font = f

func _process(delta: float) -> void:
	if _touch == -1 or _show_tip:
		return
	_held += delta
	if _held >= LONG_PRESS:
		_show_tip = true
		_tap_ok = false
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and _hit(event.position):
			_touch = event.index
			_down_pos = event.position
			_held = 0.0
			_tap_ok = true
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			if _show_tip:
				_show_tip = false
				queue_redraw()
			elif _tap_ok and not disabled:
				pressed.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch:
		var s := get_global_transform_with_canvas().get_scale().x
		if (event.position - _down_pos).length() / s > TAP_SLOP:
			_tap_ok = false
		get_viewport().set_input_as_handled()

func _hit(screen_pos: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	return Rect2(Vector2.ZERO, size).has_point(local)

func _draw() -> void:
	var c := size / 2.0
	var base := Color.GRAY if disabled else DEEP_ORANGE
	base.a = 0.9 if _show_tip else 0.45
	draw_circle(c, SIZE / 2.0, base)
	draw_arc(c, SIZE / 2.0 - 0.5, 0, TAU, 64, Color(1, 1, 1, 0.8 if _show_tip else 0.3), 1.0, true)
	_draw_icon(c - Vector2(12, 12), base)
	if _show_tip:
		_draw_tip()

# Material icon 24x24 的形狀，白色
func _draw_icon(o: Vector2, bg: Color) -> void:
	if icon == Icon.FLASH:
		# flash_on：M7 2v11h3v9l7-12h-4l4-8z
		var pts := PackedVector2Array([Vector2(7, 2), Vector2(7, 13), Vector2(10, 13), Vector2(10, 22),
			Vector2(17, 10), Vector2(13, 10), Vector2(17, 2)])
		for i in pts.size():
			pts[i] += o
		draw_colored_polygon(pts, Color.WHITE)
	else:
		# casino：白色方塊骰子 + 5 點
		var r := Rect2(o + Vector2(3, 3), Vector2(18, 18))
		draw_rect(r, Color.WHITE)
		var pip := Color(bg.r, bg.g, bg.b, 1.0)
		for p in [Vector2(7.5, 7.5), Vector2(16.5, 7.5), Vector2(12, 12), Vector2(7.5, 16.5), Vector2(16.5, 16.5)]:
			draw_circle(o + p, 1.5, pip)

# 說明氣泡：底緣在按鈕底部往上 55 的位置、水平置中（同 Flutter Positioned(bottom: 55)）
func _draw_tip() -> void:
	var fs := 11
	var text_size := _font.get_string_size(tooltip, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var box := Vector2(text_size.x + 16, text_size.y + 8)
	var pos := Vector2((SIZE - box.x) / 2.0, SIZE - 55.0 - box.y)
	draw_style_box(_tip_box(), Rect2(pos, box))
	draw_string(_font, pos + Vector2(8, 4 + _font.get_ascent(fs)), tooltip, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _tip_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.87)
	sb.set_corner_radius_all(6)
	return sb
