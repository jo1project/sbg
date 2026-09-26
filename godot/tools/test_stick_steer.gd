# stick_steer.gd 的自我檢查（TEST_SCENARIOS S-03 的斜角情境）：
#   godot --headless --path godot --script res://tools/test_stick_steer.gd
extends SceneTree

const StickSteer := preload("res://scripts/ui/stick_steer.gd")
const UP := Vector2i.UP
const DOWN := Vector2i.DOWN
const LEFT := Vector2i.LEFT
const RIGHT := Vector2i.RIGHT

var _fail := 0

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1

# 從中心推到某個角度（畫面座標，y 往下；0° = 右、90° = 下）
func _push(s, deg: float, heading: Vector2i, length := 40.0) -> Vector2i:
	return s.update(Vector2.from_angle(deg_to_rad(deg)) * length, heading)

func _initialize() -> void:
	# 1. 斜角：每種都要轉向，且在 45° 交界兩側（44°/46°）結果一樣
	for c in [[UP, 135.0, LEFT, "往上走推左下"], [UP, 45.0, RIGHT, "往上走推右下"],
			[RIGHT, -45.0, UP, "往右走推右上"], [RIGHT, 45.0, DOWN, "往右走推右下"],
			[LEFT, -135.0, UP, "往左走推左上"], [DOWN, 135.0, LEFT, "往下走推左下"]]:
		for off in [-1.0, 0.0, 1.0]:
			var s = StickSteer.new()
			var got: Vector2i = _push(s, c[1] + off, c[0])
			_check(got == c[2], "%s（%.0f°）→ %s（實際 %s）" % [c[3], c[1] + off, c[2], got])

	# 2. 按住不動不鋸齒：往上走推左下 → 轉左；蛇變成往左後同一位置不再觸發
	var s = StickSteer.new()
	_check(_push(s, 135.0, UP) == LEFT, "按住左下：第一次轉左")
	var zig := 0
	for i in 10:
		if _push(s, 135.0 + (i % 3 - 1) * 3.0, LEFT) != Vector2i.ZERO:   # 手指小幅晃動 ±3°
			zig += 1
	_check(zig == 0, "按住左下（小幅晃動）不會再轉（實際觸發 %d 次）" % zig)
	_check(_push(s, 90.0, LEFT) == DOWN, "角度再變 45°（推正下）→ 轉下")

	# 3. 回到死區後可以再觸發同一個位置
	s = StickSteer.new()
	_check(_push(s, -90.0, RIGHT) == UP, "往右走推上 → 上")
	_check(_push(s, -90.0, UP) == Vector2i.ZERO, "按住不動維持")
	s.update(Vector2(3, 0), UP)   # 回到中心附近（< 10dp 死區）
	_check(_push(s, 0.0, UP) == RIGHT, "回中心後推右 → 右")

	# 4. 死區：不到 10dp 不產生方向
	s = StickSteer.new()
	_check(_push(s, -90.0, RIGHT, 9.0) == Vector2i.ZERO, "推 9dp（死區內）不轉向")
	_check(_push(s, -90.0, RIGHT, 11.0) == UP, "推 11dp 轉向")

	# 5. 另一軸分量太小（< 25%）：正後方偏一點點不轉
	s = StickSteer.new()
	_check(_push(s, 170.0, RIGHT) == Vector2i.ZERO, "往右走推左偏 10°（副軸 17%）不轉")
	s = StickSteer.new()
	_check(_push(s, 160.0, RIGHT) == DOWN, "往右走推左偏 20°（副軸 34%）轉下")

	# 6. 同方向：往上走推上，不觸發
	s = StickSteer.new()
	_check(_push(s, -90.0, UP) == Vector2i.ZERO, "往上走推上不觸發")

	print("全部通過" if _fail == 0 else "%d 項失敗" % _fail)
	quit(1 if _fail else 0)
