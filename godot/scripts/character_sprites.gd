# 角色精靈表 -> SpriteFrames。素材同 Flutter（client/lib/game/character_sprites.dart）：
# Puny Characters 928x256，29 欄 x 8 列，每格 32x32。欄 0 = 站立、1~4 = 走路循環。
# 列 = 方向（8 方向都有）：0 下(正面) 1 右下 2 右 3 右上 4 上(背面) 5 左上 6 左 7 左下。
# 本檔的方向編號 dir 就用同一套順序（0 = 朝鏡頭，順時針每 45° +1）。
# 如果之後換成只有 5 方向（下、右下、右、右上、上）的素材，把 rows 設成 5 列的 ROWS_5DIR，
# 左側 3 個方向會自動用右側那列水平翻轉補上（flip_for()）。
extends RefCounted

const FRAME := 32
const STAND_COL := 0
const WALK_COLS := [1, 2, 3, 4]
const FEET_ROW := 24          # 腳底所在像素列（量過 hero/goblin 全部幀，都是 24）
const ROWS_8DIR := [0, 1, 2, 3, 4, 5, 6, 7]
const ROWS_5DIR := [0, 1, 2, 3, 4]

# dir 0~7 在 5 方向素材裡對應哪一列、要不要翻轉：5 左上=翻 3 右上、6 左=翻 2 右、7 左下=翻 1 右下
const MIRROR_OF := {5: 3, 6: 2, 7: 1}

static func build(path: String, rows: Array = ROWS_8DIR, walk_fps := 6.0) -> SpriteFrames:
	var img := (load(path) as Texture2D).get_image()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for dir in 8:
		var src_dir := dir
		if rows.size() < 8 and MIRROR_OF.has(dir):
			src_dir = MIRROR_OF[dir]
		var row: int = rows[src_dir]
		var walk := "walk_%d" % dir
		var stand := "stand_%d" % dir
		frames.add_animation(walk)
		frames.set_animation_speed(walk, walk_fps)
		for c in WALK_COLS:
			frames.add_frame(walk, _cut(img, c, row))
		frames.add_animation(stand)
		frames.add_frame(stand, _cut(img, STAND_COL, row))
	return frames

# 5 方向素材時，dir 5~7 要水平翻轉顯示
static func flip_for(dir: int, rows: Array = ROWS_8DIR) -> bool:
	return rows.size() < 8 and MIRROR_OF.has(dir)

static func _cut(img: Image, col: int, row: int) -> Texture2D:
	return ImageTexture.create_from_image(img.get_region(Rect2i(col * FRAME, row * FRAME, FRAME, FRAME)))
