# 一顆寶石（食物）：Sprite3D 懸浮上下飄 + 自發光（吃得到 glow 泛光）+ 小顆同色 OmniLight3D 在地板照出一圈色光。
# 素材：client/assets/ui/food_gem.png（Kenney，35x28，單張無動畫、無切圖），那張的像素密度比地牢素材細很多，
# 照 pixel_size = 1/16 會變成 2 格寬，所以縮成 12x10 像素版（assets/generated/food_gem_12x10.png，約 0.75 格，
# 接近 Flutter 畫的 0.7 格），像素大小才會跟地磚一致。
extends Node3D

const PixelScale := preload("res://scripts/pixel_scale.gd")
const TEX := preload("res://assets/generated/food_gem_12x10.png")
const GEM_COLOR := Color("e86a17")   # 素材主色
const HOVER := 0.3                   # 圖片底緣離地高度
const BOB := 0.06                    # 上下飄的幅度
const BOB_SPEED := 2.2

var _sprite: Sprite3D
var _light: OmniLight3D
var _t := randf() * TAU

func _ready() -> void:
	var px := PixelScale.size()
	_sprite = Sprite3D.new()
	_sprite.texture = TEX
	_sprite.pixel_size = px
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = true
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Sprite3D 本身沒有自發光選項，用同設定的材質覆蓋，多開 emission
	var m := StandardMaterial3D.new()
	m.albedo_texture = TEX
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission_texture = TEX
	m.emission = GEM_COLOR.lerp(Color.WHITE, 0.3)   # 白色外框也泛橘光，不會整顆糊成白色
	m.emission_energy_multiplier = 0.55
	_sprite.material_override = m
	add_child(_sprite)

	_light = OmniLight3D.new()
	_light.light_color = GEM_COLOR
	_light.light_energy = 1.2
	_light.omni_range = 1.5
	_light.shadow_enabled = false
	add_child(_light)
	_update()

func _process(delta: float) -> void:
	_t += delta * BOB_SPEED
	_update()

func _update() -> void:
	var h := TEX.get_height() * _sprite.pixel_size
	_sprite.position.y = HOVER + h / 2.0 + sin(_t) * BOB
	_light.position.y = HOVER + h / 2.0

# 被吃掉：原地留一個像素粒子閃光，自己立刻消失
func burst_and_free() -> void:
	var fx := _make_burst()
	get_parent().add_child(fx)
	fx.global_position = _sprite.global_position
	fx.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = GEM_COLOR.lightened(0.3)
	flash.light_energy = 4.0
	flash.omni_range = 2.5
	fx.add_child(flash)
	var tw := fx.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	get_tree().create_timer(fx.lifetime + 0.1).timeout.connect(fx.queue_free)
	queue_free()

func _make_burst() -> CPUParticles3D:
	var px := PixelScale.size()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.45
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2(2, 2) * px   # 2x2 像素的方塊
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -4.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.6, 1.5, 1.2))          # 超過 1 讓泛光吃得到
	ramp.set_color(1, GEM_COLOR * 1.3)
	p.color_ramp = ramp
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(0.7, 0.8))
	shrink.add_point(Vector2(1, 0))
	p.scale_amount_curve = shrink
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
