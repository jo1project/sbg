# Chunk 動態載入/卸載 + 假資料產生。之後接真實地圖時，換掉 _cell_type() 或 _build_chunk() 即可。
extends Node3D

enum Cell { FLOOR, WALL, OBSTACLE }

const CHUNK_SIZE := 8      # 每個 chunk 8x8 格，每格 1 單位
const SEED := 12345        # 固定 seed，方便重現

@export var target: Node3D            # 追蹤的對象（假蛇頭）；chunk 判斷以它為中心
@export var load_radius := 2          # 前後左右各載入幾個 chunk (2 => 5x5)

# 火把：chunk 座標 -> chunk 內的區域座標 (x, z)
const TORCHES := {
	Vector2i(0, 0): Vector2(2, 2),
	Vector2i(1, 0): Vector2(5, 6),
	Vector2i(3, 1): Vector2(3, 3),
	Vector2i(6, 6): Vector2(4, 4),
}

var _chunks := {}                     # Vector2i -> Node3D
var _center := Vector2i(999999, 999999)
var _meshes := {}                     # Cell -> Mesh
var _mats := {}                       # Cell -> Material

func _ready() -> void:
	# 每種類型：[尺寸, 顏色]，地板頂面在 y=0，牆高 2、障礙物高 0.6
	var defs := {
		Cell.FLOOR: [Vector3(1, 0.2, 1), Color(0.35, 0.3, 0.25)],
		Cell.WALL: [Vector3(1, 2, 1), Color(0.45, 0.45, 0.5)],
		Cell.OBSTACLE: [Vector3(0.8, 0.6, 0.8), Color(0.6, 0.25, 0.2)],
	}
	for t in defs:
		var m := BoxMesh.new()
		m.size = defs[t][0]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = defs[t][1]
		m.material = mat
		_meshes[t] = m

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

func _build_chunk(k: Vector2i) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k.x, k.y, SEED))
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [k.x, k.y]
	root.position = Vector3(k.x * CHUNK_SIZE, 0, k.y * CHUNK_SIZE)
	for x in CHUNK_SIZE:
		for z in CHUNK_SIZE:
			var t := _cell_type(rng)
			_add_box(root, Cell.FLOOR, x, z)
			if t != Cell.FLOOR:
				_add_box(root, t, x, z)
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
