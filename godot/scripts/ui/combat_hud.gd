# 對戰中的攻擊／閃避畫面（CanvasLayer 9：在觸控操作（10）底下，這樣失明時搖桿、攻擊鈕還看得到）。
# 照 Flutter client/lib/screens/game_screen.dart：
#   - 被攻擊：畫面邊緣紅框（DecoratedBox 4dp redAccent）+ 下方紅底「被攻擊了！放開搖桿閃躲」（_DodgeAlert）
#     + 蛇頭上方閃爍準星（_AttackCrosshairIndicator，Kenney Crosshair Pack CC0，300ms 淡入淡出）
#   - 命中橫幅：attack_banner.png 從右滑到中央、停留、往左滑出，共 2 秒（_AttackHitBanner）
#   - 失明：只看得到蛇頭和前方 2 格，其餘全黑（board.dart _visible() / _paintBlindMask()）。
#     3D 場景是斜俯視，所以把這 3 格（含角色高度）投影到螢幕、取凸包，shader 把凸包以外塗黑
#   - 一次性訊息 3 秒後消失（GameController._setBanner()）
# 所有動畫只跟著 game_session 給的狀態走；斷線凍結時 game_session 不推進計時，這裡的橫幅也跟著停（hold()）。
extends CanvasLayer

const DP := UiStyle.DP
const BLIND_SHADER := """
shader_type canvas_item;
uniform vec2 pts[12];
uniform int n = 0;
uniform vec2 rect_size;
uniform float feather = 24.0;
void fragment() {
	vec2 p = UV * rect_size;
	float d = 1e6;
	for (int i = 0; i < n; i++) {
		vec2 a = pts[i];
		vec2 b = pts[(i + 1) % n];
		vec2 e = b - a;
		float c = (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / max(length(e), 0.001);
		d = min(d, c);
	}
	// d > 0 = 在凸包裡面（離最近一邊的距離）
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - smoothstep(0.0, feather, d));
}
"""

@export var snake: Node3D
@export var camera: Camera3D

var _root: Control
var _blind: ColorRect
var _blind_mat: ShaderMaterial
var _border: Panel
var _alert: PanelContainer
var _crosshair: TextureRect
var _banner: TextureRect
var _msg_panel: PanelContainer
var _msg: Label

var _incoming := false
var _blind_on := false
var _blink := 0.0
var _banner_t := -1.0      # 命中橫幅動畫進度（秒），<0 = 沒在播
var _msg_left := 0.0
var _frozen := false

func _ready() -> void:
	layer = 9
	var theme := Theme.new()
	theme.default_font = UiFont.get_font()
	theme.default_font_size = int(16 * DP)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme
	add_child(_root)

	_blind = ColorRect.new()
	_blind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLIND_SHADER
	_blind_mat.shader = sh
	_blind.material = _blind_mat
	_blind.hide()
	_root.add_child(_blind)

	_border = Panel.new()
	_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color("ff5252")   # Flutter Colors.redAccent
	sb.set_border_width_all(int(4 * DP))
	_border.add_theme_stylebox_override("panel", sb)
	_border.hide()
	_root.add_child(_border)

	_crosshair = TextureRect.new()
	_crosshair.texture = _tex("res://assets/ui/crosshair.png")
	_crosshair.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crosshair.size = Vector2.ONE * 36 * DP
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.hide()
	_root.add_child(_crosshair)

	_alert = PanelContainer.new()
	_alert.add_theme_stylebox_override("panel", UiStyle.box(Color("d32f2f"), Color.TRANSPARENT, 0, 10, 12))   # Colors.red.shade700
	_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var al := UiStyle.label("被攻擊了！放開搖桿閃躲", 18, Color.WHITE)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert.add_child(al)
	_alert.hide()
	_root.add_child(_alert)

	_msg_panel = PanelContainer.new()
	_msg_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.87), Color.TRANSPARENT, 0, 8, 10))
	_msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg = UiStyle.label("", 15, Color.WHITE)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_panel.add_child(_msg)
	_msg_panel.hide()
	_root.add_child(_msg_panel)

	_banner = TextureRect.new()
	_banner.texture = _tex("res://assets/sprites/attack_banner.png")
	_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.hide()
	_root.add_child(_banner)

	get_viewport().size_changed.connect(_layout)
	_layout()

# 圖片只在 2D 用，轉成 ImageTexture（跟 lobby_screen.gd 一樣，避免匯入格式在某些平台畫成白色）
static func _tex(path: String) -> Texture2D:
	return ImageTexture.create_from_image((load(path) as Texture2D).get_image())

