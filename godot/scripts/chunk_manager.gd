# Chunk 動態載入/卸載。內容全部來自地圖資料（map_loader.gd）：rooms/corridors 內生成地板方塊，範圍外什麼都不生成。
# 美術（地板/柱子/箱子/怪物/火把）的組法在 map_art.gd。
extends Node3D

const MapLoader := preload("res://scripts/map_loader.gd")
const MapArt := preload("res://scripts/map_art.gd")
const TorchFlicker := preload("res://scripts/torch_flicker.gd")
const AppConfig := preload("res://scripts/app_config.gd")

const CHUNK_SIZE := 8      # 每個 chunk 8x8 格，每格 1 單位
const EDGE_TORCHES_PER_SIDE := 3   # 同 Flutter：每個房間左右邊緣各最多 3 支，平均分布

@export var target: Node3D            # 追蹤的對象（假蛇頭）；chunk 判斷以它為中心
@export var load_radius := 2          # 前後左右各載入幾個 chunk (2 => 5x5)
@export var build_budget_ms := 3.0    # 每幀最多花多少時間建 chunk（至少建 1 個）；跨 chunk 時分散到多幀，不會一幀建 5 個卡頓
const SHADOW_REFRESH := 0.2           # 幾秒重新挑一次投影的火把
@export_file("*.json") var map_path := "res://assets/maps/map_03.json"   # 本地模式用；線上模式由伺服器 obstacle_layout 換掉

signal map_changed

var map: MapLoader
var art: MapArt
var _chunks := {}                     # Vector2i -> Node3D
var _center := Vector2i(999999, 999999)
var _torches := {}                    # chunk 座標 -> Array[[世界座標 Vector3, 有沒有立柱 bool, seed int]]
var _pending: Array[Vector2i] = []    # 還沒建的 chunk，近的在前
var _shadow_left := 0.0

func _ready() -> void:
	art = MapArt.new()
	if AppConfig.local_map_override() != "":
		map_path = AppConfig.local_map_override()
	var m := MapLoader.new()
	if m.load_file(map_path):
		_use_map(m)

# 換成伺服器送來的地圖（obstacle_layout 的 map，格式同 server/maps/*.json）
func load_map_data(data: Dictionary) -> void:
	var m := MapLoader.new()
	m._parse(data)
	_use_map(m)

func _use_map(m: MapLoader) -> void:
	map = m
	for k in _chunks:
		remove_child(_chunks[k])   # 先拿掉，新 chunk 才能用同樣的名字
		_chunks[k].queue_free()
	_chunks.clear()
	_torches.clear()
	_pending.clear()
	_center = Vector2i(999999, 999999)   # 下一幀重建周圍的 chunk
	_plan_torches()
	if target and target.has_method("set_map"):
		target.set_map(map)
	if target and target.has_method("set_start"):
		target.set_start(MapLoader.cell_center(map.spawn))
	map_changed.emit()

# ---- chunk 載入判斷邏輯都在這裡 ----
func _process(delta: float) -> void:
	var c := world_to_chunk(target.global_position)
	if c != _center:
		_center = c
		for k in _chunks.keys():
			if not _in_range(k):
				_chunks[k].queue_free()
				_chunks.erase(k)
		_pending.clear()
		for x in range(c.x - load_radius, c.x + load_radius + 1):
			for z in range(c.y - load_radius, c.y + load_radius + 1):
				var k := Vector2i(x, z)
				if not _chunks.has(k):
					_pending.append(k)
		_pending.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	# 建 chunk：近的先建，超過每幀預算就留到下一幀
	var t0 := Time.get_ticks_usec()
	while not _pending.is_empty():
		var k: Vector2i = _pending.pop_front()
		_chunks[k] = _build_chunk(k)
		if Time.get_ticks_usec() - t0 > build_budget_ms * 1000.0:
			break
	_shadow_left -= delta
	if _shadow_left <= 0.0:
		_shadow_left = SHADOW_REFRESH
		_update_torch_shadows()

func _in_range(k: Vector2i) -> bool:
	return absi(k.x - _center.x) <= load_radius and absi(k.y - _center.y) <= load_radius

# 只有離蛇最近的 GameSettings.torch_shadow_count 支火把投影，其他只發光（OmniLight 陰影在手機上很貴）。
# 目前有投影的火把距離打 1 格的折扣，兩支差不多遠時不會來回切換閃爍。
func _update_torch_shadows() -> void:
	var lights := []
	for l in get_tree().get_nodes_in_group("torch_lights"):
		if is_ancestor_of(l) and not l.is_queued_for_deletion():
			lights.append(l)
	var count := GameSettings.torch_shadow_count if TorchFlicker.shadows_on else 0
	var p := target.global_position
	var dist := func(l: OmniLight3D) -> float:
		return l.global_position.distance_to(p) - (1.0 if l.shadow_enabled else 0.0)
	lights.sort_custom(func(a, b): return dist.call(a) < dist.call(b))
	for i in lights.size():
		lights[i].shadow_enabled = i < count

