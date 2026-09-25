# 效能資訊面板：FPS、每幀時間、draw calls、物件/頂點數、顯示記憶體、渲染器，
# 加上幾個特效開關（火把陰影、月光陰影、景深、泛光），在實機上直接比較開/關的效能差異。
#
# 開關方式（release build 也能用，TestFlight 版就是 release）：
#   - 三根手指同時按住畫面 1 秒（一般操作只用單指，不容易誤觸）
#   - debug build 另外可以按 F4
# 面板上的特效開關只影響這次執行，不存檔。
extends CanvasLayer

const TorchFlicker := preload("res://scripts/torch_flicker.gd")
const HOLD_SECONDS := 1.0
const FINGERS := 3
const REFRESH := 0.25   # 數字更新間隔（秒）

@export var world_environment: WorldEnvironment
@export var moonlight: DirectionalLight3D

var _root: PanelContainer
var _stats: Label
var _touches := {}        # index -> true（目前按著的手指）
var _hold := -1.0         # 三指按住的累計時間，<0 = 沒有在按
var _refresh_left := 0.0
var _fps_window: Array[float] = []

func _ready() -> void:
	layer = 30
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
	_root.position = Vector2(24, 260)
	_root.visible = false
	add_child(_root)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_root.add_child(v)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 28)
	v.add_child(_stats)

	v.add_child(_toggle("火把陰影", TorchFlicker.shadows_on, _set_torch_shadows))
	if moonlight:
		v.add_child(_toggle("月光陰影", moonlight.shadow_enabled, func(on): moonlight.shadow_enabled = on))
	var attrs := _camera_attributes()
	if attrs:
		v.add_child(_toggle("景深", attrs.dof_blur_far_enabled, func(on): attrs.dof_blur_far_enabled = on))
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		v.add_child(_toggle("泛光", env.glow_enabled, func(on): env.glow_enabled = on))
	var hint := Label.new()
	hint.text = "三指按住 1 秒關閉"
	hint.add_theme_font_size_override("font_size", 22)
	hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(hint)

func _toggle(title: String, on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = title
	c.button_pressed = on
	c.toggled.connect(cb)
	return c

func _camera_attributes() -> CameraAttributesPractical:
	if world_environment and world_environment.camera_attributes is CameraAttributesPractical:
		return world_environment.camera_attributes
	return null

func _set_torch_shadows(on: bool) -> void:
	TorchFlicker.shadows_on = on
	for l in get_tree().get_nodes_in_group("torch_lights"):
		l.shadow_enabled = on

func toggle() -> void:
	_root.visible = not _root.visible
	_fps_window.clear()

# 用 _input 看所有觸控（不攔截，搖桿/按鈕照常收到）
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
		else:
			_touches.erase(event.index)
		_hold = 0.0 if _touches.size() >= FINGERS else -1.0
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F4 and OS.is_debug_build():
		toggle()

func _process(delta: float) -> void:
	if _hold >= 0.0:
		_hold += delta
		if _hold >= HOLD_SECONDS:
			_hold = -1.0   # 放開前不會重複觸發
			toggle()
	if not _root.visible:
		return
	var fps := Engine.get_frames_per_second()
	_fps_window.append(1.0 / maxf(delta, 0.0001))
	if _fps_window.size() > 120:
		_fps_window.pop_front()
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH
	var worst := 9999.0
	for f in _fps_window:
		worst = minf(worst, f)
	_stats.text = "FPS %d（近 2 秒最低 %d）\n幀時間 %.1f ms\nDraw calls %d\n物件 %d · 頂點 %dk\n顯示記憶體 %.0f MB\n%s · %s" % [
		fps, int(worst),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
	]
