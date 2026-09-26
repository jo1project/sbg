# 固定俯角、平滑跟隨的鏡頭。直向、橫向各一組參數（DEFAULTS），可以用鏡頭調整面板（debug/camera_tuner.gd）
# 在實機上即時調，調過的值存在 GameSettings.camera_profiles，覆蓋這裡的預設。
#   pitch      俯角（度）
#   fov        垂直視角（度，Godot 的 fov 是垂直的）
#   distance   鏡頭到注視點的距離；0 = 自動：讓蛇頭所在深度的可見寬度 = fit_cells 格
#   screen_y   蛇頭在畫面上的垂直位置（0.5 = 正中央，0.6 = 由上往下 60%）；做法是鏡頭注視蛇頭前方（-Z）一段距離
#   dof_margin 蛇頭後方多遠開始遠端模糊（景深起點跟著鏡頭距離走，否則拉遠後整個畫面都會糊掉）
#   dof_blur   景深模糊強度
# 這支腳本每幀都會把 fov/rotation/景深寫回去，場景或 Inspector 其他地方設的值都會被蓋掉。
extends Camera3D

const DEFAULTS := {
	"portrait": {"pitch": 45.0, "fov": 20.0, "distance": 0.0, "fit_cells": 9.0, "screen_y": 0.6, "dof_margin": 5.0, "dof_blur": 0.15},
	"landscape": {"pitch": 35.0, "fov": 36.0, "distance": 0.0, "fit_cells": 9.0, "screen_y": 0.5, "dof_margin": 5.0, "dof_blur": 0.15},
}

@export var target: Node3D
@export var smoothing := 12.0  # 越大跟越緊；12 ≈ 83ms 追上 63% 的距離，跟得上角色但保留一點緩衝
@export var debug_print := true

var _printed := false

func _ready() -> void:
	_apply()
	global_position = target.global_position + offset_vector()

func _aspect() -> float:
	var vp := get_viewport().get_visible_rect().size
	return vp.x / vp.y

func orientation() -> String:
	return "portrait" if _aspect() < 1.0 else "landscape"

# 目前方向的參數（預設 + 存檔覆蓋）
func profile() -> Dictionary:
	var p: Dictionary = DEFAULTS[orientation()].duplicate()
	p.merge(GameSettings.camera_profiles.get(orientation(), {}), true)
	return p

# 回傳 [鏡頭到注視點距離 d, 注視點在蛇頭前方的距離 a]。
# 蛇頭在畫面的 NDC y = -a·sin(俯角) / (d - a·cos(俯角)) / tan(fov/2)，令它 = 1 - 2·screen_y 解出 a。
func _geometry(p: Dictionary) -> Vector2:
	var s := sin(deg_to_rad(p.pitch))
	var c := cos(deg_to_rad(p.pitch))
	var t := tan(deg_to_rad(p.fov) / 2.0)
	var k: float = (2.0 * p.screen_y - 1.0) * t
	var d: float = p.distance
	if d <= 0.0:
		var head_depth: float = p.fit_cells / (2.0 * t * _aspect())   # 蛇頭所在深度要看到 fit_cells 格寬
		d = head_depth * (s + k * c) / s
	return Vector2(d, k * d / (s + k * c))

# 目前使用的鏡頭距離（到注視點）
func current_distance() -> float:
	return _geometry(profile()).x

# 鏡頭位置 - 蛇頭位置
func offset_vector() -> Vector3:
	var p := profile()
	var g := _geometry(p)
	var r := deg_to_rad(p.pitch)
	return Vector3(0, 0, -g.y) + Vector3(0, sin(r), cos(r)) * g.x

func _apply() -> void:
	var p := profile()
	fov = p.fov
	rotation_degrees = Vector3(-p.pitch, 0, 0)
	var attrs := _camera_attributes()
	if attrs:
		var g := _geometry(p)
		attrs.dof_blur_far_distance = g.x - g.y * cos(deg_to_rad(p.pitch)) + p.dof_margin   # 蛇頭深度 + margin
		attrs.dof_blur_amount = p.dof_blur

func _camera_attributes() -> CameraAttributesPractical:
	if attributes is CameraAttributesPractical:
		return attributes
	var we := get_tree().current_scene.find_child("WorldEnvironment", false) if get_tree().current_scene else null
	if we and we.camera_attributes is CameraAttributesPractical:
		return we.camera_attributes
	return null

func _process(delta: float) -> void:
	_apply()  # 讓調整面板、視窗比例改變即時生效
	global_position = global_position.lerp(target.global_position + offset_vector(), 1.0 - exp(-smoothing * delta))
	if debug_print and not _printed:
		_printed = true
		var vp := get_viewport().get_visible_rect().size
		var attrs := _camera_attributes()
		print("[Camera] %s %s distance=%.2f offset=%s 畫面 %dx%d (%.3f) 視窗 %s dof_far=%s" % [
			orientation(), profile(), current_distance(), offset_vector(), vp.x, vp.y, _aspect(),
			DisplayServer.window_get_size(), attrs.dof_blur_far_distance if attrs else "-"])
