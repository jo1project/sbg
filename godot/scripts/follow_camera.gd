# 固定俯角、平滑跟隨的鏡頭（以手機直向為準）。FOV 36（Godot 的 fov 是垂直視角）、俯角 35°。
# 距離依畫面比例自動算：讓蛇頭所在深度的可見寬度 = fit_width_cells 格（直向 9:16 約 24.6 單位）。
# fit_width_cells = 0 時改用固定 distance。鏡頭位置 = 目標 + distance * (0, sin 俯角, cos 俯角)。
# 景深的遠端模糊起點跟著鏡頭距離走（= 距離 + dof_far_margin），否則鏡頭拉遠後整個畫面都會糊掉。
# 這支腳本每幀都會把 fov/rotation 寫回下面的 export 值，場景或 Inspector 其他地方設的值都會被蓋掉，要改請改這裡的 export。
extends Camera3D

@export var target: Node3D
@export_range(10, 90) var fov_deg := 36.0
@export_range(10, 80) var pitch_deg := 35.0
@export var fit_width_cells := 9.0      # 蛇頭處要看到幾格寬；0 = 用固定 distance
@export var distance := 13.0            # fit_width_cells = 0 時使用
@export var dof_far_margin := 5.0       # 蛇頭後方多遠開始遠端模糊
@export var smoothing := 12.0  # 越大跟越緊；12 ≈ 83ms 追上 63% 的距離，跟得上角色但保留一點緩衝
@export var debug_print := true

var _printed := false

func _ready() -> void:
	_apply()
	global_position = target.global_position + offset_vector()

func _aspect() -> float:
	var vp := get_viewport().get_visible_rect().size
	return vp.x / vp.y

# 目前使用的鏡頭距離
func current_distance() -> float:
	if fit_width_cells <= 0.0:
		return distance
	return fit_width_cells / (2.0 * tan(deg_to_rad(fov_deg) / 2.0) * _aspect())

func offset_vector() -> Vector3:
	var p := deg_to_rad(pitch_deg)
	return Vector3(0, sin(p), cos(p)) * current_distance()

func _apply() -> void:
	fov = fov_deg
	rotation_degrees = Vector3(-pitch_deg, 0, 0)
	var attrs := _camera_attributes()
	if attrs:
		attrs.dof_blur_far_distance = current_distance() + dof_far_margin

func _camera_attributes() -> CameraAttributesPractical:
	if attributes is CameraAttributesPractical:
		return attributes
	var we := get_tree().current_scene.find_child("WorldEnvironment", false) if get_tree().current_scene else null
	if we and we.camera_attributes is CameraAttributesPractical:
		return we.camera_attributes
	return null

func _process(delta: float) -> void:
	_apply()  # 讓 Inspector 調整、視窗比例改變即時生效
	global_position = global_position.lerp(target.global_position + offset_vector(), 1.0 - exp(-smoothing * delta))
	if debug_print and not _printed:
		_printed = true
		var d := current_distance()
		var vp := get_viewport().get_visible_rect().size
		var w := 2.0 * d * tan(deg_to_rad(fov) / 2.0) * _aspect()
		var attrs := _camera_attributes()
		print("[Camera] fov=%.1f(垂直) rotation_deg=%s distance=%.2f offset=%s 目標處可見寬度≈%.1f 格 畫面 %dx%d (%.3f) 視窗 %s dof_far=%s" % [
			fov, rotation_degrees, d, offset_vector(), w, vp.x, vp.y, _aspect(),
			DisplayServer.window_get_size(), attrs.dof_blur_far_distance if attrs else "-"])