func _layout() -> void:
	var ui := get_viewport().get_visible_rect().size
	var inset := Vector4.ZERO
	var tc := get_parent().get_node_or_null("TouchControls")
	if tc and tc.has_method("safe_insets"):
		inset = tc.safe_insets()
	# 被攻擊提示：在底部操作列上方（Flutter bottom: 140）
	_alert.size = Vector2(ui.x - 2 * 16 * DP, 0)
	_alert.position = Vector2(16 * DP, ui.y - inset.w - 140 * DP - _alert.get_combined_minimum_size().y)
	# 一次性訊息：上方狀態列下面
	_msg_panel.size = Vector2(ui.x - 2 * 8 * DP, 0)
	_msg_panel.position = Vector2(8 * DP, inset.y + 44 * DP)
	# 橫幅：寬度 = 螢幕寬 - 左右 24dp，比例 1000:460
	var bw := ui.x - 2 * 24 * DP
	_banner.size = Vector2(bw, bw * 460.0 / 1000.0)
	_blind_mat.set_shader_parameter("rect_size", ui)

# ---------- 給 game_session 呼叫 ----------

func set_incoming(on: bool) -> void:
	_incoming = on
	_border.visible = on
	_alert.visible = on
	_crosshair.visible = on
	_blink = 0.0
	if on:
		_layout()

func set_blind(on: bool) -> void:
	_blind_on = on
	_blind.visible = on

func play_hit_banner() -> void:
	_banner_t = 0.0
	_banner.show()

func show_message(text: String, secs := 3.0) -> void:
	_msg.text = text
	_msg_left = secs
	_msg_panel.show()
	_layout()

# 斷線凍結：橫幅動畫停住（訊息照常倒數，只是提示）
func hold(on: bool) -> void:
	_frozen = on

func clear() -> void:
	set_incoming(false)
	set_blind(false)
	_banner_t = -1.0
	_banner.hide()
	_msg_panel.hide()

# ---------- 每幀 ----------

func _process(delta: float) -> void:
	var ui := get_viewport().get_visible_rect().size
	if _msg_left > 0.0:
		_msg_left -= delta
		if _msg_left <= 0.0:
			_msg_panel.hide()
	if _banner_t >= 0.0:
		if not _frozen:
			_banner_t += delta
		# 0~0.5 秒 右→中（easeOut）、0.5~1.5 停在中央、1.5~2 中→左（easeIn），同 Flutter TweenSequence 25/50/25
		var x: float
		if _banner_t < 0.5:
			x = 1.0 - ease(_banner_t / 0.5, 0.4)
		elif _banner_t < 1.5:
			x = 0.0
		else:
			x = -ease((_banner_t - 1.5) / 0.5, 2.4)
		_banner.position = Vector2((ui.x - _banner.size.x) / 2.0 + x * ui.x, (ui.y - _banner.size.y) / 2.0)
		if _banner_t >= 2.0:
			_banner_t = -1.0
			_banner.hide()
	if _incoming:
		_blink += delta
		_crosshair.modulate.a = pingpong(_blink / 0.3, 1.0)   # 300ms 淡入淡出
		if snake and camera:
			var head: Vector3 = snake.position
			var p := camera.unproject_position(head + Vector3(0, 1.4, 0))
			_crosshair.position = p - _crosshair.size / 2.0
	if _blind_on and snake and camera:
		_update_blind()

# 看得到的範圍：蛇頭那一格 + 前方 2 格（Flutter _visible()），地面到角色頭頂的高度都算，投影到螢幕取凸包
func _update_blind() -> void:
	var d: Vector2i = snake.dir
	var fwd := Vector3(d.x, 0, d.y)
	var side := Vector3(-d.y, 0, d.x)
	var head: Vector3 = snake.position
	var m := 0.1   # 多露一點邊，不要剛好切在格線上
	var pts := PackedVector2Array()
	for along in [-0.5 - m, 2.5 + m]:
		for across in [-0.5 - m, 0.5 + m]:
			for h in [0.0, 1.6]:
				var w: Vector3 = head + fwd * along + side * across + Vector3(0, h, 0)
				if camera.is_position_behind(w):
					continue
				pts.append(camera.unproject_position(w))
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)   # convex_hull 會把第一點重複放在最後
	# shader 用「每一邊的左側 = 裡面」，順序要是正面積
	var area := 0.0
	for i in hull.size():
		var a := hull[i]
		var b := hull[(i + 1) % hull.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		hull.reverse()
	var arr: Array[Vector2] = []
	for i in mini(hull.size(), 12):
		arr.append(hull[i])
	while arr.size() < 12:
		arr.append(Vector2.ZERO)
	_blind_mat.set_shader_parameter("pts", arr)
	_blind_mat.set_shader_parameter("n", mini(hull.size(), 12))
