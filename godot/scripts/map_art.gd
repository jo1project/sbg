# 地圖的微縮模型美術：地板方塊、3D 柱子/箱子、2D 怪物立繪、火把。
# 素材都是 client/assets/dungeon/ 複製過來的 0x72 DungeonTilesetII 單張 PNG（不是 sprite sheet，
# Flutter 那邊也是整張直接畫），這裡需要切圖的只有 column/crate，切法見 CROP_*。
# 單位換算：素材 16px = 世界 1 單位（= 1 格）。
extends RefCounted

const DIR := "res://assets/dungeon/"
const PX := 1.0 / 16.0
const IDLE_FPS := 1000.0 / 325.0   # Flutter 怪物待機動畫跟移動 tick 同步（325ms/格），這裡用同樣節奏
const FLAME_FPS := 8.0

# 切圖區塊（素材像素座標，Rect2i(x, y, w, h)）
const CROP_CRATE_TOP := Rect2i(1, 3, 14, 9)     # 箱蓋（俯視那塊直條木板）
const CROP_CRATE_SIDE := Rect2i(1, 12, 14, 11)  # 箱子正面（橘色條 + 兩個把手孔）
const CROP_COLUMN_TOP := Rect2i(1, 1, 14, 4)    # 柱頂淺色石面
const CROP_COLUMN_CAP := Rect2i(1, 3, 14, 5)    # 柱頂外緣側面
const CROP_COLUMN_SHAFT := Rect2i(2, 8, 12, 18) # 柱身
const CROP_COLUMN_BASE := Rect2i(1, 27, 14, 4)  # 柱底座

const TORCH_COLOR := Color(1.0, 0.6, 0.25)
const TORCH_FLICKER := preload("res://scripts/torch_flicker.gd")
const MapLoaderScript := preload("res://scripts/map_loader.gd")
const COLUMN_HEIGHT := 2.0          # 柱子總高，柱頂火把放這個高度

var _floor_meshes := {}     # variant(1~8) -> Mesh
var _crate_mesh: Mesh
var _column_parts: Array    # [[Mesh, 中心高度], ...]
var _monster_frames := {}   # species -> SpriteFrames（null = 素材缺）
var _flame_frames: SpriteFrames
var _post_mesh: Mesh
var _cup_mesh: Mesh

func _init() -> void:
	# 地板側面：牆磚圖壓暗，當作微縮模型被切開的石層斷面
	var side := _mat(_tex("wall_left.png"), Color(0.8, 0.72, 0.7))
	for v in range(1, 9):
		_floor_meshes[v] = box_mesh(Vector3(1, 1, 1), side, _mat(_tex("floor_%d.png" % v)))

	var crate := _img("crate.png")
	var crate_side := _mat(_crop(crate, CROP_CRATE_SIDE))
	_crate_mesh = box_mesh(Vector3(14, 11, 14) * PX, crate_side, _mat(_crop(crate, CROP_CRATE_TOP)))

	var col := _img("column.png")
	var shaft := _mat(_crop(col, CROP_COLUMN_SHAFT))
	var cap := _mat(_crop(col, CROP_COLUMN_CAP))
	# 底座 0.25 + 柱身 1.4375 + 柱頂 0.3125 = 2.0；柱身比素材的 18px 稍微拉長到 23px
	_column_parts = [
		[box_mesh(Vector3(14, 4, 14) * PX, _mat(_crop(col, CROP_COLUMN_BASE)), shaft), 2 * PX],
		[box_mesh(Vector3(12, 23, 12) * PX, shaft, shaft), (4 + 11.5) * PX],
		[box_mesh(Vector3(14, 5, 14) * PX, cap, _mat(_crop(col, CROP_COLUMN_TOP))), (27 + 2.5) * PX],
	]

	_flame_frames = SpriteFrames.new()
	_flame_frames.set_animation_speed("default", FLAME_FPS)
	for i in 4:
		_flame_frames.add_frame("default", load("res://assets/generated/torch_flame_f%d.png" % i))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.26, 0.15)   # Flutter 火把壁架的 0xFF6B4226
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 28, 2) * PX
	bm.material = wood
	_post_mesh = bm
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.12, 0.12)
	var cm := BoxMesh.new()
	cm.size = Vector3(4, 2, 4) * PX
	cm.material = iron
	_cup_mesh = cm

# ---------- 素材 ----------
func _tex(file: String) -> Texture2D:
	return load(DIR + file)

func _img(file: String) -> Image:
	return _tex(file).get_image()

func _crop(img: Image, r: Rect2i) -> Texture2D:
	return ImageTexture.create_from_image(img.get_region(r))

