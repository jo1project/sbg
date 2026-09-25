# 玩家的蛇（角色隊伍）。邏輯照 Flutter client/lib/game/game_controller.dart 的 _tick() 與 collision.dart：
# 每 step_time 秒前進一格；撞牆/虛空、撞自己、撞障礙物就發出 died 並停下（本地模式由 game_session 重新開始，
# 線上模式送 death_report 等伺服器判定）。吃寶石不會變長（Flutter 也是）；被直接攻擊命中才會變長（grow()）。
# 效果：加速（set_speedup，每格 160ms，同 Flutter speedupTickMs）；暫停、命中停頓由 game_session 用 set_frozen() 控制。
# 開局（3-2-1 倒數）、凍結（斷線寬限期間）由 game_session.gd 控制：reset_to() → start()、set_frozen()。
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
signal died(cause: String, head: Vector2i, body: Array)   # cause 同 Flutter DeathCheck.cause；head = 撞上的格子；body = 移動前的蛇身（含頭）
signal turned(dir: Vector2i)          # 格子邏輯真正換方向的那一步（除錯/量測用）

const QUEUE_MAX := 3               # 最多排幾個轉向，避免按太多累積成很久以前的操作

@export var segment_count := 4                 # 含蛇頭，同 Flutter GameConfig.initialSnakeLength
@export var step_time := 0.325                 # 每格秒數，同 Flutter GameConfig.moveTickMs
@export var speedup_step_time := 0.16          # 加速效果時的每格秒數，同 Flutter GameConfig.speedupTickMs
@export var camera: Camera3D                   # 角色面向以它的 Y 軸旋轉為準
@export_file("*.png") var head_sheet := "res://assets/sprites/hero.png"
@export_file("*.png") var body_sheet := "res://assets/sprites/goblin.png"
## 轉向延遲除錯：print 收到輸入 / 格子邏輯換方向 / 畫面開始往新方向移動 / 蛇頭圖換面向 的時間戳（毫秒）
@export var debug_turn_timing := true

var map: MapLoader
var spawn_cell := Vector2i.ZERO
var dir := Vector2i.RIGHT          # 目前方向（最近一步實際走的），Flutter 開局也是往右
var _queue: Array[Vector2i] = []   # 還沒套用的轉向
var _started := false              # start() 之後才會走（開局倒數期間可以先輸入方向，第一步就套用，同 Flutter）
var frozen := false                # 斷線寬限期間凍結：邏輯與畫面都停在原地
var _body: Array[Vector2i] = []    # 邏輯位置，[0] = 蛇頭
var _prev: Array[Vector2i] = []    # 上一步時每一節的位置（插值起點）
var _t := 0.0                      # 這一步的進度 0~1
var _chars: Array = []             # [0] = 蛇頭
var _dbg_vis := Vector2i.ZERO      # 等著印「畫面開始轉向」的方向
var _dbg_face := -1                # 等著印「蛇頭圖換面向」的方向編號
var _growth := 0                   # 還要長幾節（直接攻擊命中，同 Flutter _growthPending）
var _step := 0.325                 # 目前每格秒數（加速時變短）
var _body_frames: SpriteFrames
var _rows: Array

# 由 chunk_manager 在本節點 _ready 之前呼叫
func set_map(m: MapLoader) -> void:
	map = m

func set_start(p: Vector3) -> void:
	spawn_cell = Vector2i(floori(p.x), floori(p.z))

func _ready() -> void:
	var fps := 2.0 / step_time       # 走路 4 幀 = 走 2 格
	var rows := CharacterSprites.ROWS_8DIR
	var head_frames := CharacterSprites.build(head_sheet, rows, fps)
	_body_frames = CharacterSprites.build(body_sheet, rows, fps)
	_rows = rows
	for i in segment_count:
		_add_char(head_frames if i == 0 else _body_frames)
	_reset()

func _add_char(frames: SpriteFrames) -> AnimatedSprite3D:
	var ch: AnimatedSprite3D = SnakeCharacter.new()
	ch.name = "Head" if _chars.is_empty() else "Body_%d" % _chars.size()
	ch.top_level = true
	add_child(ch)
	ch.setup(frames, _rows, 1.0 / step_time)
	_chars.append(ch)
	return ch

# 開局/重生：蛇頭在 cell，身體往左排開、面向右（同 Flutter _startMatch），停著等 start()
func reset_to(cell: Vector2i) -> void:
	spawn_cell = cell
	_reset()

func start() -> void:
	_started = true
	_t = 0.0

func set_frozen(on: bool) -> void:
	frozen = on

# 直接攻擊命中：之後每走一步多長一節（尾巴留在原地），同 Flutter _growthPending
func grow(n: int) -> void:
	_growth += n

func set_speedup(on: bool) -> void:
	_step = speedup_step_time if on else step_time

func is_moving() -> bool:
	return _started

func _reset() -> void:
	dir = Vector2i.RIGHT
	_queue.clear()
	_started = false
	_growth = 0
	_step = step_time
	# 上一場被攻擊長出來的節數拿掉
	while _chars.size() > segment_count:
		_chars.pop_back().queue_free()
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
	if frozen:
		return   # 凍結中不接受轉向（同 Flutter 暫停時 setDirection 直接 return）
	if d == last or _queue.size() >= QUEUE_MAX:
		return
	_queue.append(d)
	_dbg("收到輸入 %s（佇列 %s）" % [d, _queue])

func _process(delta: float) -> void:
	if frozen:
		return
	if _started:
		_t += delta / _step
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
	var grow_now := _growth > 0
	var cause := _death_cause(new_head, grow_now)
	if cause != "":
		print("死亡: %s @ %s" % [cause, new_head])
		_started = false
		_t = 1.0   # 畫面停在撞上前的那一格
		died.emit(cause, new_head, _body.duplicate())
		return false
	if nd != dir:
		turned.emit(nd)
		_dbg("格子邏輯換方向 %s -> %s，蛇頭進入 %s" % [dir, nd, new_head])
		_dbg_vis = nd
		_dbg_face = posmod(roundi(atan2(nd.x, nd.y) / (PI / 4.0)), 8)
	dir = nd
	_prev = _body.duplicate()
	_body.push_front(new_head)
	if grow_now:
		# 尾巴不動、多一節：新的最後一節從舊尾巴的位置開始（原地不動）
		_growth -= 1
		_prev.append(_prev.back())
		var tail_facing: int = _chars[-1].dir
		_add_char(_body_frames).place(_cell_pos(_body.back()), tail_facing)
	else:
		_body.pop_back()
	head_arrived.emit(new_head)
	return true

# 同 Flutter collision.dart checkDeath()（grow=false：尾巴這一格會讓出來，不算撞到自己；grow=true：尾巴不動，撞到也算）
func _death_cause(new_head: Vector2i, grow := false) -> String:
	if map:
		var out_of_bounds := new_head.x < 0 or new_head.x >= map.cols or new_head.y < 0 or new_head.y >= map.rows
		if out_of_bounds or not map.is_floor(new_head):
			return "wall"
	var body := _body.duplicate()
	if not grow:
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
