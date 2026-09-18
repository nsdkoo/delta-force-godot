extends Node
## ============================================================================
## AssetDB · 素材库
## ----------------------------------------------------------------------------
## 集中加载 Kenney（CC0 1.0 Universal）素材，提供语义化取用接口。
## 素材均为"单朝向朝右/朝上"的俯视图，靠旋转适配任意朝向。
##
## 这里还负责两件和"卡通描边风"直接相关的事：
##   1. 贴图统一补边（PAD）—— 描边只在精灵四边形内采样，紧裁贴图的外轮廓
##      会被裁掉。补边之后所有实体都能画出完整一圈轮廓。
##   2. 提供共享的描边材质与地表分级材质 —— 归一化到 TEXTURE_PIXEL_SIZE 的
##      描边宽度让一份材质能套在所有尺寸的贴图上，不必每个精灵建一份。
##
## 补边会改变贴图尺寸，所以任何"按贴图宽度算缩放"的地方都必须改用
## logical_width() / logical_height()，否则内容会整体缩小一圈。
## ============================================================================

const DIR_OP := "res://assets/operators/"
const DIR_VEH := "res://assets/vehicles/"
const DIR_TILE := "res://assets/tiles/"
const DIR_FX := "res://assets/fx/"
const DIR_BLD := "res://assets/buildings/"
const DIR_DECOR := "res://assets/decor_kr/"

## 贴图四周补的透明边（像素）。描边宽度 1.9 texel，留 4 像素足够
const PAD := 4

const OUTLINE_SHADER := "res://assets/shaders/outline.gdshader"

## 军事风建筑贴图：优先 Kenney 工事/箱体，告别 Tiny Swords 中世纪塔楼
## （城堡/蓝瓦民居和沥青路混在一起很怪）
const BUILDING_VARIANTS := {
	"house": ["crate_metal", "crate_wood", "fort_block"],
	"warehouse": ["fort_block", "fort_bunker", "crate_metal"],
	"block": ["fort_block", "fort_bunker"],
	"tower": ["fort_bunker", "fort_turret", "fort_gun"],
	"bunker": ["fort_bunker", "fort_gun"],
	"wall": ["barricade_metal", "fence_yellow"],
	"fence": ["fence_red", "wire_straight"],
}
const DECOR_NAMES := [
	"tree1", "tree2", "tree3", "tree4",
	"bush1", "bush2", "bush3", "bush4",
	"rock1", "rock2", "rock3", "rock4",
]

# ---------------------------------------------------------------- Kenney 卡通包
## Top-down Tanks Redux + Tower Defense（均为 CC0 1.0，可商用、免署名）。
## 这两包的价值在于：素材本身就是"平涂 + 深色描边"的卡通风格，
## 而且载具/弹丸直接提供 *_outline 版本 —— 轮廓是画进去的，比着色器描边干净。
const DIR_KTILE := "res://assets/kenney/tiles/"
const DIR_KFX := "res://assets/kenney/fx/"
const DIR_KVEH := "res://assets/kenney/vehicles/"

const K_TILES := [
	"tree_green_large", "tree_green_small", "tree_green_leaf",
	"tree_brown_large", "tree_brown_small",
	"bush_large", "bush_small", "rock_large", "rock_small",
	"crystal_ball", "crystal_star",
	"barrel_rust", "barrel_green", "barrel_red", "barrel_black",
	"crate_wood", "crate_metal", "barricade_wood", "barricade_metal",
	"sandbag_beige", "sandbag_brown", "wire_straight", "wire_crooked",
	"fence_red", "fence_yellow",
	"oil_large", "oil_small", "tracks_small", "tracks_large", "tracks_double",
	# 工事用的塔与炮（来自 Tower Defense 包）
	"fort_bunker", "fort_gun", "fort_block", "fort_turret",
	"air_plane", "flame", "marker_dot",
]
const K_FX := [
	"exp_1", "exp_2", "exp_3", "exp_4", "exp_5",
	"expsmoke_1", "expsmoke_2", "expsmoke_3", "expsmoke_4", "expsmoke_5",
	"shot_large", "shot_orange", "shot_red", "shot_thin",
]
const K_HULLS := ["hull_blue", "hull_sand", "hull_red", "hull_dark", "hull_darklarge", "hull_bigred"]
const K_TURRETS := [
	"turret_blue_1", "turret_blue_2", "turret_blue_3",
	"turret_sand_1", "turret_sand_2", "turret_sand_3",
	"turret_red_1", "turret_red_2", "turret_red_3",
	"turret_dark_1", "turret_dark_2", "turret_dark_3",
]