func world_to_chunk(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))

func _chunk_of_cell(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / CHUNK_SIZE), floori(float(c.y) / CHUNK_SIZE))

func _build_chunk(k: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [k.x, k.y]
	root.position = Vector3(k.x * CHUNK_SIZE, 0, k.y * CHUNK_SIZE)
	if map:
		for x in CHUNK_SIZE:
			for z in CHUNK_SIZE:
				var g := Vector2i(k.x * CHUNK_SIZE + x, k.y * CHUNK_SIZE + z)
				if not map.is_floor(g):
					continue
				var f := art.make_floor(g)
				f.position = Vector3(x + 0.5, -0.5, z + 0.5)
				root.add_child(f)
				if map.obstacles.has(g):
					_add_map_obstacle(root, map.obstacles[g], x, z)
		for t in _torches.get(k, []):
			var torch := art.make_torch(t[1], t[2])
			torch.name = "Torch_%d" % t[2]
			torch.position = t[0] - root.position
			root.add_child(torch)
	add_child(root)
	return root

# 火把位置（對照 Flutter board.dart _paintTorches）：
# - 每個房間左右邊緣，外側不是地板的格子裡平均挑最多 3 格，立柱貼著地板切面立在外側虛空
# - 每根 column 柱頂一支（不加立柱）
func _plan_torches() -> void:
	var n := 0
	for room in _rooms():
		for side: int in [-1, 1]:
			var edge_x: int = room.position.x if side < 0 else room.end.x - 1
			var ys := []
			for y in range(room.position.y, room.end.y):
				if not map.is_floor(Vector2i(edge_x + side, y)):
					ys.append(y)
			for y in _even_spaced(ys, EDGE_TORCHES_PER_SIDE):
				# 貼著切面：立柱中心離切面 1px（立柱寬 2px）
				var x: float = edge_x + 0.5 + side * (0.5 + 1.0 / 16.0)
				_add_torch(Vector2i(edge_x, y), Vector3(x, 0, y + 0.5), true, n)
				n += 1
	for c in map.obstacles:
		if map.obstacles[c].get("type") == "column":
			_add_torch(c, MapLoader.cell_center(c, MapArt.COLUMN_HEIGHT), false, n)
			n += 1

func _rooms() -> Array[Rect2i]:
	return map.zones.slice(0, map.room_count)

func _add_torch(cell: Vector2i, pos: Vector3, with_post: bool, seed_value: int) -> void:
	var k := _chunk_of_cell(cell)
	if not _torches.has(k):
		_torches[k] = []
	_torches[k].append([pos, with_post, seed_value])

func _even_spaced(items: Array, count: int) -> Array:
	if items.size() <= count:
		return items
	var out := []
	for i in count:
		out.append(items[roundi(i * (items.size() - 1) / float(count - 1))])
	return out

# 節點命名：Monster_<species>_<x>_<y> / Column_<x>_<y> / Crate_<x>_<y> / Chest_<x>_<y>（x,y 為 JSON 格座標）
# metadata：obstacle_type, grid_x, grid_y；monster 另有 species, size
# size=big 的怪物對照 Flutter MapObstacle.cells：佔 (x,y) 與 (x+1,y) 兩格，立繪置中在兩格中間
func _add_map_obstacle(parent: Node3D, o: Dictionary, x: int, z: int) -> void:
	var type := str(o.get("type", ""))
	var gx := int(o.x)
	var gy := int(o.y)
	var node: Node3D
	var center_x := x + 0.5
	match type:
		"monster":
			var species := str(o.get("species", "unknown"))
			var size := str(o.get("size", "small"))
			node = art.make_monster(species)
			node.name = "Monster_%s_%d_%d" % [species, gx, gy]
			node.set_meta("species", species)
			node.set_meta("size", size)
			if size == "big":
				center_x = x + 1.0
		"column":
			node = art.make_column()
			node.name = "Column_%d_%d" % [gx, gy]
		"crate":
			node = art.make_crate()
			node.name = "Crate_%d_%d" % [gx, gy]
		"chest":
			node = art.make_chest()
			node.name = "Chest_%d_%d" % [gx, gy]
		_:
			push_warning("MapLoader: 未知 obstacle type '%s' @ (%d,%d)，先用 crate 代替" % [type, gx, gy])
			node = art.make_crate()
			node.name = "Unknown_%s_%d_%d" % [type, gx, gy]
	node.set_meta("obstacle_type", type)
	node.set_meta("grid_x", gx)
	node.set_meta("grid_y", gy)
	node.position = Vector3(center_x, 0, z + 0.5)
	parent.add_child(node)
