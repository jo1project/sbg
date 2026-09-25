# 觸控操作 UI（CanvasLayer，疊在 3D 畫面上，不吃景深/泛光這些 3D 後製）。以手機直向為準。
# 版面照 Flutter screens/game_screen.dart 的 _BottomBelt：底部一列，左右內距 20dp、上下內距 12dp，
# 左 = 直接攻擊（⚡）、中 = 搖桿、右 = 隨機效果攻擊（🎲），三個垂直置中，整列包在 SafeArea 裡。
# 全部用 anchor 貼齊螢幕底部（搖桿 anchor 在底部中央、兩顆按鈕在左下/右下），offset 只放 dp 換算後的內距與大小。
#
# 尺寸換算：專案是 1080x1920 基準 + stretch canvas_items/expand，UI 座標 = 基準單位。
# Flutter 的 dp 以「直向手機寬 412dp」對應基準寬 1080 換算（1dp ≈ 2.62 單位），所以按鈕佔螢幕寬的比例跟
# Flutter 在一般手機上一樣（搖桿 100dp ≈ 螢幕寬 24%）。
#
# 安全區域：手機上讀 DisplayServer.get_display_safe_area()；電腦沒有安全區域，勾 simulate_iphone_safe_area
# （或執行中按 F2）模擬 iPhone 15 直向的上 59pt / 下 34pt，並畫出動態島和底部滑動條，看得到被擋住的範圍。
# 電腦測試：滑鼠（emulate_touch_from_mouse）操作搖桿/按鈕，或鍵盤 WASD/方向鍵轉向、J/K 攻擊、空白鍵閃避（= 放開搖桿）。
extends CanvasLayer

const Joystick := preload("res://scripts/ui/joystick.gd")
const AttackButton := preload("res://scripts/ui/attack_button.gd")

signal attack_requested(attack_type: String)   # "direct" / "random"，game_session 送 attack_request
signal dodge_requested                          # 放開搖桿（同 Flutter Joystick.onRelease → tryDodge）

const REF_WIDTH_DP := 412.0   # 直向手機的參考寬度（dp）
const BASE_WIDTH := 1080.0    # 專案基準寬度（project.godot viewport_width）
const DP := BASE_WIDTH / REF_WIDTH_DP
const PAD_H := 20.0           # dp
const PAD_V := 12.0           # dp
# iPhone 15（393x852pt）直向安全區域
const IPHONE_WIDTH_PT := 393.0
const IPHONE_INSET_TOP_PT := 59.0
const IPHONE_INSET_BOTTOM_PT := 34.0

@export var snake: Node   # snake_train.gd：set_direction(Vector2i)
## 電腦上模擬 iPhone 直向的安全區域（上：動態島/狀態列，下：滑動條）。執行中按 F2 切換。
@export var simulate_iphone_safe_area := false:
	set(v):
		simulate_iphone_safe_area = v
		if is_inside_tree():
			_layout()

var _root: Control
var _joystick: Control
var _btn_direct: Control
var _btn_random: Control
var _sim: Control   # 模擬安全區域的遮擋示意

func _ready() -> void:
	layer = 10   # 在暗角（Vignette，layer 1）上面
	_root = Control.new()
	_root.name = "Hud"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	_sim = Control.new()
	_sim.name = "SafeAreaSim"
	_sim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sim.draw.connect(_draw_sim)
	_root.add_child(_sim)

	get_viewport().size_changed.connect(_layout)
	_layout()

# 安全區域內距（UI 基準單位）：x=左, y=上, z=右, w=下
func safe_insets() -> Vector4:
	var ui := get_viewport().get_visible_rect().size
	if simulate_iphone_safe_area:
		var k := ui.x / IPHONE_WIDTH_PT
		return Vector4(0, IPHONE_INSET_TOP_PT * k, 0, IPHONE_INSET_BOTTOM_PT * k)
	if not OS.has_feature("mobile"):
		return Vector4.ZERO   # 電腦的 safe area 是整個螢幕，不是視窗，不能拿來用
	var safe := DisplayServer.get_display_safe_area()
	var screen := Vector2(DisplayServer.screen_get_size())
	var k2 := ui / screen    # 螢幕像素 -> UI 單位（手機上視窗 = 全螢幕）
	return Vector4(safe.position.x * k2.x, safe.position.y * k2.y,
		(screen.x - safe.end.x) * k2.x, (screen.y - safe.end.y) * k2.y)

