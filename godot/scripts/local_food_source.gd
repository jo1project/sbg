# 暫時的本地食物產生器（還沒接伺服器前用）。行為照抄 server/src/room.js 的 spawnFood()/handleFoodEaten()：
# 場上恆定 FOOD_COUNT 個，在地圖可通行格裡隨機挑，避開障礙物（big 怪物佔兩格）、蛇身、已有的食物，最多試 50 次；
# 吃掉一個就補一個。接上伺服器後整個檔案換成 ServerFoodSource。
extends "res://scripts/food_source.gd"

const MapLoader := preload("res://scripts/map_loader.gd")
const FOOD_COUNT := 3   # 同 server events.js CONFIG.FOOD_COUNT

var map: MapLoader
var occupied_by_snake: Callable   # () -> Array[Vector2i]

var _foods := {}   # foodId -> Vector2i
var _next_id := 0
var _floor: Array[Vector2i] = []
var _blocked := {}

func start() -> void:
	_floor.assign(map.floor_cells.keys())
	for c in map.obstacles:
		var o: Dictionary = map.obstacles[c]
		_blocked[c] = true
		if o.get("size") == "big":
			_blocked[c + Vector2i(1, 0)] = true
	for i in FOOD_COUNT:
		_spawn()

func report_eaten(food_id: String, head_cell: Vector2i) -> void:
	if not _foods.has(food_id) or _foods[food_id] != head_cell:
		return   # 同伺服器：位置對不上就忽略
	_foods.erase(food_id)
	_spawn()

func _spawn() -> void:
	var snake: Array = occupied_by_snake.call() if occupied_by_snake.is_valid() else []
	var taken := {}
	for c in _foods.values():
		taken[c] = true
	for c in snake:
		taken[c] = true
	var pos := Vector2i.ZERO
	for attempt in 50:
		pos = _floor[randi() % _floor.size()]
		if not taken.has(pos) and not _blocked.has(pos) and map.is_floor(pos):
			break
	_next_id += 1
	var id := "local_%d" % _next_id
	_foods[id] = pos
	food_spawned.emit(id, pos)
