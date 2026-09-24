# 讀取 Flutter/server 產出的地圖 JSON（格式原樣，不可改），轉成格子資料給 chunk_manager 用。
# 座標對應：地圖格 (x, y) => 世界 [x, x+1) x [y, y+1)，也就是 JSON 的 y 對應世界的 z 軸，地圖原點在世界原點。
extends RefCounted

enum Kind { FLOOR, WALL }

var map_id := ""
var cols := 0
var rows := 0
var spawn := Vector2i.ZERO
var cells := {}        # Vector2i -> Kind；只有 rooms/corridors 與其外框牆算「已知內容」
var obstacles := {}    # Vector2i -> Dictionary（JSON 原始 obstacle 物件）

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
	rects.append_array(d.get("corridors", []))
	for r in rects:
		for x in range(int(r.x0), int(r.x1) + 1):
			for y in range(int(r.y0), int(r.y1) + 1):
				cells[Vector2i(x, y)] = Kind.FLOOR
	# 每個矩形往外一圈是牆；已經是地板的格子（別的房間/走廊）不蓋牆，走廊就能打通牆
	for r in rects:
		for x in range(int(r.x0) - 1, int(r.x1) + 2):
			for y in range(int(r.y0) - 1, int(r.y1) + 2):
				var c := Vector2i(x, y)
				if not cells.has(c):
					cells[c] = Kind.WALL

	for o in d.get("obstacles", []):
		obstacles[Vector2i(int(o.x), int(o.y))] = o

# 這格是否由地圖資料決定（true => 不走隨機生成）
func is_known(c: Vector2i) -> bool:
	return cells.has(c)

func kind_at(c: Vector2i) -> Kind:
	return cells[c]

# 與已知內容的切比雪夫距離是否 <= r（用來在交界留一圈乾淨地板）
func is_near(c: Vector2i, r: int) -> bool:
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if cells.has(c + Vector2i(dx, dy)):
				return true
	return false

static func cell_center(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(c.x + 0.5, y, c.y + 0.5)
