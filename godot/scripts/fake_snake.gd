# 測試用假蛇頭：沿寫死的 waypoint 循環自動移動。之後換成真正的輸入控制。
extends Node3D

@export var speed := 6.0  # 單位/秒
@export var waypoints: Array[Vector3] = [
	Vector3(4, 0.5, 4), Vector3(60, 0.5, 4), Vector3(60, 0.5, 60),
	Vector3(-20, 0.5, 60), Vector3(-20, 0.5, -30), Vector3(4, 0.5, -30),
]

var _i := 0

func _ready() -> void:
	position = waypoints[0]

# 由 chunk_manager 依地圖 spawnPos 呼叫：整條路線平移，讓起點落在 spawn
func set_start(p: Vector3) -> void:
	var offset := Vector3(p.x - waypoints[0].x, 0, p.z - waypoints[0].z)  # 高度沿用原路線
	for j in waypoints.size():
		waypoints[j] += offset
	_i = 0
	position = waypoints[0]

func _process(delta: float) -> void:
	var goal := waypoints[(_i + 1) % waypoints.size()]
	position = position.move_toward(goal, speed * delta)
	if position.is_equal_approx(goal):
		_i = (_i + 1) % waypoints.size()
