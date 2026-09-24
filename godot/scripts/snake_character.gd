# 蛇的一節（蛇頭或身體）：AnimatedSprite3D，自己依「插值後的實際移動速度」決定 8 方向與走路動畫快慢。
# 由 snake_train.gd 每幀呼叫 move_to() 餵顯示位置。
extends AnimatedSprite3D

const CharacterSprites := preload("res://scripts/character_sprites.gd")
const PX := 1.0 / 16.0

var rows: Array = CharacterSprites.ROWS_8DIR
var base_speed := 1.0         # 正常移動速度（格/秒），此速度下 speed_scale = 1
var dir := 0                  # 目前面向（0 = 朝鏡頭，順時針 +1，見 character_sprites.gd）
var _moving := false

# 精靈中心在 32px 幀的第 16 列，腳在第 24 列 => 整張往上抬 8px，腳踩在地板 y=0
const LIFT := (CharacterSprites.FEET_ROW - CharacterSprites.FRAME / 2.0) * PX

func setup(frames: SpriteFrames, sheet_rows: Array, speed: float) -> void:
	sprite_frames = frames
	rows = sheet_rows
	base_speed = speed
	pixel_size = PX
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	shaded = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply(false)

# 直接放到某位置（不算速度、不改方向），用在初始擺放
func place(ground: Vector3, facing: int) -> void:
	position = Vector3(ground.x, LIFT, ground.z)
	dir = facing
	_apply(false)

# ground: 這一幀在地面上的顯示位置（y 忽略）；cam_yaw: 攝影機繞 Y 軸的角度
func move_to(ground: Vector3, delta: float, cam_yaw: float) -> void:
	var v := ground - position
	v.y = 0
	position = Vector3(ground.x, LIFT, ground.z)
	var speed := v.length() / maxf(delta, 1e-5)
	var moving := speed > base_speed * 0.05
	if moving:
		# 轉成相對攝影機的方向：鏡頭朝 -z 時，+z（JSON y 變大）= 朝鏡頭 = 正面
		var rel := v.rotated(Vector3.UP, -cam_yaw)
		var ang := atan2(rel.x, rel.z)   # 0 = 朝鏡頭，+90° = 右，180° = 背面
		dir = posmod(roundi(ang / (PI / 4.0)), 8)
		speed_scale = speed / base_speed
	# 停下時不改 dir，保留最後方向
	_apply(moving)

func _apply(moving: bool) -> void:
	var anim := ("walk_%d" if moving else "stand_%d") % dir
	flip_h = CharacterSprites.flip_for(dir, rows)
	if animation != anim:
		var f := frame
		var p := frame_progress
		play(anim)
		# 走路中換方向時沿用目前的步伐幀，不要每次轉向都從第一幀重來
		if moving and _moving:
			set_frame_and_progress(f % sprite_frames.get_frame_count(anim), p)
	_moving = moving
