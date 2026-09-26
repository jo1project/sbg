# 搖桿向量 → 轉向（刻意跟 Flutter 不同，見 PARITY.md）。Flutter 是單純把角度切成 4 等分，推斜角（例如往上走時推左下）
# 在 45° 交界有一半機率被判成迴轉或同方向，輸入就被丟掉。這裡改成：
#   1. 看蛇目前的方向：主要軸是迴轉或同方向時，改用另一軸的分量（佔推桿長度 ≥ off_axis_ratio 才算），轉向那一側
#   2. 同一個搖桿位置只觸發一次轉向：角度要再變 retrigger_deg 以上、或回到死區，才會觸發下一次（按住不動不會鋸齒狀亂走）
#   3. 主要軸在 45° 交界加 hysteresis_deg 的遲滯，手指輕微晃動不會讓主要軸跳來跳去
# 死區、不能迴轉、轉向佇列照舊（死區在這裡判斷；迴轉與佇列在 snake_train.gd set_direction()）。
# 向量單位是 dp、畫面座標（y 往下）。自我檢查：godot --headless --path godot --script res://tools/test_stick_steer.gd
extends RefCounted

var dead_zone := 10.0          # dp
var off_axis_ratio := 0.25     # 另一軸分量 / 推桿長度
var retrigger_deg := 30.0
var hysteresis_deg := 8.0

var _axis := Vector2i.ZERO     # 目前的主要軸（遲滯用）
var _fired := false            # 這次按住後已經觸發過轉向
var _fired_angle := 0.0

# 放開搖桿、或回到死區
func reset() -> void:
	_axis = Vector2i.ZERO
	_fired = false

# v：搖桿頭相對底座中心（dp）；heading：蛇目前（含已排進佇列）的方向。回傳要轉的方向，不轉 = Vector2i.ZERO
func update(v: Vector2, heading: Vector2i) -> Vector2i:
	var length := v.length()
	if length < dead_zone:
		reset()
		return Vector2i.ZERO
	_axis = _major_axis(v)
	var d := _axis
	if d == heading or d == -heading:
		var minor := absf(v.y) if _axis.x != 0 else absf(v.x)
		if minor / length < off_axis_ratio:
			return Vector2i.ZERO
		d = Vector2i(0, signi(roundi(signf(v.y)))) if _axis.x != 0 else Vector2i(signi(roundi(signf(v.x))), 0)
	var ang := v.angle()
	if _fired and absf(angle_difference(_fired_angle, ang)) < deg_to_rad(retrigger_deg):
		return Vector2i.ZERO
	_fired = true
	_fired_angle = ang
	return d

func _major_axis(v: Vector2) -> Vector2i:
	if _axis != Vector2i.ZERO and absf(v.angle_to(Vector2(_axis))) <= deg_to_rad(45.0 + hysteresis_deg):
		return _axis
	if absf(v.x) >= absf(v.y):
		return Vector2i(signi(roundi(signf(v.x))), 0)
	return Vector2i(0, signi(roundi(signf(v.y))))
