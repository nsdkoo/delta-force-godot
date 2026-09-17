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

## 贴图四周补的透明边（像素）。描边宽度 1.9 texel，留 4 像素足够
const PAD := 4

const OUTLINE_SHADER := "res://assets/shaders/outline.gdshader"

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
	if not ResourceLoader.exists(path):
		push_warning("AssetDB: 缺少素材 " + path)
		return null
	var t := load(path) as Texture2D
	if t == null:
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
	var key: String = GameConfig.OPERATORS[unit.op_class]["sprite"]
	if unit.is_reloading and tex.has("op_soldier_reload"):
		return tex["op_soldier_reload"]
	return tex.get("op_" + key, null)

func operator_texture_for(op_class: int) -> Texture2D:
	return tex.get("op_" + GameConfig.OPERATORS[op_class]["sprite"], null)

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

func fx(name: String) -> Texture2D:
	return tex.get("fx_" + name, null)

## 干员贴图的世界显示宽度（像素）
const OPERATOR_DRAW_WIDTH := 52.0
## 载具贴图相对碰撞半径的显示倍率
const VEHICLE_DRAW_SCALE := 2.05
