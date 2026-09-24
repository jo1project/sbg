# 固定俯角、平滑跟隨的鏡頭。規格：FOV 28、俯角 35°、位置 = 目標 + (0, 7.5, 10.6)。
# 這支腳本每幀都會把 fov/rotation 寫回下面的 export 值，場景或 Inspector 其他地方設的值都會被蓋掉，要改請改這裡的 export。
extends Camera3D

@export var target: Node3D
@export_range(10, 90) var fov_deg := 28.0
@export_range(10, 80) var pitch_deg := 35.0
@export var offset := Vector3(0, 7.5, 10.6)
@export var smoothing := 4.0  # 越大跟越緊
@export var debug_print := true

var _printed := false

func _ready() -> void:
	_apply()
	global_position = target.global_position + offset

func _apply() -> void:
	fov = fov_deg
	rotation_degrees = Vector3(-pitch_deg, 0, 0)

func _process(delta: float) -> void:
	_apply()  # 讓 Inspector 調整即時生效
	global_position = global_position.lerp(target.global_position + offset, 1.0 - exp(-smoothing * delta))
	if debug_print and not _printed:
		_printed = true
		# 目標所在平面上看得到的寬度（Godot 的 fov 是垂直視角）
		var d := global_position.distance_to(target.global_position)
		var vp := get_viewport().get_visible_rect().size
		var w := 2.0 * d * tan(deg_to_rad(fov) / 2.0) * vp.x / vp.y
		print("[Camera] fov=%.1f rotation_deg=%s position=%s target=%s offset=%s dist=%.2f 目標處可見寬度≈%.1f 格 (viewport %dx%d)" % [
			fov, rotation_degrees, global_position, target.global_position,
			global_position - target.global_position, d, w, vp.x, vp.y])
