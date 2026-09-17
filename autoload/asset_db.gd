extends Node
## ============================================================================
## AssetDB · 素材库
## ----------------------------------------------------------------------------
## 集中加载 Kenney（CC0 1.0 Universal）素材，提供语义化取用接口。
## 素材均为"单朝向朝右/朝上"的俯视图，靠旋转适配任意朝向。
## ============================================================================

const DIR_OP := "res://assets/operators/"
const DIR_VEH := "res://assets/vehicles/"
const DIR_TILE := "res://assets/tiles/"
const DIR_FX := "res://assets/fx/"

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
	return load(path) as Texture2D

# ---------------------------------------------------------------- 取用
func operator_texture(unit) -> Texture2D:
	var key: String = GameConfig.OPERATORS[unit.op_class]["sprite"]
	if unit.is_reloading and tex.has("op_soldier_reload"):
		return tex["op_soldier_reload"]
	return tex.get("op_" + key, null)

func operator_texture_for(op_class: int) -> Texture2D:
	return tex.get("op_" + GameConfig.OPERATORS[op_class]["sprite"], null)

func vehicle_body(kind: String, team: int) -> Texture2D:
	return tex.get("veh_%s_%d_body" % [kind, team], null)

func vehicle_turret(kind: String, team: int) -> Texture2D:
	return tex.get("veh_%s_%d_turret" % [kind, team], null)

func tile(name: String) -> Texture2D:
	return tex.get("tile_" + name, null)

func fx(name: String) -> Texture2D:
	return tex.get("fx_" + name, null)

## 干员贴图的世界显示宽度（像素）
const OPERATOR_DRAW_WIDTH := 46.0
## 载具贴图相对碰撞半径的显示倍率
const VEHICLE_DRAW_SCALE := 2.05