# 把控制項 anchor 到 (ax, 1)（ax: 0 左 / 0.5 中 / 1 右），並用 offset 決定位置與大小
func _place(c: Control, ax: float, x: float, bottom: float, w: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = x
	c.offset_right = x + w
	c.offset_bottom = bottom
	c.offset_top = bottom - w

func _layout() -> void:
	var inset := safe_insets()
	var belt := Joystick.SIZE * DP                     # 這一列的高度 = 最高的元件（搖桿）
	var belt_bottom := -(inset.w + PAD_V * DP)          # 相對螢幕底邊
	var b := AttackButton.SIZE * DP
	var btn_bottom := belt_bottom - (belt - b) / 2.0    # 垂直置中在這一列
	_place(_joystick, 0.5, -belt / 2.0, belt_bottom, belt)
	_place(_btn_direct, 0.0, inset.x + PAD_H * DP, btn_bottom, b)
	_place(_btn_random, 1.0, -(inset.z + PAD_H * DP) - b, btn_bottom, b)
	_sim.queue_redraw()

# 模擬 iPhone：上方狀態列/動態島、下方滑動條，半透明標出被系統佔用的範圍
func _draw_sim() -> void:
	if not simulate_iphone_safe_area:
		return
	var ui := get_viewport().get_visible_rect().size
	var inset := safe_insets()
	var k := ui.x / IPHONE_WIDTH_PT
	var shade := Color(1, 0.2, 0.2, 0.18)
	_sim.draw_rect(Rect2(0, 0, ui.x, inset.y), shade)
	_sim.draw_rect(Rect2(0, ui.y - inset.w, ui.x, inset.w), shade)
	# 動態島（126x37pt，距頂 11pt）
	var island := Rect2((ui.x - 126 * k) / 2.0, 11 * k, 126 * k, 37 * k)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.set_corner_radius_all(int(18 * k))
	_sim.draw_style_box(sb, island)
	# 底部滑動條（134x5pt，距底 8pt）
	var bar := Rect2((ui.x - 134 * k) / 2.0, ui.y - 13 * k, 134 * k, 5 * k)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(1, 1, 1, 0.85)
	sb2.set_corner_radius_all(int(3 * k))
	_sim.draw_style_box(sb2, bar)

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
		KEY_SPACE:
			_on_joystick_released()
		KEY_F2:
			simulate_iphone_safe_area = not simulate_iphone_safe_area
			print("模擬 iPhone 安全區域: ", simulate_iphone_safe_area)
		_:
			return
	get_viewport().set_input_as_handled()

# 搖桿/鍵盤的「畫面方向」就是格子方向：鏡頭固定朝 -z（JSON y 變小的方向），所以畫面上 = (0,-1)。
# 之後如果鏡頭會繞 Y 軸轉，要在這裡依鏡頭 yaw 旋轉方向。
func _on_direction(d: Vector2i) -> void:
	if snake:
		snake.set_direction(d)

# Flutter 放開搖桿 = 嘗試閃躲（game_session 只在正在被攻擊時才送 dodge_attempt，其他時候是 no-op）
func _on_joystick_released() -> void:
	dodge_requested.emit()

func _attack(attack_type: String) -> void:
	if not _btn_direct.disabled:
		attack_requested.emit(attack_type)

# 等攻擊結果期間兩顆按鈕變灰（同 Flutter disabled: c.pendingOutgoingAttack）
func set_attack_enabled(on: bool) -> void:
	for b in [_btn_direct, _btn_random]:
		if b.disabled == on:
			b.disabled = not on
			b.queue_redraw()
