# 火把光源輕微閃爍：亮度/範圍跟著 1D 雜訊小幅擺動，每支火把 seed 不同就不會同步閃。
extends OmniLight3D

@export var noise_seed := 0
@export var energy_jitter := 0.18   # 亮度擺動比例
@export var range_jitter := 0.05    # 範圍擺動比例
@export var speed := 6.0

var _noise := FastNoiseLite.new()
var _base_energy := 0.0
var _base_range := 0.0
var _t := 0.0

func _ready() -> void:
	_noise.seed = noise_seed
	_noise.frequency = 1.0
	_base_energy = light_energy
	_base_range = omni_range

func _process(delta: float) -> void:
	_t += delta * speed
	var n := _noise.get_noise_1d(_t)   # 約 -1 ~ 1
	light_energy = _base_energy * (1.0 + energy_jitter * n)
	omni_range = _base_range * (1.0 + range_jitter * n)
