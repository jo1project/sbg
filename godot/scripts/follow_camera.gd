# 固定俯角、平滑跟隨的鏡頭。俯角/距離/平滑度都在 Inspector 調。
extends Camera3D

@export var target: Node3D
@export_range(20, 80) var pitch_deg := 55.0
@export var distance := 16.0
@export var smoothing := 4.0  # 越大跟越緊

func _ready() -> void:
	rotation_degrees = Vector3(-pitch_deg, 0, 0)
	global_position = _goal()

func _goal() -> Vector3:
	var p := deg_to_rad(pitch_deg)
	return target.global_position + Vector3(0, sin(p), cos(p)) * distance

func _process(delta: float) -> void:
	rotation_degrees.x = -pitch_deg  # 讓 Inspector 調角度即時生效
	global_position = global_position.lerp(_goal(), 1.0 - exp(-smoothing * delta))
