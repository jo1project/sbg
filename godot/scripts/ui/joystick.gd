# 虛擬搖桿。尺寸照 Flutter client/lib/widgets/joystick.dart：底座 100、搖桿頭 40、最大拖曳半徑 45、死區 10（dp）。
# 兩種模式（效能面板可切換，GameSettings.joystick_floating）：
#   浮動（預設，刻意跟 Flutter 不同，見 PARITY.md）：這個控制項的範圍就是「觸發區」（touch_controls.gd 排成畫面下半部，
#     扣掉安全區域）。在觸發區任何地方按下，底座中心就出現在手指位置；手指拖出半徑時底座跟著手指走，手指永遠在搖桿範圍內。
#     沒按著時在預設位置（底部中央）顯示半透明的待機底座，提示這裡可以操作。
#   固定（同 Flutter）：只有按在預設位置的底座上才算，底座不動。
# 按下的瞬間不產生方向；拖超過死區 10dp 後，每次移動都依角度切成 4 方向送出 direction（同 Flutter；迴轉、同方向由
# snake_train.gd set_direction() 忽略）。
# 放開 = 發出 released（Flutter 用這個當「閃躲」操作）。
# 多指：只吃 InputEventScreenTouch/Drag，每根手指用 index 分開；exclude(螢幕座標) 回傳 true 的位置（攻擊按鈕的感應範圍、
# 蓋在上面的面板）按下不會變成搖桿。電腦上靠 emulate_touch_from_mouse 讓滑鼠也能用。
extends Control

signal direction(dir: Vector2i)   # 格子方向：(0,-1) = 畫面上方 = 遠離鏡頭 = JSON y 變小
signal released

const SIZE := 100.0
const RADIUS := 45.0
const KNOB := 40.0
const DEAD_ZONE := 10.0

var floating := true
var dp := 1.0                 # 1dp = 幾個 UI 單位（touch_controls 設）
var home_from_bottom := 0.0   # 預設位置：底座中心距離這個控制項底邊（UI 單位），水平置中
var exclude: Callable         # func(screen_pos: Vector2) -> bool

var _touch := -1
var _center := Vector2.ZERO   # 按著時的底座中心（本地座標）
var _knob := Vector2.ZERO     # dp

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func home() -> Vector2:
	return Vector2(size.x / 2.0, size.y - home_from_bottom)

func is_active() -> bool:
	return _touch != -1

func _to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and _can_start(event.position):
			_touch = event.index
			_center = _to_local(event.position) if floating else home()
			_knob = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_knob = Vector2.ZERO
			queue_redraw()
			released.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch:
		_drag(_to_local(event.position))
		get_viewport().set_input_as_handled()

func _can_start(screen_pos: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	var local := _to_local(screen_pos)
	if floating:
		if not Rect2(Vector2.ZERO, size).has_point(local):
			return false
	elif local.distance_to(home()) > SIZE / 2.0 * dp:
		return false
	return not (exclude.is_valid() and exclude.call(screen_pos))

func _drag(local: Vector2) -> void:
	var v := (local - _center) / dp
	if v.length() > RADIUS:
		if floating:
			_center += (v - v.normalized() * RADIUS) * dp   # 底座跟著手指走
		v = v.normalized() * RADIUS
	_knob = v
	queue_redraw()
	if v.length() < DEAD_ZONE:   # 死區，避免手指微抖動誤觸發
		return
	# 同 Flutter 的切法：畫面座標（y 往下）的角度，右 [-45,45)、下 [45,135)、上 [-135,-45)、其餘左
	var deg := rad_to_deg(atan2(v.y, v.x))
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
	var active := _touch != -1
	var c := _center if active else home()
	var k := 1.0 if active or not floating else 0.5   # 浮動模式待機：半透明
	var r := SIZE / 2.0 * dp
	draw_circle(c, r, Color(1, 1, 1, 0.12 * k))
	draw_arc(c, r - 0.5 * dp, 0, TAU, 64, Color(1, 1, 1, 0.3 * k), dp, true)
	# Flutter 用 Align(alignment: knob / radius) 擺搖桿頭，所以頭的中心最多偏離 (100-40)/2 = 30
	var off := _knob / RADIUS * (SIZE - KNOB) / 2.0 * dp
	draw_circle(c + off, KNOB / 2.0 * dp, Color(1, 1, 1, 0.5 * k))
