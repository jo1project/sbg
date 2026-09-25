# 攻擊命中橫幅的像素風爆裂圖（程式產生，不用圖片素材）：
#   背景：中央放射狀的像素三角形（尖刺長短不一），由外到內 深棕紅描邊 → #993C1D 主色 → 橘 → 金黃核心
#   文字：「ATTACK」5x7 點陣字（等寬、加粗），金黃 #FAC775 + 深棕紅 #4A1B0C 描邊與下方陰影
# 先畫在小尺寸 Image 上，顯示時用最近鄰放大，所以邊緣是方塊像素，跟地牢場景的像素素材一致。
# frames() 回傳 3 幀（尖刺長度、相位、亮度略不同），combat_hud.gd 輪播做閃爍。
extends RefCounted

const W := 160
const H := 80
const SPIKES := 14

const OUTLINE := Color("4a1b0c")
const MAIN := Color("993c1d")
const MID := Color("d85a30")
const INNER := Color("ef9f27")
const CORE := Color("fac775")
const TEXT := Color("fac775")
const TEXT_HI := Color("fff1c8")

# 5x7 點陣字（只需要 ATTACK 這幾個字母）
const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
}

static func frames() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for f in 3:
		out.append(ImageTexture.create_from_image(_frame(f)))
	return out

static func _frame(f: int) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 每根尖刺的長度（固定種子，每幀稍微不同）
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + f * 17
	var lens: Array[float] = []
	for i in SPIKES:
		lens.append(rng.randf_range(0.62, 1.0))
	var phase := 0.5 * f / 3.0         # 每幀轉一點點
	var glow: float = [1.0, 1.12, 0.94][f]   # 每幀亮度不同 → 閃爍
	var cx := W / 2.0
	var cy := H / 2.0
	for y in H:
		for x in W:
			# 橢圓座標（橫幅是扁的），d = 1 碰到邊
			var dx := (x + 0.5 - cx) / (W / 2.0)
			var dy := (y + 0.5 - cy) / (H / 2.0)
			var d := sqrt(dx * dx + dy * dy)
			var a := fposmod(atan2(dy, dx) / TAU * SPIKES + phase, SPIKES)
			var i := int(a)
			var frac := a - i
			# 三角形尖刺：尖端在每一格的中間
			var tri := 1.0 - absf(frac - 0.5) * 2.0
			var r := 0.5 + (lens[i] * 0.5) * tri   # 谷底 0.5：主體夠大，文字後面整片都是爆炸
			var col := Color(0, 0, 0, 0)
			if d < r * 0.42:
				col = CORE
			elif d < r * 0.62:
				col = INNER
			elif d < r * 0.8:
				col = MID
			elif d < r:
				col = MAIN
			elif d < r + 0.06:
				col = OUTLINE
			if col.a > 0.0 and col != OUTLINE:
				col = Color(minf(col.r * glow, 1.0), minf(col.g * glow, 1.0), minf(col.b * glow, 1.0))
			img.set_pixel(x, y, col)
	# 四周飛散的像素碎片（2x2 方塊）
	for k in 14:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.9, 1.15)
		var px := int(cx + cos(ang) * dist * W / 2.0)
		var py := int(cy + sin(ang) * dist * H / 2.0)
		var c: Color = [MAIN, MID, INNER][k % 3]
		for oy in 2:
			for ox in 2:
				if px + ox >= 0 and px + ox < W and py + oy >= 0 and py + oy < H and img.get_pixel(px + ox, py + oy).a == 0.0:
					img.set_pixel(px + ox, py + oy, c)
	_draw_text(img, "ATTACK", f)
	return img

static func _draw_text(img: Image, text: String, f: int) -> void:
	var s := 3                       # 點陣放大倍數
	var adv := 5 * s + 1 + 3         # 字寬 + 加粗 1px + 間距
	var tw := adv * text.length() - 3
	var ox := (W - tw) / 2
	var oy := (H - 7 * s) / 2 - 1
	# 字的像素（加粗：每個點往右多 1px）
	var mask := {}
	for li in text.length():
		var g: Array = GLYPHS[text[li]]
		for gy in 7:
			for gx in 5:
				if g[gy][gx] != "#":
					continue
				for py in s:
					for px in s + 1:
						mask[Vector2i(ox + li * adv + gx * s + px, oy + gy * s + py)] = true
	# 描邊（周圍 2px）+ 下方陰影
	for p in mask:
		for ddy in range(-2, 4):
			for ddx in range(-2, 3):
				var q: Vector2i = p + Vector2i(ddx, ddy)
				if not mask.has(q) and q.x >= 0 and q.x < W and q.y >= 0 and q.y < H:
					img.set_pixelv(q, OUTLINE)
	for p in mask:
		# 金黃為主，每個字最上面一排點陣亮一點；第 2 幀整個亮（閃）
		var top: bool = (p.y - oy) < s
		img.set_pixelv(p, TEXT_HI if top or f == 1 else TEXT)
