# 觸控操作 UI（CanvasLayer，疊在 3D 畫面上，不吃景深/泛光這些 3D 後製）。
# 版面照 Flutter screens/game_screen.dart 的 _BottomBelt：底部一列，左右內距 20、上下內距 12，
# 左 = 直接攻擊（⚡）、中 = 搖桿、右 = 隨機效果攻擊（🎲），三個垂直置中、左右貼齊（spaceBetween），整列包在 SafeArea 裡。
# 尺寸用 Flutter 的邏輯像素（dp）寫，這裡依裝置 DPI 換算成實際像素；手機上再避開瀏海/底部手勢條的安全區域。
# 電腦測試：滑鼠（emulate_touch_from_mouse）操作搖桿/按鈕，或鍵盤 WASD/方向鍵轉向、J/K 攻擊。
extends CanvasLayer

const Joystick := preload("res://scripts/ui/joystick.gd")
const AttackButton := preload("res://scripts/ui/attack_button.gd")

const PAD_H := 20.0
const PAD_V := 12.0

@export var snake: Node   # snake_train.gd：set_direction(Vector2i)

var _root: Control
var _joystick: Control
var _btn_direct: Control
var _btn_random: Control

func _ready() -> void:
	layer = 10   # 在暗角（Vignette，layer 1）上面
	_root = Control.new()
	_root.name = "Hud"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_joystick = Joystick.new()
	_joystick.name = "Joystick"
	_joystick.direction.connect(_on_direction)
	_joystick.released.connect(_on_joystick_released)
	_root.add_child(_joystick)

	_btn_direct = AttackButton.new()
	_btn_direct.name = "AttackDirect"
	_btn_direct.icon = AttackButton.Icon.FLASH
	_btn_direct.tooltip = "直接攻擊 · 對手變長"
	_btn_direct.pressed.connect(_attack.bind("direct"))
	_root.add_child(_btn_direct)

	_btn_random = AttackButton.new()
	_btn_random.name = "AttackRandom"
	_btn_random.icon = AttackButton.Icon.CASINO
	_btn_random.tooltip = "隨機效果 · 加速/暫停/致盲"
	_btn_random.pressed.connect(_attack.bind("random"))
	_root.add_child(_btn_random)

	get_viewport().size_changed.connect(_layout)
	_layout()

# dp -> 實際像素。電腦上 1:1；手機依 DPI（160dpi = 1x，同 Android dp 定義）
func _ui_scale() -> float:
	if OS.has_feature("mobile"):
		return maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	return 1.0

# 安全區域內距（實際像素）：left, top, right, bottom。只有手機需要（電腦的 safe area 是整個螢幕，不是視窗）
func _safe_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var vp := get_viewport().get_visible_rect().size
	var k := vp / Vector2(screen)   # 螢幕像素 -> viewport 像素
	return Vector4(safe.position.x * k.x, safe.position.y * k.y,
		(screen.x - safe.end.x) * k.x, (screen.y - safe.end.y) * k.y)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := _ui_scale()
	var inset := _safe_insets()
	_root.position = Vector2.ZERO
	_root.size = vp
	for c in [_joystick, _btn_direct, _btn_random]:
		c.scale = Vector2(s, s)
	var belt_h := Joystick.SIZE * s                          # 這一列的高度 = 最高的元件（搖桿）
	var bottom := vp.y - inset.w - PAD_V * s                 # 列的底緣
	var center_y := bottom - belt_h / 2.0
	var left := inset.x + PAD_H * s
	var right := vp.x - inset.z - PAD_H * s
	var b := AttackButton.SIZE * s
	_btn_direct.position = Vector2(left, center_y - b / 2.0)
	_btn_random.position = Vector2(right - b, center_y - b / 2.0)
	_joystick.position = Vector2((left + right) / 2.0 - belt_h / 2.0, center_y - belt_h / 2.0)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_W, KEY_UP:
			_on_direction(Vector2i.UP)
		KEY_S, KEY_DOWN:
			_on_direction(Vector2i.DOWN)
		KEY_A, KEY_LEFT:
			_on_direction(Vector2i.LEFT)
		KEY_D, KEY_RIGHT:
			_on_direction(Vector2i.RIGHT)
		KEY_J:
			_attack("direct")
		KEY_K:
			_attack("random")
		_:
			return
	get_viewport().set_input_as_handled()

# 搖桿/鍵盤的「畫面方向」就是格子方向：鏡頭固定朝 -z（JSON y 變小的方向），所以畫面上 = (0,-1)。
# 之後如果鏡頭會繞 Y 軸轉，要在這裡依鏡頭 yaw 旋轉方向。
func _on_direction(d: Vector2i) -> void:
	if snake:
		snake.set_direction(d)

# Flutter 放開搖桿 = 嘗試閃躲（只有正在被攻擊時才會送 dodge_attempt，其他時候是 no-op）。還沒接伺服器，先不做事。
func _on_joystick_released() -> void:
	pass

# 還沒接伺服器：只印出按了哪個攻擊。之後改成送 attack_request { attackType, clientTime }
func _attack(attack_type: String) -> void:
	print("攻擊: %s" % attack_type)
