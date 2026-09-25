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