## 干员贴图（按 GameConfig.OPERATORS[x].sprite 取用）
const OP_TEXTURES := [
	"soldier_rifle", "soldier_lmg", "soldier_reload",
	"operator_blue", "operator_survivor", "operator_agent", "operator_green",
]
## 载具贴图：kind -> team -> {body, turret}
const VEH_TEXTURES := {
	"tank": {
		0: {"body": "tank_body_sand", "turret": "tank_turret_sand"},
		1: {"body": "tank_body_dark", "turret": "tank_turret_dark"},
	},
	"apc": {
		0: {"body": "apc_body_blue", "turret": "apc_turret_blue"},
		1: {"body": "apc_body_red", "turret": "apc_turret_red"},
	},
}
const TILE_TEXTURES := [
	"sand_1", "sand_2", "sandbag_beige", "sandbag_brown", "crate_wood", "crate_metal",
	"barricade", "wire", "tree_dry", "barrel_rust", "barrel_green", "tracks", "oil_spill",
]
const FX_TEXTURES := [
	"muzzle", "muzzle_2", "smoke", "smoke_dark", "fire", "flame", "spark", "scorch", "trace",
]

var tex: Dictionary = {}
var _outline_mat: ShaderMaterial = null

func _ready() -> void:
	_load_dir(DIR_OP, OP_TEXTURES, "op_")
	_load_dir(DIR_TILE, TILE_TEXTURES, "tile_")
	_load_dir(DIR_FX, FX_TEXTURES, "fx_")
	_load_dir(DIR_KTILE, K_TILES, "kt_")
	_load_dir(DIR_KFX, K_FX, "kf_")
	_load_dir(DIR_DECOR, DECOR_NAMES, "dc_")
	# Tiny Swords 建筑仅作兜底（当前默认走 Kenney 军事贴图）
	_load_dir(DIR_BLD, [
		"house", "house_b", "warehouse", "block", "tower", "bunker", "wall", "fence",
		"castle", "house_warm", "house_cool", "house_sand",
	], "bld_")
	# 地形砖：Ground 区域平铺用（Tower Defense 包）
	for n in ["ground_grass", "ground_grass_b", "ground_grass_c", "ground_dirt",
			"ground_dirt_b", "ground_dirt_c", "ground_sand", "ground_sand_b",
			"ground_stone", "ground_stone_b", "ground_stone_c",
			"patch_grass_round", "decal_crater", "decal_scatter"]:
		tex["gt_" + n] = _load("res://assets/kenney/ground/" + n + ".png")
	for n in K_HULLS:
		tex["kh_" + n] = _load(DIR_KVEH + n + ".png")
	for n in K_TURRETS:
		tex["kv_" + n] = _load(DIR_KVEH + n + ".png")
	# 载具
	for kind in VEH_TEXTURES:
		for team in VEH_TEXTURES[kind]:
			var pair: Dictionary = VEH_TEXTURES[kind][team]
			tex["veh_%s_%d_body" % [kind, team]] = _load(DIR_VEH + pair["body"] + ".png")
			tex["veh_%s_%d_turret" % [kind, team]] = _load(DIR_VEH + pair["turret"] + ".png")

func _load_dir(dir: String, names: Array, prefix: String) -> void:
	for n in names:
		tex[prefix + n] = _load(dir + n + ".png")

