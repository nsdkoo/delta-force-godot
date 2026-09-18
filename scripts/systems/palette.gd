extends RefCounted
class_name Palette
## ============================================================================
## Palette · 卡通描边风调色板
## ----------------------------------------------------------------------------
## 目标风格：厚描边 + 高饱和平涂 + 硬投影（《王国保卫战》那一类 2D 卡通塔防的
## 观感）。和之前那版"写实军事俯视"的区别不在素材，在这三件事：
##
##   1. 明暗靠色块断，不靠渐变 —— 同一个面只用一个颜色，靠相邻面拉大明度差
##   2. 所有实体都有一圈深色外轮廓，把物体从背景里"抠"出来
##   3. 投影是硬的（高不透明、无模糊），不是柔和的接触阴影
##
## 集中定义在这里的一个好处：改风格只需要改这一份，不用满项目找颜色字面量。
## ============================================================================

# ---------------------------------------------------------------- 描边
const OUTLINE := Color("#241a12")          ## 实体外轮廓（暖调近黑，纯黑会显脏）
const OUTLINE_SOFT := Color("#3b2a1c")     ## 内部结构线

# ---------------------------------------------------------------- 地表
const GRASS := Color("#6fae3a")
const GRASS_DARK := Color("#518a29")
const GRASS_LIGHT := Color("#8fca50")
const DIRT := Color("#c8a05a")
const DIRT_DARK := Color("#a2793c")
const SAND := Color("#e3c98a")
const SAND_DARK := Color("#c9a961")
const ROAD := Color("#a87a3e")
const ROAD_DARK := Color("#8a6330")
const ROCK := Color("#9aa3ad")
const ROCK_DARK := Color("#6c7681")

# ---------------------------------------------------------------- 建筑
## 每种建筑一套三面色：顶面 / 南立面（受光）/ 东立面（背光）。
## 南立面比顶面暗一档、东立面再暗一档 —— 明度差拉到 20% 以上才有卡通体积感。
const BUILD := {
	"house": {
		"top": Color("#e8663f"), "s": Color("#c14a2c"), "e": Color("#9b3a22"),
	},
	"block": {
		"top": Color("#8fb3d4"), "s": Color("#6e93b8"), "e": Color("#547a9e"),
	},
	"tower": {
		"top": Color("#c9d3dd"), "s": Color("#a3aeba"), "e": Color("#828d99"),
	},
	"warehouse": {
		"top": Color("#cfae4e"), "s": Color("#a98c3a"), "e": Color("#87702c"),
	},
	"wall": {
		"top": Color("#bda671"), "s": Color("#9a8449"), "e": Color("#7c6a3a"),
	},
	"fence": {
		"top": Color("#8a6238"), "s": Color("#6d4c2b"), "e": Color("#553a21"),
	},
	"bunker": {
		"top": Color("#9aa878"), "s": Color("#7a8a5e"), "e": Color("#61704a"),
	},
}

## 屋顶装饰色（烟囱、窗、门）
const ROOF_TRIM := Color("#4a3423")
const WINDOW := Color("#ffe9a8")
const WINDOW_OFF := Color("#6b7f96")

# ---------------------------------------------------------------- 记号（工事 / 标记）
const MARK_ATTACK := Color("#ff4d3d")
const MARK_DEFEND := Color("#3d9bff")
const MARK_ADVANCE := Color("#ffd24a")
const MARK_WARN := Color("#ff9a3a")
const MARK_GOLD := Color("#ffc42e")

# ---------------------------------------------------------------- UI
## 面板：暖木牌 + 金边。卡通塔防的界面几乎都是"木头/石头牌子 + 金线"
const UI_WOOD := Color("#3a2a1c")
const UI_WOOD_LIGHT := Color("#5b452e")
const UI_WOOD_DARK := Color("#241a12")
const UI_GOLD := Color("#e0a83c")
const UI_GOLD_LIGHT := Color("#ffd97a")
const UI_PARCHMENT := Color("#f3e4c4")
const UI_TEXT := Color("#f6ecd8")
const UI_TEXT_DIM := Color("#b9a68a")

## 面板样式（统一边框/圆角/内边距）
static func panel_style(alpha: float = 0.95, border: float = 2.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI_WOOD.r, UI_WOOD.g, UI_WOOD.b, alpha)
	sb.border_color = Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.85)
	sb.set_border_width_all(int(border))
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	# 顶部一条高光，做出"木牌受光"的错觉
	sb.border_width_top = int(border) + 1
	return sb

## 按钮样式：亮木色 + 粗金边 + 圆角
static func button_style(bg: Color, border_col: Color = UI_GOLD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
