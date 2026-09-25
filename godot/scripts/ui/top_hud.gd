# 對戰中的頂部 HUD（CanvasLayer 10：在失明遮罩（combat_hud，9）上面，失明時一樣看得到能量）。
# 功能同 Flutter game_screen.dart _TopBar（EnergyBar + _MiniMap），外觀照新設計：
#   左：己方藍色頭像 + 藍色能量條（左→右填）+ 數字
#   中：對手模糊位置小地圖（opponent_position_fuzzy，每 2 秒；對 NPC 伺服器不送，就不顯示點）+ 下方交叉劍圖示
#   右：對手紅色系，能量條由右往左填
#   整列深色底 #14110d，跟下面的地牢場景分層；上方延伸到安全區域
# 能量以伺服器 energy_update 為準，條的滿格 = 效果封頂 10（CONFIG.ENERGY_CAP），超過 10 條維持全滿、數字照實顯示。
extends CanvasLayer

const DP := UiStyle.DP
const ENERGY_CAP := 10.0
const MAP_COLS := 12.0   # CONFIG.MAP_WIDTH
const MAP_ROWS := 24.0   # CONFIG.MAP_HEIGHT
const HEIGHT_DP := 64.0  # 安全區域以下的高度

const BG := Color("14110d")
const LINE := Color("3a3228")
# [條底色, 填色, 框, 滿格時的框, 文字, 頭像底]
const MINE := [Color("0c1a24"), Color("378add"), Color("042c53"), Color("85b7eb"), Color("85b7eb"), Color("0c2340")]
const OPP := [Color("240d0d"), Color("e24b4a"), Color("501313"), Color("f09595"), Color("f09595"), Color("3a1010")]

@export var touch_controls: CanvasLayer   # 安全區域

var _bar_bg: Panel
var _row: HBoxContainer
var _my_bar: EnergyBar
var _opp_bar: EnergyBar
var _my_num: Label
var _opp_num: Label
var _map: MiniMap

func _ready() -> void:
	layer = 10
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	_bar_bg = Panel.new()
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = LINE
	sb.border_width_bottom = int(1.5 * DP)
	_bar_bg.add_theme_stylebox_override("panel", sb)
	root.add_child(_bar_bg)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(6 * DP))
	root.add_child(_row)

	_row.add_child(_avatar(MINE))
	_my_bar = EnergyBar.new(MINE, false)
	_row.add_child(_my_bar)
	_my_num = _number(MINE)
	_row.add_child(_my_num)

	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", int(2 * DP))
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mm := CenterContainer.new()
	mm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map = MiniMap.new()
	mm.add_child(_map)
	mid.add_child(mm)
	var sw := CenterContainer.new()
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_child(UiIcon.make("swords", 16, Color("fac775")))
	mid.add_child(sw)
	_row.add_child(mid)

	_opp_num = _number(OPP)
	_opp_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row.add_child(_opp_num)
	_opp_bar = EnergyBar.new(OPP, true)
	_row.add_child(_opp_bar)
	_row.add_child(_avatar(OPP))

	get_viewport().size_changed.connect(_layout)
	_layout()
	set_energy(0, 0)
	hide()

func _layout() -> void:
	var ui := get_viewport().get_visible_rect().size
	var inset := Vector4.ZERO
	if touch_controls and touch_controls.has_method("safe_insets"):
		inset = touch_controls.safe_insets()
	var h := HEIGHT_DP * DP
	_bar_bg.position = Vector2.ZERO
	_bar_bg.size = Vector2(ui.x, inset.y + h)
	var side := 12 * DP
	_row.position = Vector2(inset.x + side, inset.y)
	_row.size = Vector2(ui.x - inset.x - inset.z - 2 * side, h)

# 整列（含安全區域）的底邊，其他提示要排在這下面
func bottom() -> float:
	return _bar_bg.size.y

# ---------- 給 game_session 呼叫 ----------

func set_energy(mine: float, opp: float) -> void:
	_my_bar.set_value(mine / ENERGY_CAP)
	_opp_bar.set_value(opp / ENERGY_CAP)
	_my_num.text = str(int(mine))
	_opp_num.text = str(int(opp))

# 格子座標（有雜訊，可能超出地圖一點）；null = 沒有（NPC、還沒收到）
func set_opponent_pos(p) -> void:
	_map.pos = p
	_map.queue_redraw()

# ---------- 元件 ----------

func _avatar(c: Array) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2.ONE * 32 * DP
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UiStyle.box(c[5], c[1], 1.5, 6, 4))
	box.add_child(UiIcon.make("person", 22, c[4]))
	return box

func _number(c: Array) -> Label:
	var l := UiStyle.label("0", 16, c[4])
	l.custom_minimum_size.x = 22 * DP
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	return l

class EnergyBar extends Control:
	var colors: Array
	var reverse := false   # true = 由右往左填（對手）
	var value := 0.0

	func _init(c: Array, from_right: bool) -> void:
		colors = c
		reverse = from_right
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		custom_minimum_size = Vector2(40, 14) * UiStyle.DP
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: float) -> void:
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var r := 4 * UiStyle.DP
		var full := value >= 1.0
		_round(Rect2(Vector2.ZERO, size), colors[0], r)
		if value > 0.0:
			var w := size.x * value
			_round(Rect2(Vector2(size.x - w if reverse else 0.0, 0), Vector2(w, size.y)), colors[1], r)
		# 框：滿格時變亮（Flutter 滿格加白框）
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = colors[3] if full else colors[2]
		sb.set_border_width_all(int((2.0 if full else 1.5) * UiStyle.DP))
		sb.set_corner_radius_all(int(r))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))

	func _round(rect: Rect2, c: Color, r: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		draw_style_box(sb, rect)

class MiniMap extends Control:
	var pos = null   # Vector2（格子座標）或 null

	func _init() -> void:
		custom_minimum_size = Vector2(20, 36) * UiStyle.DP   # 地圖 12x24 的比例
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06)
		sb.border_color = Color(1, 1, 1, 0.24)
		sb.set_border_width_all(int(UiStyle.DP))
		sb.set_corner_radius_all(int(3 * UiStyle.DP))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if pos != null:
			var fx := clampf((pos.x + 0.5) / MAP_COLS, 0.0, 1.0)
			var fy := clampf((pos.y + 0.5) / MAP_ROWS, 0.0, 1.0)
			draw_circle(Vector2(fx * size.x, fy * size.y), 3 * UiStyle.DP, Color("ffd740"))   # Flutter amberAccent
