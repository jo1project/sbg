# Chunk 動態載入/卸載。每一格先問地圖資料（map_loader.gd），地圖沒涵蓋的格子才走隨機假資料。
extends Node3D

const MapLoader := preload("res://scripts/map_loader.gd")

enum Cell { FLOOR, WALL, OBSTACLE }

const CHUNK_SIZE := 8      # 每個 chunk 8x8 格，每格 1 單位
const SEED := 12345        # 固定 seed，方便重現

@export var target: Node3D            # 追蹤的對象（假蛇頭）；chunk 判斷以它為中心
@export var load_radius := 2          # 前後左右各載入幾個 chunk (2 => 5x5)
@export_file("*.json") var map_path := "res://assets/maps/map_03.json"
@export var seam_margin := 1          # 地圖外牆外面幾圈強制留空地板，讓隨機區跟地圖交界乾淨

# 火把：chunk 座標 -> chunk 內的區域座標 (x, z)
const TORCHES := {
	Vector2i(0, 0): Vector2(2, 2),
	Vector2i(1, 0): Vector2(5, 6),
	Vector2i(3, 1): Vector2(3, 3),
	Vector2i(6, 6): Vector2(4, 4),
}

var map: MapLoader                    # null => 全部隨機
var _chunks := {}                     # Vector2i -> Node3D
var _center := Vector2i(999999, 999999)
var _meshes := {}                     # Cell -> Mesh
var _obstacle_meshes := {}            # obstacle type -> Mesh

func _ready() -> void:
	# 每種類型：[尺寸, 顏色]，地板頂面在 y=0，牆高 2、障礙物高 0.6
	var defs := {
		Cell.FLOOR: [Vector3(1, 0.2, 1), Color(0.35, 0.3, 0.25)],
		Cell.WALL: [Vector3(1, 2, 1), Color(0.45, 0.45, 0.5)],
		Cell.OBSTACLE: [Vector3(0.8, 0.6, 0.8), Color(0.6, 0.25, 0.2)],
	}
	for t in defs:
		_meshes[t] = _box(defs[t][0], defs[t][1])
	# 地圖 obstacles 的 placeholder（之後換真美術）
	_obstacle_meshes["column"] = _box(Vector3(0.6, 0.6, 0.6), Color(0.55, 0.6, 0.75))
	_obstacle_meshes["crate"] = _box(Vector3(0.6, 0.6, 0.6), Color(0.75, 0.55, 0.2))
	var cap := CapsuleMesh.new()      # 高 1、半徑 0.3；big/small 用節點 scale 區分
	cap.radius = 0.3
	cap.height = 1.0
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.7, 0.2, 0.6)
	cap.material = cap_mat
	_obstacle_meshes["monster"] = cap

	if map_path != "":
		map = MapLoader.new()
		if not map.load_file(map_path):
			map = null
	if map and target and target.has_method("set_start"):
		target.set_start(MapLoader.cell_center(map.spawn))

func _box(size: Vector3, color: Color) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material = mat
	return m

# ---- chunk 載入判斷邏輯都在這裡 ----
func _process(_delta: float) -> void:
	var c := world_to_chunk(target.global_position)
	if c == _center:
		return
	_center = c
	for k in _chunks.keys():
		if absi(k.x - c.x) > load_radius or absi(k.y - c.y) > load_radius:
			_chunks[k].queue_free()
			_chunks.erase(k)
	for x in range(c.x - load_radius, c.x + load_radius + 1):
		for z in range(c.y - load_radius, c.y + load_radius + 1):
			var k := Vector2i(x, z)
			if not _chunks.has(k):
				_chunks[k] = _build_chunk(k)

func world_to_chunk(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))

# 決定性偽隨機：同 seed + 同 chunk 座標 => 同樣的格子
func _cell_type(rng: RandomNumberGenerator) -> Cell:
	var r := rng.randf()
	if r < 0.08:
		return Cell.WALL
	if r < 0.16:
		return Cell.OBSTACLE
	return Cell.FLOOR

# 一格最後長什麼樣：地圖資料優先，其次交界緩衝區，最後才是隨機
func _resolve(g: Vector2i, rolled: Cell) -> Cell:
	if map == null:
		return rolled
	if map.is_known(g):
		return Cell.WALL if map.kind_at(g) == MapLoader.Kind.WALL else Cell.FLOOR
	if seam_margin > 0 and map.is_near(g, seam_margin):
		return Cell.FLOOR
	return rolled

func _build_chunk(k: Vector2i) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k.x, k.y, SEED))
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [k.x, k.y]
	root.position = Vector3(k.x * CHUNK_SIZE, 0, k.y * CHUNK_SIZE)
	for x in CHUNK_SIZE:
		for z in CHUNK_SIZE:
			# 每格都照樣抽一次亂數，確保隨機區的結果不會因為地圖蓋掉某些格而位移
			var g := Vector2i(k.x * CHUNK_SIZE + x, k.y * CHUNK_SIZE + z)
			var t := _resolve(g, _cell_type(rng))
			_add_box(root, Cell.FLOOR, x, z)
			if t != Cell.FLOOR:
				_add_box(root, t, x, z)
			if map and map.obstacles.has(g):
				_add_map_obstacle(root, map.obstacles[g], x, z)
	if TORCHES.has(k):
		var l := OmniLight3D.new()
		var p: Vector2 = TORCHES[k]
		l.position = Vector3(p.x, 1.5, p.y)
		l.light_color = Color(1, 0.6, 0.25)
		l.light_energy = 3.0
		l.omni_range = 8.0
		root.add_child(l)
	add_child(root)
	return root

func _add_box(parent: Node3D, t: Cell, x: int, z: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[t]
	var h: float = _meshes[t].size.y
	# 地板往下沉半個厚度使頂面落在 y=0，其餘放在地板上
	mi.position = Vector3(x + 0.5, -h / 2.0 if t == Cell.FLOOR else h / 2.0, z + 0.5)
	parent.add_child(mi)

# 節點命名：Monster_<species>_<x>_<y> / Column_<x>_<y> / Crate_<x>_<y>（x,y 為 JSON 格座標）
# metadata：obstacle_type, grid_x, grid_y；monster 另有 species, size
func _add_map_obstacle(parent: Node3D, o: Dictionary, x: int, z: int) -> void:
	var type := str(o.get("type", ""))
	var gx := int(o.x)
	var gy := int(o.y)
	var mi := MeshInstance3D.new()
	mi.set_meta("obstacle_type", type)
	mi.set_meta("grid_x", gx)
	mi.set_meta("grid_y", gy)
	var h := 0.6
	match type:
		"monster":
			var species := str(o.get("species", "unknown"))
			var size := str(o.get("size", "small"))
			mi.name = "Monster_%s_%d_%d" % [species, gx, gy]
			mi.set_meta("species", species)
			mi.set_meta("size", size)
			var s := 1.5 if size == "big" else 0.8
			mi.scale = Vector3.ONE * s
			h = 1.0 * s
		"column", "crate":
			mi.name = "%s_%d_%d" % [type.capitalize(), gx, gy]
		_:
			push_warning("MapLoader: 未知 obstacle type '%s' @ (%d,%d)，先用 crate 代替" % [type, gx, gy])
			mi.name = "Unknown_%s_%d_%d" % [type, gx, gy]
			type = "crate"
	mi.mesh = _obstacle_meshes[type]
	mi.position = Vector3(x + 0.5, h / 2.0, z + 0.5)
	parent.add_child(mi)
