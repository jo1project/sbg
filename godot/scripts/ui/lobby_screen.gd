# 大廳（線上模式，連上伺服器後、按「開始配對」之前的畫面；結算畫面「返回大廳」也回到這裡）。
# 由上到下：
#   頂部列：設定齒輪（敬請期待）、鑽石數量（功能未做，先顯示 0）
#   Logo 橫幅：地牢地板磚紋底 +「JO一個英雄」金字深棕紅描邊（字級依寬度縮到放得下，不換行不裁切）+「SNAKE BATTLE」
#   玩家資訊卡：頭像（預設圖示）、名稱（暱稱未做，先用 ID）、勝／敗（伺服器 player_records）
#   造型預覽：目前的蛇（英雄 + 哥布林）、金框箭頭 → 造型頁（敬請期待）
#   「開始配對」按鈕（按了才進原本的「配對中…」畫面）
#   底部導覽：造型／排行榜／好友（未開放，灰階，點了顯示敬請期待）
# 顯示時會把觸控操作（搖桿、攻擊按鈕）關掉，免得點到底部導覽時一起觸發搖桿。
extends CanvasLayer

signal start_pressed

const CharacterSprites := preload("res://scripts/character_sprites.gd")
const DP := UiStyle.DP

const BG := Color("14110d")
const PANEL_BG := Color("1e1a16")
const PANEL_BORDER := Color("3a3228")
const GOLD := Color("fac775")
const GOLD_BORDER := Color("ba7517")
const TITLE_OUTLINE := Color("4a1b0c")
const SUBTITLE := Color("f0997b")
const BLUE := Color("378add")
const WIN_GREEN := Color("97c459")
const GREY := Color("888780")
const TEXT := Color("d3d1c7")
const GREEN_BG := Color("173404")
const GREEN_BORDER := Color("639922")
const GREEN_TEXT := Color("eaf3de")
const FLOORS := ["floor_1", "floor_2", "floor_3", "floor_4", "floor_5", "floor_6", "floor_7", "floor_8"]

@export var touch_controls: CanvasLayer   # 安全區域 + 顯示大廳時關掉觸控操作

var _col: VBoxContainer
var _title: Label
var _name: Label
var _id: Label
var _wins: Label
var _losses: Label
var _start: Button
var _start_label: Label
var _notice: Label
var _soon: Control
var _soon_title: Label
var _ready_to_start := false
var _floor_tex: Array[Texture2D] = []

func _ready() -> void:
	layer = 12   # StatusOverlay（11）上面、結算畫面（13）下面
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	theme.default_font_size = int(14 * DP)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	root.add_child(bg)

	_col = VBoxContainer.new()
	_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_col.add_theme_constant_override("separation", int(14 * DP))
	root.add_child(_col)

	_col.add_child(_top_bar())
	_col.add_child(_logo())
	_col.add_child(_player_card())
	_col.add_child(_skin_preview())

	_start = _plain_button(UiStyle.box(GREEN_BG, GREEN_BORDER, 2, 10, 0), UiStyle.box(Color("27500a"), GREEN_BORDER, 2, 10, 0))
	_start.custom_minimum_size.y = 60 * DP
	_start.pressed.connect(func():
		if _ready_to_start:
			start_pressed.emit())
	_start_label = UiStyle.label("開始配對", 22, GREEN_TEXT)
	_start_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_start.add_child(_start_label)
	_col.add_child(_start)

	_notice = UiStyle.label("", 12, GREY)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(_notice)

	_col.add_child(_bottom_nav())

	_soon = _coming_soon_page()
	root.add_child(_soon)

	visibility_changed.connect(_sync_touch_controls)
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_ready(false, "連線中…")
	_sync_touch_controls()

func _layout() -> void:
	var ui := get_viewport().get_visible_rect().size
	var inset := Vector4.ZERO
	if touch_controls and touch_controls.has_method("safe_insets"):
		inset = touch_controls.safe_insets()
	var side := 16 * DP
	_col.offset_left = inset.x + side
	_col.offset_right = -(inset.z + side)
	_col.offset_top = inset.y + 8 * DP
	_col.offset_bottom = -(inset.w + 8 * DP)
	# 標題字級：預設 40dp，放不下就縮（不換行、不裁切）
	var avail := ui.x - inset.x - inset.z - 2 * side - 2 * 16 * DP
	var want := int(40 * DP)
	var w := UiFont.get_font().get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, want).x + 2 * 6 * DP
	_title.add_theme_font_size_override("font_size", want if w <= avail else int(want * avail / w))

