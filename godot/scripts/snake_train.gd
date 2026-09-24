# 玩家的蛇（角色隊伍）。本地單機模式：邏輯照 Flutter client/lib/game/game_controller.dart 的 _tick()
# 與 collision.dart：每 step_time 秒前進一格；撞牆/虛空、撞自己、撞障礙物就死
# （目前只 print 並重新開始；接伺服器後改成送 death_report 等伺服器判定）。吃寶石不會變長（Flutter 也是）。
#
# 輸入：轉向輸入先排進佇列，每個格子步進取一個套用（一格內快速按「上再右」會分兩步依序轉，不會只留最後一個）。
#   跟前一個方向（佇列最後一個，佇列空就是目前方向）相反或相同的輸入直接忽略（不能 180 度迴轉）。
#   Flutter 原本只存最後一個 _pendingDir，這裡改成佇列是刻意的差異。
# 顯示：每一步都從上一格線性插值到這一格，插值時間 = 一步的時間，所以畫面位置最多落後邏輯一格、
#   不會越拖越遠；方向改變在步進那一瞬間就開始反映在畫面上。
# 這個節點本身的 position = 蛇頭顯示位置（給 chunk_manager / 攝影機追蹤用）。
extends Node3D

const MapLoader := preload("res://scripts/map_loader.gd")
const CharacterSprites := preload("res://scripts/character_sprites.gd")
const SnakeCharacter := preload("res://scripts/snake_character.gd")

signal head_arrived(cell: Vector2i)   # 蛇頭進入新的一格（吃食物判定用）
signal died(cause: String)            # "wall" | "self" | "obstacle"，同 Flutter DeathCheck.cause
signal turned(dir: Vector2i)          # 格子邏輯真正換方向的那一步（除錯/量測用）

const QUEUE_MAX := 3               # 最多排幾個轉向，避免按太多累積成很久以前的操作

@export var segment_count := 4                 # 含蛇頭，同 Flutter GameConfig.initialSnakeLength
@export var step_time := 0.325                 # 每格秒數，同 Flutter GameConfig.moveTickMs（加速效果是 160ms，之後接）
@export var camera: Camera3D                   # 角色面向以它的 Y 軸旋轉為準
@export_file("*.png") var head_sheet := "res://assets/sprites/hero.png"
@export_file("*.png") var body_sheet := "res://assets/sprites/goblin.png"
## 轉向延遲除錯：print 收到輸入 / 格子邏輯換方向 / 畫面開始往新方向移動 / 蛇頭圖換面向 的時間戳（毫秒）
@export var debug_turn_timing := true

var map: MapLoader
var spawn_cell := Vector2i.ZERO
var dir := Vector2i.RIGHT          # 目前方向（最近一步實際走的），Flutter 開局也是往右
var _queue: Array[Vector2i] = []   # 還沒套用的轉向
var _started := false              # 開局/重生後等第一次方向輸入才開始走
var _body: Array[Vector2i] = []    # 邏輯位置，[0] = 蛇頭
var _prev: Array[Vector2i] = []    # 上一步時每一節的位置（插值起點）
var _t := 0.0                      # 這一步的進度 0~1
var _chars: Array = []             # [0] = 蛇頭
var _dbg_vis := Vector2i.ZERO      # 等著印「畫面開始轉向」的方向
var _dbg_face := -1                # 等著印「蛇頭圖換面向」的方向編號

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
	_queue.clear()
	_started = false
	_t = 0.0
	_body.clear()
	for i in segment_count:
		_body.append(spawn_cell - Vector2i(i, 0))
	_prev = _body.duplicate()
	for i in _chars.size():
		_chars[i].place(_cell_pos(_body[i]), 2)   # 2 = 右（character_sprites.gd 的方向編號）
	position = _cell_pos(_body[0])

# 目前每一節佔的格子（邏輯位置，[0] = 蛇頭）
func occupied_cells() -> Array[Vector2i]:
	return _body.duplicate()

# 方向輸入（搖桿/鍵盤）
func set_direction(d: Vector2i) -> void:
	var last: Vector2i = _queue.back() if not _queue.is_empty() else dir
	if d == -last:
		return
	if not _started:
		# 第一次輸入（含跟目前面向相同的方向）：馬上走第一步，不用等一整個 step
		_started = true
		_t = 1.0
	if d == last or _queue.size() >= QUEUE_MAX:
		return
	_queue.append(d)
	_dbg("收到輸入 %s（佇列 %s）" % [d, _queue])

func _process(delta: float) -> void:
	if _started:
		_t += delta / step_time
		while _t >= 1.0:
			_t -= 1.0
			if not _tick():
				return
	var yaw := camera.global_rotation.y if camera else 0.0
	for i in _chars.size():
		_chars[i].move_to(_display(i), delta, yaw)
	position = _display(0)
	if _dbg_vis != Vector2i.ZERO and _t > 0.0:
		_dbg("畫面開始往 %s 移動（這一步進度 %.0f%%）" % [_dbg_vis, _t * 100])
		_dbg_vis = Vector2i.ZERO
	if _dbg_face >= 0 and _chars[0].dir == _dbg_face:
		_dbg("蛇頭圖換成面向 %d" % _dbg_face)
		_dbg_face = -1

# 走一格。回傳 false = 死了（已重新開始）
func _tick() -> bool:
	var nd := dir
	if not _queue.is_empty():
		nd = _queue.pop_front()
	var new_head := _body[0] + nd
	var cause := _death_cause(new_head)
	if cause != "":
		print("死亡: %s @ %s" % [cause, new_head])
		died.emit(cause)
		_reset()
		return false
	if nd != dir:
		turned.emit(nd)
		_dbg("格子邏輯換方向 %s -> %s，蛇頭進入 %s" % [dir, nd, new_head])
		_dbg_vis = nd
		_dbg_face = posmod(roundi(atan2(nd.x, nd.y) / (PI / 4.0)), 8)
	dir = nd
	_prev = _body.duplicate()
	_body.push_front(new_head)
	_body.pop_back()
	head_arrived.emit(new_head)
	return true

# 同 Flutter collision.dart checkDeath()（grow=false：尾巴這一格會讓出來，不算撞到自己）
func _death_cause(new_head: Vector2i) -> String:
	if map:
		var out_of_bounds := new_head.x < 0 or new_head.x >= map.cols or new_head.y < 0 or new_head.y >= map.rows
		if out_of_bounds or not map.is_floor(new_head):
			return "wall"
	var body := _body.duplicate()
	body.pop_back()
	if new_head in body:
		return "self"
	if map:
		for c in map.obstacles:
			var o: Dictionary = map.obstacles[c]
			if new_head == c or (o.get("size") == "big" and new_head == c + Vector2i(1, 0)):
				return "obstacle"
	return ""

func _dbg(msg: String) -> void:
	if debug_turn_timing:
		print("[turn %8.1f ms] %s" % [Time.get_ticks_usec() / 1000.0, msg])

# 第 i 節的顯示位置：上一格 -> 這一格線性插值
func _display(i: int) -> Vector3:
	return _cell_pos(_prev[i]).lerp(_cell_pos(_body[i]), _t)

static func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0, c.y + 0.5)
