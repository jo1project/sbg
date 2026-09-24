# 虛擬搖桿，照 Flutter client/lib/widgets/joystick.dart：
# 底座 100x100 圓、搖桿頭 40、最大拖曳半徑 45、死區 10；輸出離散的四方向（貪食蛇只需要上下左右，不做類比）。
# 拖曳期間每次移動都回報方向；放開時搖桿頭回中心並發出 released（Flutter 用這個當「閃躲」操作）。
# 尺寸單位是 Flutter 的邏輯像素（dp），實際大小由外層 touch_controls.gd 用 scale 換算。
# 只吃 InputEventScreenTouch/Drag（多指觸控各自獨立）；電腦上靠 emulate_touch_from_mouse 讓滑鼠也能用。
extends Control

signal direction(dir: Vector2i)   # 格子方向：(0,-1) = 畫面上方 = 遠離鏡頭 = JSON y 變小
signal released

const SIZE := 100.0
const RADIUS := 45.0
const KNOB := 40.0
const DEAD_ZONE := 10.0

var _knob := Vector2.ZERO
var _touch := -1

func _init() -> void:
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and _hit(event.position):
			_touch = event.index
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_knob = Vector2.ZERO
			queue_redraw()
			released.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch:
		_drag(event.relative / get_global_transform_with_canvas().get_scale().x)
		get_viewport().set_input_as_handled()

func _hit(screen_pos: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	return Rect2(Vector2.ZERO, size).has_point(local)

func _drag(delta: Vector2) -> void:
	var next := _knob + delta
	var dist := next.length()
	_knob = next / dist * RADIUS if dist > RADIUS else next
	queue_redraw()
	if dist < DEAD_ZONE:   # 死區，避免手指微抖動誤觸發
		return
	# 同 Flutter 的切法：畫面座標（y 往下）的角度，右 [-45,45)、下 [45,135)、上 [-135,-45)、其餘左
	var deg := rad_to_deg(atan2(_knob.y, _knob.x))
	var d: Vector2i
	if deg >= -45 and deg < 45:
		d = Vector2i.RIGHT
	elif deg >= 45 and deg < 135:
		d = Vector2i.DOWN
	elif deg >= -135 and deg < -45:
		d = Vector2i.UP
	else:
		d = Vector2i.LEFT
	direction.emit(d)

func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, SIZE / 2.0, Color(1, 1, 1, 0.12))
	draw_arc(c, SIZE / 2.0 - 0.5, 0, TAU, 64, Color(1, 1, 1, 0.3), 1.0, true)
	# Flutter 用 Align(alignment: knob / radius) 擺搖桿頭，所以頭的中心最多偏離 (100-40)/2 = 30
	var off := _knob / RADIUS * (SIZE - KNOB) / 2.0
	draw_circle(c + off, KNOB / 2.0, Color(1, 1, 1, 0.5))
