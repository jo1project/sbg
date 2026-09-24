# 蛇（角色隊伍）：邏輯是格子制（每 step_time 秒蛇頭前進一格，身體每節走到前一節剛離開的格子），
# 顯示是沿蛇頭走過的格子路徑連續插值。路徑在轉角處用二次貝茲曲線把角削圓（從進入邊中點到離開邊中點，
# 以轉角格中心為控制點），所以轉彎時實際速度會經過斜向，角色自然會顯示斜向圖。
# 這個節點本身的 position = 蛇頭顯示位置（給 chunk_manager / 攝影機追蹤用）。
#
# 目前是測試用的自動路徑（route，相對 spawnPos 的一圈），之後換成真正的輸入時，改寫 _next_cell() 即可。
# 注意：削圓角需要「下一步」提前半格知道，所以 _cells 永遠多存一格 lookahead；接真實輸入時，
# 轉向指令要在蛇頭走到格子前半格就決定（類似輸入緩衝一個 tick）。
extends Node3D

const CharacterSprites := preload("res://scripts/character_sprites.gd")
const SnakeCharacter := preload("res://scripts/snake_character.gd")

@export var segment_count := 5                 # 含蛇頭
@export var step_time := 0.325                 # 每格秒數（同 Flutter 325ms/格）
@export var camera: Camera3D                   # 方向以它的 Y 軸旋轉為準
@export_file("*.png") var head_sheet := "res://assets/sprites/hero.png"
@export_file("*.png") var body_sheet := "res://assets/sprites/goblin.png"
# 測試路徑：[dx, dy, 格數]，從 spawn 出發繞一圈回到 spawn（map_03 預設是 spawn 左上方一圈，不會踩到障礙物）
@export var route: Array[Vector3i] = [
	Vector3i(-1, 0, 1), Vector3i(0, -1, 7), Vector3i(1, 0, 4), Vector3i(0, 1, 7), Vector3i(-1, 0, 3),
]
@export var pause_per_loop := 1.0              # 每繞完一圈停幾秒（看停下時保留方向），0 = 不停

var spawn_cell := Vector2i.ZERO
var _loop: Array[Vector2i] = []   # route 展開成的格子，_loop_cell(0) = spawn
var _next_k := 0                  # 下一次要取的 _loop_cell 編號
var _cells: Array[Vector2i] = []  # 蛇頭走過的格子；[-2] = 蛇頭這一步的目標格，[-1] = 下一步 lookahead
var _t := 0.0                     # 這一步的進度 0~1
var _pause := 0.0
var _chars: Array = []            # [0] = 蛇頭

# 由 chunk_manager 依地圖 spawnPos 呼叫（在本節點 _ready 之前）
func set_start(p: Vector3) -> void:
	spawn_cell = Vector2i(floori(p.x), floori(p.z))

func _ready() -> void:
	var c := spawn_cell
	for leg in route:
		for n in leg.z:
			c += Vector2i(leg.x, leg.y)
			_loop.append(c)
	if _loop.is_empty() or _loop[-1] != spawn_cell:
		push_warning("SnakeTrain: route 沒有回到 spawn，循環時會跳格")
	# 初始歷史：沿路徑往回推，讓身體一開始就排在蛇頭後面
	# 蛇頭一開始停在 spawn（_cells[-3]），正要走向 _loop_cell(1)
	for k in range(-(segment_count + 2), 3):
		_cells.append(_loop_cell(k))
	_next_k = 3

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
		var u := _head_u() - i
		ch.place(_eval(u), _facing(_eval(u - 0.05), _eval(u + 0.05)))
		_chars.append(ch)
	position = _eval(_head_u())

func _loop_cell(k: int) -> Vector2i:
	return _loop[posmod(k - 1, _loop.size())]

# 之後接真實輸入時改這裡：回傳蛇頭再下一步要去的格子
func _next_cell() -> Vector2i:
	var c := _loop_cell(_next_k)
	_next_k += 1
	return c

func _process(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
	else:
		_t += delta / step_time
		while _t >= 1.0:
			_t -= 1.0
			_cells.append(_next_cell())
			if _cells.size() > segment_count + 4:
				_cells.pop_front()
			# 蛇頭剛抵達的格子是 _loop_cell(_next_k - 3)；回到 spawn 時停一下
			if pause_per_loop > 0.0 and posmod(_next_k - 3, _loop.size()) == 0:
				_pause = pause_per_loop
				_t = 0.0
				break
	var yaw := camera.global_rotation.y if camera else 0.0
	for i in _chars.size():
		_chars[i].move_to(_eval(_head_u() - i), delta, yaw)
	position = _eval(_head_u())

# 蛇頭在 _cells 上的連續位置：從 [-3] 走向 [-2]
func _head_u() -> float:
	return _cells.size() - 3 + _t

# 路徑上連續位置 u（整數 = 正好在 _cells[u] 格中心）-> 世界座標（地面 y=0）
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

func _facing(from: Vector3, to: Vector3) -> int:
	var v := to - from
	return posmod(roundi(atan2(v.x, v.z) / (PI / 4.0)), 8)
