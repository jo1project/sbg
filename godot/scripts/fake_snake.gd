# 測試用假蛇頭：從 spawn 出發，沿寫死的 waypoint 循環自動移動（沒有碰撞）。之後換成真正的輸入控制。
extends Node3D

@export var speed := 3.0  # 單位/秒
# 預設是 map_03 房間內側繞一圈（地圖外現在什麼都沒有，別走出去）
@export var waypoints: Array[Vector3] = [
	Vector3(1.5, 0.5, 1.5), Vector3(10.5, 0.5, 1.5),
	Vector3(10.5, 0.5, 22.5), Vector3(1.5, 0.5, 22.5),
]

var _next := 1

func _ready() -> void:
	if position == Vector3.ZERO:
		position = waypoints[0]

# 由 chunk_manager 依地圖 spawnPos 呼叫：從 spawn 出發，先走向第一個 waypoint 再開始循環
func set_start(p: Vector3) -> void:
	position = Vector3(p.x, waypoints[0].y, p.z)
	_next = 0

func _process(delta: float) -> void:
	var goal := waypoints[_next]
	position = position.move_toward(goal, speed * delta)
	if position.is_equal_approx(goal):
		_next = (_next + 1) % waypoints.size()
