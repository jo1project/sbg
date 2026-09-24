# 全專案共用的像素比例：pixel_size = 1 / 地磚像素寬度（地磚 1 張 = 世界 1 格）。
# 所有 Sprite3D / 以像素為單位的道具尺寸都用這個，怪物、角色、火焰、地板的像素才會一樣大。
extends RefCounted

const TILE_TEXTURE := "res://assets/dungeon/floor_1.png"

static var _size := 0.0

static func size() -> float:
	if _size == 0.0:
		_size = 1.0 / (load(TILE_TEXTURE) as Texture2D).get_width()
	return _size