# ---------- 給 game_session 呼叫 ----------

# can_start：已連上伺服器、可以配對；notice：按鈕下方的小字（連線狀態、返回大廳的原因）
func set_ready(can_start: bool, notice := "") -> void:
	_ready_to_start = can_start
	_start.modulate = Color.WHITE if can_start else Color(1, 1, 1, 0.45)
	_start_label.text = "開始配對" if can_start else "連線中…"
	_notice.text = notice

func set_notice(text: String) -> void:
	_notice.text = text

# record：伺服器 identified / game_over.stats 的 { wins, losses, draws }
func set_player(player_id: String, record: Dictionary) -> void:
	_name.text = "玩家 %s" % player_id    # 暱稱功能還沒做，先用 ID
	_id.text = "ID %s" % player_id
	set_record(record)

func set_record(record: Dictionary) -> void:
	_wins.text = "%d 勝" % int(record.get("wins", 0))
	_losses.text = "%d 敗" % int(record.get("losses", 0))

func _sync_touch_controls() -> void:
	if touch_controls:
		touch_controls.visible = not visible
		touch_controls.process_mode = Node.PROCESS_MODE_DISABLED if visible else Node.PROCESS_MODE_INHERIT
	if not visible:
		_soon.hide()

# ---------- 各區塊 ----------

func _top_bar() -> Control:
	var row := HBoxContainer.new()
	var gear := _icon_button("gear", 26, TEXT, UiStyle.box(PANEL_BG, PANEL_BORDER, 1, 8, 0))
	gear.pressed.connect(_show_soon.bind("設定"))
	row.add_child(gear)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	# 鑽石（功能未做，先保留位置）
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiStyle.box(Color("2a1f0e"), GOLD_BORDER, 1.5, 20, 0))
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", int(6 * DP))
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, int(12 * DP))
	pill.add_child(m)
	m.add_child(pr)
	pr.add_child(_icon("diamond", 18, GOLD))
	var n := UiStyle.label("0", 16, GOLD)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(n)
	pill.custom_minimum_size.y = 36 * DP
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pill)
	return row

func _logo() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.custom_minimum_size.y = 150 * DP
	panel.clip_contents = true
	# 地牢地板磚紋（同遊戲場景的素材），放大成像素風
	var tiles := Control.new()
	tiles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tiles.draw.connect(_draw_tiles.bind(tiles))
	tiles.resized.connect(tiles.queue_redraw)
	panel.add_child(tiles)
	var shade := Panel.new()
	var sb := UiStyle.box(Color(0, 0, 0, 0.35), PANEL_BORDER, 3, 10, 0)
	shade.add_theme_stylebox_override("panel", sb)
	panel.add_child(shade)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", int(2 * DP))
	panel.add_child(v)
	_title = UiStyle.label("JO一個英雄", 40, GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.add_theme_color_override("font_outline_color", TITLE_OUTLINE)
	_title.add_theme_constant_override("outline_size", int(6 * DP))
	v.add_child(_title)
	var sub := UiStyle.label("SNAKE BATTLE", 13, SUBTITLE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wide := FontVariation.new()
	wide.base_font = UiFont.get_font()
	wide.spacing_glyph = int(5 * DP)   # 字距加寬
	sub.add_theme_font_override("font", wide)
	v.add_child(sub)
	return panel

func _draw_tiles(c: Control) -> void:
	if _floor_tex.is_empty():
		# 素材匯入時會轉成 3D 用的 VRAM 壓縮格式，2D 直接畫在某些平台會是白的；轉成一般 ImageTexture 再畫
		for f in FLOORS:
			_floor_tex.append(ImageTexture.create_from_image((load("res://assets/dungeon/%s.png" % f) as Texture2D).get_image()))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7   # 固定花紋，每次開起來一樣
	var t := 32 * DP   # 一格磚（16px 素材）的大小
	for y in ceili(c.size.y / t):
		for x in ceili(c.size.x / t):
			var i := rng.randi_range(1, FLOORS.size() - 1) if rng.randf() < 0.12 else 0   # 大多是素面磚，偶爾有裂紋
			c.draw_texture_rect(_floor_tex[i], Rect2(x * t, y * t, t, t), false)

func _player_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 1.5, 10, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12 * DP))
	card.add_child(row)
	# 頭像（預留：之後換成玩家自訂頭像）
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2.ONE * 56 * DP
	avatar.add_theme_stylebox_override("panel", UiStyle.box(Color("0c2340"), BLUE, 2, 8, 8))
	avatar.add_child(_icon("person", 36, Color("85b7eb")))
	row.add_child(avatar)
	# 名稱（預留：暱稱）
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	_name = UiStyle.label("玩家", 18, TEXT)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_name)
	_id = UiStyle.label("", 11, GREY)
	names.add_child(_id)
	row.add_child(names)
	# 勝／敗
	var rec := VBoxContainer.new()
	rec.alignment = BoxContainer.ALIGNMENT_CENTER
	_wins = UiStyle.label("0 勝", 17, WIN_GREEN)
	_wins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rec.add_child(_wins)
	_losses = UiStyle.label("0 敗", 17, GREY)
	_losses.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rec.add_child(_losses)
	row.add_child(rec)
	return card

