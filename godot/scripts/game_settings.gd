# 本機設定（存在 user://sbg_settings.cfg）：大廳「設定」頁改、開機時讀。
# 暱稱、繼承碼存在伺服器，不在這裡。
class_name GameSettings

const TorchFlicker := preload("res://scripts/torch_flicker.gd")
const PATH := "user://sbg_settings.cfg"
const DEFAULT_STEP_MS := 325   # 同 snake_train.gd step_time、Flutter GameConfig.moveTickMs

static var shadows := true
static var show_fps := false
# TODO 正式上線前拿掉：測試用移動速度（每格毫秒數），snake_train.gd 每次開局讀
static var step_ms := DEFAULT_STEP_MS

static func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	shadows = cfg.get_value("video", "shadows", shadows)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	step_ms = cfg.get_value("test", "step_ms", step_ms)

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("test", "step_ms", step_ms)
	cfg.save(PATH)

# 陰影：火把（之後載入的 chunk 也套用）+ 月光
static func apply_shadows(tree: SceneTree) -> void:
	TorchFlicker.shadows_on = shadows
	for l in tree.get_nodes_in_group("torch_lights"):
		l.shadow_enabled = shadows
	var moon := tree.current_scene.get_node_or_null("Moonlight") as DirectionalLight3D if tree.current_scene else null
	if moon:
		moon.shadow_enabled = shadows
