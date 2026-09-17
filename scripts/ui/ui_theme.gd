extends RefCounted
class_name UiTheme
## ============================================================================
## UiTheme · 卡通界面主题
## ----------------------------------------------------------------------------
## 面板与按钮全部做成"木板牌子 + 金线"：不透明暖木底、亮金描边、大圆角、
## 厚边距。这是卡通塔防那一类游戏的通用界面语言 —— 界面本身要像游戏里的
## 一件道具，而不是浮在画面上的系统控件。
##
## 用 Theme 资源下发而不是逐个控件覆盖样式：
## 选举页 / 部署页 / 结算页加起来有几十个 Label 与 Button，逐个覆盖会写满
## 每个按钮各四份样式（normal / hover / pressed / disabled），而且以后加控件
## 一定会漏。挂一份 Theme 到面板根节点，所有子控件自动继承。
## ============================================================================

## 中文必须用 SystemFont：Godot 内置字体不含 CJK，直接用会显示成方块
static func cjk_font(bold: bool = false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	if bold:
		f.font_weight = 700
	return f

static func _btn(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb

static func _panel(alpha: float = 0.96) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.UI_WOOD.r, Palette.UI_WOOD.g, Palette.UI_WOOD.b, alpha)
	sb.border_color = Color(Palette.UI_GOLD.r, Palette.UI_GOLD.g, Palette.UI_GOLD.b, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	return sb

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = cjk_font()
	t.default_font_size = 15

	# ---- 面板 ----
	t.set_stylebox("panel", "Panel", _panel())
	t.set_stylebox("panel", "PanelContainer", _panel())

	# ---- 按钮：木牌 + 金边，四态各一份 ----
	var base := Palette.UI_WOOD_LIGHT
	t.set_stylebox("normal", "Button", _btn(base, Palette.UI_GOLD))
	t.set_stylebox("hover", "Button", _btn(base.lightened(0.16), Palette.UI_GOLD_LIGHT))
	t.set_stylebox("pressed", "Button", _btn(base.darkened(0.22), Palette.UI_GOLD))
	t.set_stylebox("disabled", "Button", _btn(Palette.UI_WOOD_DARK, Color(Palette.UI_GOLD.r, Palette.UI_GOLD.g, Palette.UI_GOLD.b, 0.3)))
	t.set_stylebox("focus", "Button", _btn(Color(0, 0, 0, 0), Palette.UI_GOLD_LIGHT))
	t.set_color("font_color", "Button", Palette.UI_TEXT)
	t.set_color("font_hover_color", "Button", Palette.UI_GOLD_LIGHT)
	t.set_color("font_pressed_color", "Button", Palette.UI_GOLD_LIGHT)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.48, 0.4))
	t.set_font("font", "Button", cjk_font(true))
	t.set_font_size("font_size", "Button", 15)

	# ---- 文本 ----
	t.set_color("font_color", "Label", Palette.UI_TEXT)
	t.set_font("font", "Label", cjk_font())
	t.set_font_size("font_size", "Label", 15)

	return t
