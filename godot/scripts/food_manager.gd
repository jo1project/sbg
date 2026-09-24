# 場上的寶石：接食物來源（food_source.gd 介面）的 food_spawned 產生寶石；
# 蛇頭每走進一格就比對，吃到了（同 Flutter game_controller _tick() 的判定）就播閃光、移除，並回報來源。
# 現在用本地產生器；接伺服器時把 _make_source() 換成 ServerFoodSource。
extends Node3D

const LocalFoodSource := preload("res://scripts/local_food_source.gd")
const Gem := preload("res://scripts/gem.gd")

@export var snake: Node3D            # snake_train.gd
@export var chunk_manager: Node3D    # 拿地圖資料

var source: Node                     # food_source.gd
var _gems := {}                      # foodId -> [Gem 節點, Vector2i]

func _ready() -> void:
	source = _make_source()
	add_child(source)
	source.food_spawned.connect(_on_food_spawned)
	source.food_removed.connect(_on_food_removed)
	snake.head_arrived.connect(_on_head_arrived)
	source.start()

func _make_source() -> Node:
	var s = LocalFoodSource.new()
	s.name = "LocalFoodSource"
	s.map = chunk_manager.map
	s.occupied_by_snake = snake.occupied_cells
	return s

func _on_food_spawned(food_id: String, cell: Vector2i) -> void:
	var g := Node3D.new()
	g.set_script(Gem)
	g.name = "Gem_%s" % food_id
	g.set_meta("food_id", food_id)
	g.position = Vector3(cell.x + 0.5, 0, cell.y + 0.5)
	add_child(g)
	_gems[food_id] = [g, cell]

func _on_food_removed(food_id: String) -> void:
	if _gems.has(food_id):
		_gems[food_id][0].queue_free()
		_gems.erase(food_id)

func _on_head_arrived(cell: Vector2i) -> void:
	for id in _gems.keys():
		if _gems[id][1] == cell:
			_gems[id][0].burst_and_free()
			_gems.erase(id)
			source.report_eaten(id, cell)
			return