func _mat(tex: Texture2D, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m

# 以原點為中心的方塊，側面四面共用 side（每面 UV 0~1 貼滿，圖的上緣朝上），頂面 top、底面用 side。
# BoxMesh 內建 UV 是 3x2 圖集排列，沒辦法各面貼不同圖，所以自己組。
static func box_mesh(size: Vector3, side: Material, top: Material) -> ArrayMesh:
	var h := size / 2.0
	var mesh := ArrayMesh.new()
	# 每面依「從外面看過去」的 左上、右上、右下、左下 排列（Godot 正面為順時針）
	var sides := [
		[Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3.BACK],
		[Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3.FORWARD],
		[Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3.RIGHT],
		[Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3.LEFT],
		[Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3.DOWN],
	]
	var tops := [
		[Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3.UP],
	]
	for pair in [[sides, side], [tops, top]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for q in pair[0]:
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(q[4])
				st.set_uv(uv[i])
				st.add_vertex(q[i])
		st.set_material(pair[1])
		st.commit(mesh)
	return mesh

# ---------- 節點 ----------
# 地板方塊：上表面 y=0、厚 1；繞 Y 隨機轉 90° 倍數，減少地磚重複感（依格座標決定，每次重建都一樣）
func make_floor(c: Vector2i) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _floor_meshes[MapLoaderScript.floor_variant(c)]
	mi.rotation.y = posmod(hash(c), 4) * PI / 2.0
	return mi

func make_crate() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _crate_mesh
	mi.position.y = 11 * PX / 2.0
	return _wrap(mi)

func make_column() -> Node3D:
	var root := Node3D.new()
	for p in _column_parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position.y = p[1]
		root.add_child(mi)
	return root


# 怪物：2D 立繪 + Y 軸 billboard；圖片底緣對齊地板（素材每幀腳都踩在最底一列像素）
# 像素 1:1（16px = 1 格），big 怪物素材本身就是 32px 寬，自然佔兩格，不另外縮放
func make_monster(species: String) -> Node3D:
	if not _monster_frames.has(species):
		_monster_frames[species] = _load_idle(species)
	var frames: SpriteFrames = _monster_frames[species]
	if frames == null:
		push_warning("MapArt: 找不到 %s 的待機動畫素材，用膠囊代替" % species)
		var mi := MeshInstance3D.new()
		mi.mesh = CapsuleMesh.new()
		mi.position.y = 1.0
		return _wrap(mi)
	var s := AnimatedSprite3D.new()
	s.sprite_frames = frames
	s.pixel_size = PX
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	s.position.y = frames.get_frame_texture("default", 0).get_height() * PX / 2.0
	s.autoplay = "default"
	return _wrap(s)

func _load_idle(species: String) -> SpriteFrames:
	var f := SpriteFrames.new()
	f.set_animation_speed("default", IDLE_FPS)
	for i in 4:
		var path := DIR + "%s_idle_anim_f%d.png" % [species, i]
		if not ResourceLoader.exists(path):
			return null
		f.add_frame("default", load(path))
	return f

# 火把：像素火焰 billboard + 暖橘 OmniLight3D（輕微閃爍）。with_post=true 時底下加一根木立柱，
# 立柱從地板切面旁邊（虛空裡）往上長，頂端高出地面；false 時直接放在原點（例如柱頂）。
func make_torch(with_post: bool, seed_value: int) -> Node3D:
	var root := Node3D.new()
	var top := 0.0
	if with_post:
		var post := MeshInstance3D.new()
		post.mesh = _post_mesh
		top = 0.75
		post.position.y = top - _post_mesh.size.y / 2.0
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(post)
	var cup := MeshInstance3D.new()
	cup.mesh = _cup_mesh
	cup.position.y = top + PX
	cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cup)

	var flame := AnimatedSprite3D.new()
	flame.sprite_frames = _flame_frames
	flame.pixel_size = PX * 0.75
	flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	flame.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	flame.shaded = false
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fh := _flame_frames.get_frame_texture("default", 0).get_height() * flame.pixel_size
	flame.position.y = top + 2 * PX + fh / 2.0
	flame.autoplay = "default"
	root.add_child(flame)

	var light := OmniLight3D.new()
	light.light_color = TORCH_COLOR
	light.light_energy = 2.6
	light.omni_range = 7.0
	light.shadow_enabled = true
	light.position.y = top + 2 * PX + fh * 0.6
	light.set_script(TORCH_FLICKER)
	light.set("noise_seed", seed_value)
	root.add_child(light)
	return root

func _wrap(child: Node3D) -> Node3D:
	var root := Node3D.new()
	root.add_child(child)
	return root

