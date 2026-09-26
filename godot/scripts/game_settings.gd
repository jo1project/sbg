# 本機設定（存在 user://sbg_settings.cfg）：大廳「設定」頁改、開機時讀。
# 暱稱、繼承碼存在伺服器，不在這裡。
class_name GameSettings

const TorchFlicker := preload("res://scripts/torch_flicker.gd")
const PATH := "user://sbg_settings.cfg"

static var shadows := true
static var show_fps := false
# 操作手感（效能面板 debug/perf_overlay.gd 調，存檔；刻意跟 Flutter 不同，見 PARITY.md）
static var joystick_floating := true   # 浮動搖桿（false = 固定在底部中央，同 Flutter）
static var joystick_zone := 0.5        # 浮動搖桿觸發區：畫面下方多少比例的高度
static var button_hit_scale := 1.3     # 攻擊按鈕感應範圍 / 圖示大小
# 鏡頭（鏡頭調整面板 debug/camera_tuner.gd 調）：{"portrait": {...}, "landscape": {...}}，只存調過的值，其餘用 follow_camera.gd DEFAULTS
static var camera_profiles := {}

static func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	shadows = cfg.get_value("video", "shadows", shadows)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	joystick_floating = cfg.get_value("input", "joystick_floating", joystick_floating)
	joystick_zone = cfg.get_value("input", "joystick_zone", joystick_zone)
	button_hit_scale = cfg.get_value("input", "button_hit_scale", button_hit_scale)
	camera_profiles = cfg.get_value("camera", "profiles", camera_profiles)

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("input", "joystick_floating", joystick_floating)
	cfg.set_value("input", "joystick_zone", joystick_zone)
	cfg.set_value("input", "button_hit_scale", button_hit_scale)
	cfg.set_value("camera", "profiles", camera_profiles)
	cfg.save(PATH)

# 陰影：火把（之後載入的 chunk 也套用）+ 月光
static func apply_shadows(tree: SceneTree) -> void:
	TorchFlicker.shadows_on = shadows
	for l in tree.get_nodes_in_group("torch_lights"):
		l.shadow_enabled = shadows
	var moon := tree.current_scene.get_node_or_null("Moonlight") as DirectionalLight3D if tree.current_scene else null
	if moon:
		moon.shadow_enabled = shadows