func _load(path: String) -> Texture2D:
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		# 新丢进工程、还没被编辑器导入的 PNG：直接按文件读，避免 ResourceLoader 报缺
		var abs_path := ProjectSettings.globalize_path(path)
		var img := Image.load_from_file(abs_path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	if t == null:
		push_warning("AssetDB: 缺少素材 " + path)
		return null
	return _padded(t)

# ---------------------------------------------------------------- 材质
## 共享的描边材质。所有需要"抠出来"的实体都挂这一份
func outline_material() -> ShaderMaterial:
	if _outline_mat == null:
		_outline_mat = _make_material(OUTLINE_SHADER)
	return _outline_mat

func _make_material(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if ResourceLoader.exists(path):
		m.shader = load(path)
	else:
		push_warning("AssetDB: 缺少着色器 " + path)
	return m

## 给一个 CanvasItem 挂上描边材质（已经是画布项的子节点就直接用）
func apply_outline(ci: CanvasItem) -> void:
	if ci != null:
		ci.material = outline_material()

# ---------------------------------------------------------------- 补边
## 四周补一圈透明边，给描边留出绘制空间
func _padded(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		# 压缩贴图取不出逐像素数据，直接退回原图（描边会缺一条，但不会崩）
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create_empty(w + PAD * 2, h + PAD * 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(PAD, PAD))
	return ImageTexture.create_from_image(out)

## 补边前的宽度：所有"按贴图宽度算缩放"的地方都要用这个
func logical_width(t: Texture2D) -> float:
	return float(t.get_width() - PAD * 2) if t != null else 1.0

func logical_height(t: Texture2D) -> float:
	return float(t.get_height() - PAD * 2) if t != null else 1.0

# ---------------------------------------------------------------- 取用
func operator_texture(unit) -> Texture2D:
	var key: String = GameConfig.op(unit.op_id)["sprite"]
	if unit.is_reloading and tex.has("op_soldier_reload"):
		return tex["op_soldier_reload"]
	return tex.get("op_" + key, null)

func operator_texture_for(op_id: String) -> Texture2D:
	return tex.get("op_" + GameConfig.op(op_id)["sprite"], null)

## 载具贴图：kind 可以是 "tank" / "apc" / "aa" / "heli" / "car"；
## 缺图时退回同阵营的通用车体，保证新载具不会因为没素材而隐身。
func vehicle_body(kind: String, team: int) -> Texture2D:
	var k := "veh_%s_%d_body" % [kind, team]
	if tex.has(k) and tex[k] != null:
		return tex[k]
	return tex.get("veh_%s_%d_body" % ["tank" if kind != "apc" else "apc", team], null)

func vehicle_turret(kind: String, team: int) -> Texture2D:
	var k := "veh_%s_%d_turret" % [kind, team]
	if tex.has(k) and tex[k] != null:
		return tex[k]
	return tex.get("veh_%s_%d_turret" % ["tank" if kind != "apc" else "apc", team], null)

func tile(name: String) -> Texture2D:
	return tex.get("tile_" + name, null)

# ---------------------------------------------------------------- Kenney 取用
## 地形砖（Kenney Tower Defense，CC0）。draw_texture_rect 要平铺依赖
## 画布项的 TEXTURE_REPEAT_ENABLED，调用方需要自己开
func gtile(name: String) -> Texture2D:
	return tex.get("gt_" + name, null)

func ktile(name: String) -> Texture2D:
	return tex.get("kt_" + name, null)

## Tiny Swords 装饰（树/灌木/石）
func decor(name: String) -> Texture2D:
	return tex.get("dc_" + name, null)

## 建筑贴图：按类型轮换变体。军事包走 kenney/tiles，旧 Tiny Swords 作兜底
func building(type: String, index: int = 0) -> Texture2D:
	var variants: Array = BUILDING_VARIANTS.get(type, BUILDING_VARIANTS["house"])
	var name: String = variants[index % variants.size()]
	var t: Texture2D = tex.get("kt_" + name, null)
	if t == null:
		t = tex.get("bld_" + name, null)
	if t == null:
		t = tex.get("kt_fort_block", null)
	if t == null:
		t = tex.get("bld_house", null)
	return t

func kfx(name: String) -> Texture2D:
	return tex.get("kf_" + name, null)

func hull(name: String) -> Texture2D:
	return tex.get("kh_" + name, null)

func turret(name: String) -> Texture2D:
	return tex.get("kv_" + name, null)

## 爆炸序列的一帧。step 0..1 按进度取帧，用于把 5 张静帧连成一次爆炸
func blast_frame(k: float, smoke: bool = false) -> Texture2D:
	var idx := clampi(int(floor(clampf(k, 0.0, 1.0) * 5.0)), 0, 4)
	return kfx(("expsmoke_" if smoke else "exp_") + str(idx + 1))

func fx(name: String) -> Texture2D:
	return tex.get("fx_" + name, null)

## Tiny Swords 建筑已自带描边；持枪干员用 Kenney，需要着色器描边
const OPERATOR_HAS_BAKED_OUTLINE := false
## 干员贴图的世界显示宽度（像素）
const OPERATOR_DRAW_WIDTH := 52.0
## 载具贴图相对碰撞半径的显示倍率
const VEHICLE_DRAW_SCALE := 2.05
