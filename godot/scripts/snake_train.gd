# 玩家的蛇（角色隊伍）。本地單機模式：邏輯照 Flutter client/lib/game/game_controller.dart 的 _tick()
# 與 collision.dart：每 step_time 秒前進一格、方向輸入先暫存到下一格才生效、不能直接 180 度迴轉、
# 撞牆/虛空、撞自己、撞障礙物就死（目前只 print 並重新開始；接伺服器後改成送 death_report 等伺服器判定）。
# 吃寶石不會變長（Flutter 也是只加能量，變長只來自對手的直接攻擊）。
#
# 顯示：沿蛇頭走過的格子路徑連續插值，轉角用二次貝茲削圓（從進入邊中點到離開邊中點、以格子中心為控制點），
# 所以轉彎時角色會經過斜向圖。削圓角要在「蛇頭進入一格」時就知道它從哪一邊出去，所以邏輯 tick 發生在
# 蛇頭跨過格線的瞬間：進入新格子 X 時做死亡判定、吃寶石，並用暫存的方向決定 X 的出口。
# 輸入延遲最多一個 tick，跟 Flutter 一樣。
# 這個節點本身的 position = 蛇頭顯示位置（給 chunk_manager / 攝影機追蹤用）。
extends Node3D

const MapLoader := preload("res://scripts/map_loader.gd")
const CharacterSprites := preload("res://scripts/character_sprites.gd")
const SnakeCharacter := preload("res://scripts/snake_character.gd")

signal head_arrived(cell: Vector2i)   # 蛇頭進入新的一格（吃食物判定用）
signal died(cause: String)            # "wall" | "self" | "obstacle"，同 Flutter DeathCheck.cause

@export var segment_count := 4                 # 含蛇頭，同 Flutter GameConfig.initialSnakeLength
@export var step_time := 0.325                 # 每格秒數，同 Flutter GameConfig.moveTickMs（加速效果是 160ms，之後接）
@export var camera: Camera3D                   # 角色面向以它的 Y 軸旋轉為準
@export_file("*.png") var head_sheet := "res://assets/sprites/hero.png"
@export_file("*.png") var body_sheet := "res://assets/sprites/goblin.png"

var map: MapLoader
var spawn_cell := Vector2i.ZERO
var dir := Vector2i.RIGHT          # 目前方向（最近一次實際採用的），Flutter 開局也是往右
var _pending := Vector2i.ZERO      # 暫存的下一個方向（ZERO = 沒有）
var _started := false              # 開局/重生後等第一次方向輸入才開始走
var _cells: Array[Vector2i] = []   # 蛇頭走過的格子；[-2] = 蛇頭所在格（邏輯位置），[-1] = 已決定的下一格
var _s := 0.5                      # 自上次 tick 後的進度 0~1（0 = 剛跨進 [-2]，0.5 = 在 [-2] 正中央）
var _chars: Array = []             # [0] = 蛇頭

# 由 chunk_manager 在本節點 _ready 之前呼叫
func set_map(m: MapLoader) -> void:
	map = m

func set_start(p: Vector3) -> void:
	spawn_cell = Vector2i(floori(p.x), floori(p.z))

func _ready() -> void:
	var fps := 2.0 / step_time       # 走路 4 幀 = 走 2 格
	var rows := CharacterSprites.ROWS_8DIR
	var head_frames := CharacterSprites.build(head_sheet, rows, fps)
	var body_frames := CharacterSprites.build(body_sheet, rows, fps) if segment_count > 1 else null
	for i in segment_count:
		var ch: AnimatedSprite3D = SnakeCharacter.new()
		ch.name = "Head" if i == 0 else "Body_%d" % i
		ch.top_level = true
		add_child(ch)
		ch.setup(head_frames if i == 0 else body_frames, rows, 1.0 / step_time)
		_chars.append(ch)
	_reset()

# 開局/重生：蛇頭在 spawn，身體往左排開、面向右（同 Flutter _startMatch）
func _reset() -> void:
	dir = Vector2i.RIGHT
	_pending = Vector2i.ZERO
	_started = false
	_s = 0.5
	_cells.clear()
	# 多存幾格歷史給尾巴的插值用
	for x in range(spawn_cell.x - segment_count - 1, spawn_cell.x + 2):
		_cells.append(Vector2i(x, spawn_cell.y))
	for i in _chars.size():
		_chars[i].place(_eval(_head_u() - i), 2)   # 2 = 右（character_sprites.gd 的方向編號）
	position = _eval(_head_u())

# 目前每一節佔的格子（邏輯位置，[0] = 蛇頭）
func occupied_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in segment_count:
		out.append(_cells[_cells.size() - 2 - i])
	return out

# 方向輸入（搖桿/鍵盤）。同 Flutter setDirection()：跟目前方向相反的直接忽略，其他的暫存到下一格生效。
func set_direction(d: Vector2i) -> void:
	if d == -dir:
		return
	_pending = d
	if not _started:
		# 還沒開始走：出口還能改，直接換掉已決定的下一格
		_started = true
		_apply_pending()
		_cells[-1] = _cells[-2] + dir

func _apply_pending() -> void:
	if _pending != Vector2i.ZERO:
		dir = _pending
		_pending = Vector2i.ZERO

func _process(delta: float) -> void:
	if _started:
		_s += delta / step_time
		while _s >= 1.0:
			_s -= 1.0
			if not _tick():
				return
	var yaw := camera.global_rotation.y if camera else 0.0
	for i in _chars.size():
		_chars[i].move_to(_eval(_head_u() - i), delta, yaw)
	position = _eval(_head_u())

# 蛇頭跨進 _cells[-1]。回傳 false = 死了（已重新開始）
func _tick() -> bool:
	var new_head := _cells[-1]
	var cause := _death_cause(new_head)
	if cause != "":
		print("死亡: %s @ %s" % [cause, new_head])
		died.emit(cause)
		_reset()
		return false
	_apply_pending()
	_cells.append(new_head + dir)
	if _cells.size() > segment_count + 3:
		_cells.pop_front()
	head_arrived.emit(new_head)
	return true

# 同 Flutter collision.dart checkDeath()（grow=false：尾巴這一格會讓出來，不算撞到自己）
func _death_cause(new_head: Vector2i) -> String:
	if map:
		var out_of_bounds := new_head.x < 0 or new_head.x >= map.cols or new_head.y < 0 or new_head.y >= map.rows
		if out_of_bounds or not map.is_floor(new_head):
			return "wall"
	var body := occupied_cells()
	body.pop_back()
	if new_head in body:
		return "self"
	if map:
		for c in map.obstacles:
			var o: Dictionary = map.obstacles[c]
			if new_head == c or (o.get("size") == "big" and new_head == c + Vector2i(1, 0)):
				return "obstacle"
	return ""

# 蛇頭在 _cells 上的連續位置（整數 = 正好在該格中心）
func _head_u() -> float:
	return _cells.size() - 2.5 + _s

# 路徑上連續位置 u -> 世界座標（地面 y=0）
func _eval(u: float) -> Vector3:
	var i := clampi(roundi(u), 1, _cells.size() - 2)
	var t := clampf(u - i + 0.5, 0.0, 1.0)
	var a := Vector2(_cells[i - 1])
	var c := Vector2(_cells[i])
	var b := Vector2(_cells[i + 1])
	var m0 := (a + c) * 0.5
	var m1 := (c + b) * 0.5
	var p := m0 * (1 - t) * (1 - t) + c * 2.0 * t * (1 - t) + m1 * t * t
	return Vector3(p.x + 0.5, 0, p.y + 0.5)
