# 結算畫面（對局結束時蓋在遊戲畫面上）：
#   半透明黑遮罩 → 置中深色面板：
#     結果橫幅（你贏了 綠 / 你輸了 紅 / 平手 灰），斷線、離開這類結束原因用小字寫在標題下面
#     戰績 2x2：得分比數（本場寶石數 我方:對手）、收集寶石數、存活時間、最長身長（伺服器 game_over.stats）
#     按鈕列：「再戰一場」（直接重新排隊）、「返回大廳」
# 尺寸用 dp 設計（同 touch_controls.gd：直向寬 412dp 對應基準寬 1080）。
# Flutter 版的結算畫面還是只有文字 + 返回大廳（差異記在 PARITY.md）。
extends CanvasLayer

signal rematch_pressed
signal lobby_pressed

const DP := UiStyle.DP

const PANEL_BG := Color("1e1a16")
const PANEL_BORDER := Color("3a3228")
const CELL_BG := Color("14110d")
const LABEL_COLOR := Color("888780")
const VALUE_COLOR := Color("fac775")
# 橫幅：[底色, 框色, 文字色]
const HEADER := {
	"win": [Color("173404"), Color("639922"), Color("eaf3de")],
	"lose": [Color("501313"), Color("e24b4a"), Color("f7c1c1")],
	"draw": [Color("2c2c2a"), Color("888780"), Color("d3d1c7")],
}
const TITLE := {"win": "你贏了", "lose": "你輸了", "draw": "平手"}

var _panel: PanelContainer
var _header: PanelContainer
var _title: Label
var _subtitle: Label
var _values: Array[Label] = []

func _ready() -> void:
	layer = 13   # 在大廳（12）上面
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	theme.default_font_size = int(14 * DP)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	add_child(root)

	var mask := ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.6)
	mask.mouse_filter = Control.MOUSE_FILTER_STOP   # 擋住後面的「隨機配對」按鈕
	root.add_child(mask)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, PANEL_BORDER, 3, 12, 16))
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(16 * DP))
	_panel.add_child(col)

	# 結果橫幅
	_header = PanelContainer.new()
	col.add_child(_header)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", int(2 * DP))
	_header.add_child(hcol)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", int(28 * DP))
	hcol.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", int(12 * DP))
	hcol.add_child(_subtitle)

	# 戰績 2x2
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(8 * DP))
	grid.add_theme_constant_override("v_separation", int(8 * DP))
	col.add_child(grid)
	for label in ["得分比數", "收集寶石數", "存活時間", "最長身長"]:
		grid.add_child(_stat_cell(label))

	# 按鈕列
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * DP))
	col.add_child(row)
	row.add_child(_button("再戰一場", "refresh",
		[Color("3b6d11"), Color("639922"), Color("eaf3de"), Color("27500a")], rematch_pressed.emit))
	row.add_child(_button("返回大廳", "home",
		[Color("2c2c2a"), Color("5f5e5a"), Color("d3d1c7"), Color("1f1f1d")], lobby_pressed.emit))

	get_viewport().size_changed.connect(_layout)
	_layout()
	hide()

func _layout() -> void:
	var ui := get_viewport().get_visible_rect().size
	_panel.custom_minimum_size.x = minf(ui.x - 2 * 24 * DP, 360 * DP)

# kind: "win" / "lose" / "draw"；stats: 伺服器 game_over.stats 裡「我方」的那份，opp_gems 對手寶石數（沒有就 -1）
func show_result(kind: String, subtitle: String, my_stats: Dictionary, opp_gems: int) -> void:
	var c: Array = HEADER[kind]
	_header.add_theme_stylebox_override("panel", UiStyle.box(c[0], c[1], 2, 8, 12))
	_title.text = TITLE[kind]
	_title.add_theme_color_override("font_color", c[2])
	_subtitle.text = subtitle
	_subtitle.add_theme_color_override("font_color", Color(c[2], 0.8))
	_subtitle.visible = subtitle != ""

	var gems := int(my_stats.get("gems", -1))
	var survival_ms = my_stats.get("survivalMs")
	var length = my_stats.get("maxLength")
	_values[0].text = "%d : %d" % [gems, opp_gems] if gems >= 0 and opp_gems >= 0 else "—"
	_values[1].text = str(gems) if gems >= 0 else "—"
	_values[2].text = "%.1f 秒" % (float(survival_ms) / 1000.0) if survival_ms != null else "—"
	_values[3].text = str(int(length)) if length != null else "—"
	show()

func _stat_cell(label: String) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", UiStyle.box(CELL_BG, PANEL_BORDER, 1, 6, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(2 * DP))
	cell.add_child(v)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", int(11 * DP))
	l.add_theme_color_override("font_color", LABEL_COLOR)
	v.add_child(l)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", int(18 * DP))
	val.add_theme_color_override("font_color", VALUE_COLOR)
	v.add_child(val)
	_values.append(val)
	return cell

# colors: [底色, 框色, 文字色, 按下時底色]
func _button(text: String, icon: String, colors: Array, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 48 * DP
	b.focus_mode = Control.FOCUS_NONE
	var normal := UiStyle.box(colors[0], colors[1], 1, 8, 0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", UiStyle.box(colors[3], colors[1], 1, 8, 0))
	b.pressed.connect(on_pressed)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(6 * DP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(UiIcon.make(icon, 18, colors[2]))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(15 * DP))
	l.add_theme_color_override("font_color", colors[2])
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return b
