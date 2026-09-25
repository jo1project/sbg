# 介面小圖示（字型裡沒有這些符號，用畫的）。座標以 24x24 設計，依實際大小縮放。
# 用法：UiIcon.make("person", 24, Color.WHITE)（大小是 dp）
class_name UiIcon
extends Control

var icon := ""
var color := Color.WHITE

static func make(icon_name: String, size_dp: float, c: Color) -> UiIcon:
	var ic := UiIcon.new()
	ic.icon = icon_name
	ic.color = c
	ic.custom_minimum_size = Vector2.ONE * size_dp * UiStyle.DP
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * size.x / 24.0)
	var c := Vector2(12, 12)
	match icon:
		"gear":
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				var n := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([c + d * 6 + n * 2, c + d * 10.5 + n * 1.6, c + d * 10.5 - n * 1.6, c + d * 6 - n * 2]), color)
			draw_arc(c, 5.5, 0, TAU, 32, color, 3.0, true)
		"diamond":
			draw_colored_polygon(PackedVector2Array([Vector2(6, 4), Vector2(18, 4), Vector2(22, 9), Vector2(12, 21), Vector2(2, 9)]), color)
			draw_line(Vector2(2, 9), Vector2(22, 9), Color(0, 0, 0, 0.35), 1.2)
			draw_line(Vector2(9, 4), Vector2(12, 21), Color(0, 0, 0, 0.25), 1.0)
			draw_line(Vector2(15, 4), Vector2(12, 21), Color(0, 0, 0, 0.25), 1.0)
		"person":
			draw_circle(Vector2(12, 8), 4.5, color)
			draw_colored_polygon(PackedVector2Array([Vector2(3, 22), Vector2(4.5, 16), Vector2(8, 13.5), Vector2(16, 13.5), Vector2(19.5, 16), Vector2(21, 22)]), color)
		"chevron":
			draw_polyline(PackedVector2Array([Vector2(8, 4), Vector2(16, 12), Vector2(8, 20)]), color, 3.2, true)
		"skin":
			# 上衣
			draw_colored_polygon(PackedVector2Array([Vector2(8, 3), Vector2(2, 7), Vector2(4.5, 11.5), Vector2(6.5, 10.5), Vector2(6.5, 21),
				Vector2(17.5, 21), Vector2(17.5, 10.5), Vector2(19.5, 11.5), Vector2(22, 7), Vector2(16, 3), Vector2(14, 5.5), Vector2(10, 5.5)]), color)
		"trophy":
			draw_colored_polygon(PackedVector2Array([Vector2(6, 3), Vector2(18, 3), Vector2(17, 10), Vector2(14, 14), Vector2(10, 14), Vector2(7, 10)]), color)
			draw_arc(Vector2(6, 7), 3, PI / 2, PI * 1.5, 12, color, 1.6, true)
			draw_arc(Vector2(18, 7), 3, -PI / 2, PI / 2, 12, color, 1.6, true)
			draw_rect(Rect2(10.5, 14, 3, 4), color)
			draw_rect(Rect2(7, 18, 10, 3), color)
		"friends":
			draw_circle(Vector2(8.5, 8), 3.5, color)
			draw_colored_polygon(PackedVector2Array([Vector2(2, 20), Vector2(3, 15), Vector2(6, 13), Vector2(11, 13), Vector2(14, 15), Vector2(15, 20)]), color)
			draw_circle(Vector2(16.5, 7), 3, color)
			draw_colored_polygon(PackedVector2Array([Vector2(16, 12), Vector2(19.5, 12), Vector2(22, 14), Vector2(23, 19), Vector2(16.5, 19), Vector2(15.5, 14.5)]), color)
		"refresh":
			# 缺一角的圓 + 箭頭
			draw_arc(c, 7.5, deg_to_rad(-60), deg_to_rad(240), 32, color, 2.4, true)
			var tip := c + Vector2.from_angle(deg_to_rad(-60)) * 7.5
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-4.5, -3.5), tip + Vector2(3.5, -4.5), tip + Vector2(1.5, 3.5)]), color)
		"home":
			# 屋頂三角 + 屋身，中間門口
			draw_colored_polygon(PackedVector2Array([Vector2(12, 3), Vector2(22, 12), Vector2(2, 12)]), color)
			draw_rect(Rect2(5, 11, 14, 10), color)
			draw_rect(Rect2(10, 14, 4, 7), Color(0, 0, 0, 0.55))
		"swords":
			# 兩把劍交叉：劍身 + 護手 + 劍柄
			for flip in [1.0, -1.0]:
				var a := Vector2(12 - 8 * flip, 3)     # 劍尖
				var b := Vector2(12 + 5 * flip, 17)    # 護手位置
				var dir := (b - a).normalized()
				var n := Vector2(-dir.y, dir.x)
				draw_colored_polygon(PackedVector2Array([a, b + n * 1.4, b - n * 1.4]), color)
				draw_line(b + n * 3.2, b - n * 3.2, color, 2.0, true)
				draw_line(b, b + dir * 4.5, color, 2.2, true)
