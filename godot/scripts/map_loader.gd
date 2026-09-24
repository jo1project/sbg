# 讀取 Flutter/server 產出的地圖 JSON（格式原樣，不可改），轉成格子資料給 chunk_manager 用。
# 座標對應：地圖格 (x, y) => 世界 [x, x+1) x [y, y+1)，也就是 JSON 的 y 對應世界的 z 軸，地圖原點在世界原點。
extends RefCounted

var map_id := ""
var cols := 0
var rows := 0
var spawn := Vector2i.ZERO
var zones: Array[Rect2i] = []   # rooms + corridors（Rect2i 的 end 為開區間，已把 JSON 的含端點 x1/y1 +1）
var room_count := 0             # zones 前 room_count 個是 rooms，後面是 corridors
var floor_cells := {}           # Vector2i -> true；rooms/corridors 範圍內的格子，範圍外什麼都不生成
var obstacles := {}             # Vector2i -> Dictionary（JSON 原始 obstacle 物件）

# 用法：var m := MapLoader.new(); if m.load_file(path): ...
func load_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MapLoader: 無法開啟 %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("MapLoader: %s 不是合法的 JSON 物件" % path)
		return false
	_parse(data)
	return true

func _parse(d: Dictionary) -> void:
	map_id = str(d.get("mapId", ""))
	cols = int(d.get("gridCols", 0))
	rows = int(d.get("gridRows", 0))
	var sp: Dictionary = d.get("spawnPos", {})
	spawn = Vector2i(int(sp.get("x", 0)), int(sp.get("y", 0)))

	# rooms 與 corridors 同樣處理：矩形內（x1/y1 含端點）都是地板
	var rects: Array = []
	rects.append_array(d.get("rooms", []))
	room_count = rects.size()
	rects.append_array(d.get("corridors", []))
	for r in rects:
		var z := Rect2i(int(r.x0), int(r.y0), int(r.x1) - int(r.x0) + 1, int(r.y1) - int(r.y0) + 1)
		zones.append(z)
		for x in range(z.position.x, z.end.x):
			for y in range(z.position.y, z.end.y):
				floor_cells[Vector2i(x, y)] = true

	for o in d.get("obstacles", []):
		obstacles[Vector2i(int(o.x), int(o.y))] = o

func is_floor(c: Vector2i) -> bool:
	return floor_cells.has(c)

# 對應 Flutter MapSprites.floorFor()：同一格固定選同一張地磚，88% floor_1、12% 平均分給 floor_2~8。回傳 1~8。
static func floor_variant(c: Vector2i) -> int:
	var h := posmod(c.x * 928371 + c.y * 51329, 100)
	return 1 if h < 88 else 2 + (h - 88) % 7

static func cell_center(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(c.x + 0.5, y, c.y + 0.5)
