# 介面共用字型。
# 不能只靠 SystemFont：iOS 上找不到系統中文字型時 Label 整個畫不出字（只剩底框），
# 所以打包 Noto Sans TC 常用字子集（tools/make_cjk_font.py 產生），子集沒有的字再退回系統字型。
class_name UiFont

const FONT_PATH := "res://assets/fonts/NotoSansTC-Bold-subset.ttf"

static var _font: Font

static func get_font() -> Font:
	if _font == null:
		var f: FontFile = load(FONT_PATH)
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["PingFang TC", "Microsoft JhengHei", "Noto Sans CJK TC", "Noto Sans TC", "sans-serif"])
		f.fallbacks = [sys]
		_font = f
	return _font
