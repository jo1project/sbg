# 對戰狀態的畫面提示（CanvasLayer，不受 3D 後製影響）：
# - 開局 3-2-1 倒數大字（同 Flutter game_screen.dart _PreGameCountdown）
# - 橫幅：連線中斷/等待對手重連（同 Flutter _DisconnectBanner）；對局結果在 result_screen.gd
# - 上方一行狀態（連線/配對/能量）；大廳和「開始配對」按鈕在 lobby_screen.gd
# 座標是 1080x1920 基準單位；上方元素避開安全區域（跟 touch_controls.gd 用同一個 safe_insets()）。
extends CanvasLayer

@export var touch_controls: CanvasLayer   # 拿安全區域

var _root: Control
var _countdown: Label
var _banner_panel: PanelContainer
var _banner: Label
var _status: Label

func _ready() -> void:
	layer = 11
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	theme.default_font_size = 40
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme
	add_child(_root)

	_countdown = Label.new()
	_countdown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 260)
	_countdown.add_theme_color_override("font_outline_color", Color.BLACK)
	_countdown.add_theme_constant_override("outline_size", 24)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.hide()
	_root.add_child(_countdown)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 30)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 8)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)

	_banner_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.87)   # 同 Flutter Colors.black87
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(28)
	_banner_panel.add_theme_stylebox_override("panel", sb)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_panel.add_child(_banner)
	_banner_panel.hide()
	_root.add_child(_banner_panel)

	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var ui := get_viewport().get_visible_rect().size
	var top := 0.0
	if touch_controls and touch_controls.has_method("safe_insets"):
		top = touch_controls.safe_insets().y
	_status.position = Vector2(0, top + 16)
	_status.size = Vector2(ui.x, 50)
	_banner_panel.position = Vector2(60, top + 76 * UiStyle.DP)   # 對戰中頂部 HUD（64dp）的下面
	_banner_panel.custom_minimum_size = Vector2(ui.x - 120, 0)
	_banner_panel.size = Vector2(ui.x - 120, 0)

func set_countdown(n: int) -> void:
	_countdown.visible = n > 0
	_countdown.text = str(n)

func show_banner(text: String) -> void:
	_layout()
	_banner.text = text
	_banner_panel.show()

func hide_banner() -> void:
	_banner_panel.hide()

func set_status(text: String) -> void:
	_status.text = text