func _skin_preview() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * DP))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 多的高度給這塊
	# 左：目前的蛇（英雄帶頭 + 哥布林身體，朝右站著），英雄選擇未做，先固定
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 130 * DP
	panel.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 1.5, 10, 10))
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UiStyle.label("目前造型", 11, GREY))
	var snake := HBoxContainer.new()
	snake.alignment = BoxContainer.ALIGNMENT_CENTER
	snake.size_flags_vertical = Control.SIZE_EXPAND_FILL
	snake.add_theme_constant_override("separation", int(-26 * DP))
	var right_row := 2   # 精靈表第 2 列 = 朝右
	for i in 4:
		var sheet := "res://assets/sprites/goblin.png" if i < 3 else "res://assets/sprites/hero.png"
		var img := (load(sheet) as Texture2D).get_image().get_region(
			Rect2i(CharacterSprites.STAND_COL * CharacterSprites.FRAME, right_row * CharacterSprites.FRAME, CharacterSprites.FRAME, CharacterSprites.FRAME))
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2.ONE * 80 * DP
		snake.add_child(tr)
	v.add_child(snake)
	row.add_child(panel)
	# 右：金框箭頭 → 造型頁
	var go := _icon_button("chevron", 28, GOLD, UiStyle.box(Color("2a1f0e"), GOLD_BORDER, 2, 10, 0))
	go.custom_minimum_size = Vector2(56 * DP, 0)
	go.size_flags_vertical = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_show_soon.bind("造型"))
	row.add_child(go)
	return row

func _bottom_nav() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 1.5, 12, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * DP))
	bar.add_child(row)
	# 三個都還沒開放：灰階，點了顯示敬請期待
	for item in [["skin", "造型"], ["trophy", "排行榜"], ["friends", "好友"]]:
		var b := _plain_button(StyleBoxEmpty.new(), UiStyle.box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0, 8, 0))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 58 * DP
		b.pressed.connect(_show_soon.bind(item[1]))
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", int(2 * DP))
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := _icon(item[0], 24, GREY)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var l := UiStyle.label(item[1], 12, GREY)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		b.add_child(v)
		row.add_child(b)
	return bar

# 還沒做的功能：蓋一層「敬請期待」
func _coming_soon_page() -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mask := ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.75)
	page.add_child(mask)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 280 * DP
	panel.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 3, 12, 20))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(12 * DP))
	panel.add_child(v)
	_soon_title = UiStyle.label("", 16, GREY)
	_soon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_soon_title)
	var big := UiStyle.label("敬請期待", 30, GOLD)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_color_override("font_outline_color", TITLE_OUTLINE)
	big.add_theme_constant_override("outline_size", int(4 * DP))
	v.add_child(big)
	var back := _plain_button(UiStyle.box(Color("2c2c2a"), Color("5f5e5a"), 1, 8, 0), UiStyle.box(Color("1f1f1d"), Color("5f5e5a"), 1, 8, 0))
	back.custom_minimum_size.y = 46 * DP
	var bl := UiStyle.label("返回", 15, TEXT)
	bl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back.add_child(bl)
	back.pressed.connect(func(): page.hide())
	v.add_child(back)
	page.hide()
	return page

func _show_soon(title: String) -> void:
	_soon_title.text = title
	_soon.show()

# ---------- 小工具 ----------

func _plain_button(normal: StyleBox, pressed: StyleBox) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", normal)
	return b

func _icon_button(icon: String, size_dp: float, color: Color, style: StyleBox) -> Button:
	var b := _plain_button(style, style)
	b.custom_minimum_size = Vector2.ONE * 44 * DP
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_icon(icon, size_dp, color))
	b.add_child(c)
	return b

func _icon(icon: String, size_dp: float, color: Color) -> Control:
	return UiIcon.make(icon, size_dp, color)
