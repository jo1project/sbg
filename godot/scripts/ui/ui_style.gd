# 介面共用的尺寸換算與底框樣式（結算畫面、大廳）。
# 尺寸用 dp 設計，同 touch_controls.gd：直向手機寬 412dp 對應基準寬 1080。
class_name UiStyle

const DP := 1080.0 / 412.0

static func box(bg: Color, border: Color, border_dp: float, radius_dp: float, pad_dp: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(round(border_dp * DP)))
	sb.set_corner_radius_all(int(radius_dp * DP))
	sb.set_content_margin_all(pad_dp * DP)
	return sb

static func label(text: String, size_dp: float, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size_dp * DP))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# 沒有文字的按鈕（文字/圖示自己加在裡面），hover 跟 normal 一樣（手機沒有 hover）
static func button(normal: StyleBox, pressed: StyleBox) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", normal)
	return b

# 輸入框（設定頁、好友連線）
static func line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", int(15 * DP))
	e.add_theme_stylebox_override("normal", box(Color("14110d"), Color("3a3228"), 1, 6, 8))
	e.add_theme_stylebox_override("focus", box(Color("14110d"), Color("ba7517"), 1, 6, 8))
	return e

# 金框小按鈕（文字置中）
static func small_button(text: String, cb: Callable, fg := Color("fac775"), bg := Color("2a1f0e"), border := Color("ba7517")) -> Button:
	var b := button(box(bg, border, 1.5, 8, 0), box(bg.lightened(0.1), border, 1.5, 8, 0))
	b.custom_minimum_size = Vector2(60, 40) * DP
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(text, 14, fg)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	b.pressed.connect(cb)
	return b

# 手機鍵盤：iPhone 鍵盤沒有「收起」鍵，Godot 也不會在點別處時自動收，所以有輸入框的頁面在 _input 呼叫這個：
# 按在目前輸入中的 LineEdit 以外的地方就 release_focus（LineEdit 失去焦點時會收起鍵盤）。不吃掉事件，按鈕照常收到。
# 另外：iOS 上 Godot 引擎禁止第三方鍵盤（app delegate 的 shouldAllowExtensionPointIdentifier 回傳 NO），
# 只能輸入英數的欄位（好友編號、繼承碼）用 KEYBOARD_TYPE_EMAIL_ADDRESS 叫出英數鍵盤，不用在注音鍵盤上切換。
static func dismiss_keyboard(event: InputEvent, viewport: Viewport) -> void:
	var down: bool = (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed
	if not down:
		return
	var f := viewport.gui_get_focus_owner() as LineEdit
	if f and not Rect2(Vector2.ZERO, f.size).has_point(f.get_global_transform_with_canvas().affine_inverse() * event.position):
		f.release_focus()
