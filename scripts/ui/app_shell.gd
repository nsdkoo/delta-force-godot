extends CanvasLayer
## ============================================================================
## AppShell · 产品外壳（主菜单 / 设置 / 暂停）
## ----------------------------------------------------------------------------
## 参照开源同类游戏的做法：主菜单不是一块挡住画面的黑幕，而是**压在实时战场上
## 的一层半透明 UI** —— 背后有部队在推进、有枪声，玩家还没开始就已经"在战场里"。
## 这比一张静态背景图强得多，成本却几乎为零（战场本来就在跑）。
##
## 三个页面共用同一套构建方式，只在这里集中一次：
##   左对齐的按钮列 + 右侧信息栏 + 底部版本角标，
##   底层同一份 UiTheme（木牌金边）与 Palette（卡通配色）。
##
## 暂停用 AppState 驱动而不是各页面自己 get_tree().paused：
## "什么时候时间该停"只有一处判断，避免出现"设置页里战场还在打"这种事。
## ============================================================================

const MENU_LAYER := 60          ## 必须高于 HUD 的 40 与结算页的 20

var root: Control
var _page: String = ""
var _pan_t: float = 0.0

func _ready() -> void:
	# 暂停时要能点按钮，所以这层永远处理输入
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = MENU_LAYER
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	EventBus.app_state_changed.connect(_on_state)
	visible = false

func _on_state(state: int) -> void:
	match state:
		AppState.State.MAIN_MENU:
			show_main_menu()
		AppState.State.SETTINGS:
			show_settings()
		AppState.State.PAUSED:
			show_pause()
		AppState.State.PLAYING, AppState.State.BRIEFING:
			clear()

func clear() -> void:
	_page = ""
	visible = false
	for c in root.get_children():
		c.queue_free()

func _fresh(title: String, subtitle: String) -> Control:
	clear()
	visible = true
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(box)
	# 左侧压暗：让按钮列从战场背景里"跳"出来，同时不遮死画面
	var veil := ColorRect.new()
	veil.color = Color(0.06, 0.04, 0.03, 0.62)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(veil)
	var bar := ColorRect.new()
	bar.color = Color(Palette.UI_WOOD.r, Palette.UI_WOOD.g, Palette.UI_WOOD.b, 0.88)
	bar.position = Vector2.ZERO
	bar.size = Vector2(560, 2000)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	var edge := ColorRect.new()
	edge.color = Color(Palette.UI_GOLD.r, Palette.UI_GOLD.g, Palette.UI_GOLD.b, 0.75)
	edge.position = Vector2(560, 0)
	edge.size = Vector2(3, 2000)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(edge)

	var t := Label.new()
	t.text = title
	t.position = Vector2(56, 96)
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", Palette.UI_GOLD_LIGHT)
	box.add_child(t)
	var s := Label.new()
	s.text = subtitle
	s.position = Vector2(60, 158)
	s.add_theme_font_size_override("font_size", 15)
	s.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	box.add_child(s)
	return box

## 一条按钮列项。返回按钮本身，调用方接 pressed
func _menu_button(box: Control, text: String, y: float, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(430, 54)
	b.position = Vector2(56, y)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var bg: Color = Palette.UI_GOLD.darkened(0.35) if primary else Palette.UI_WOOD_LIGHT
	b.add_theme_stylebox_override("normal", Palette.button_style(bg))
	b.add_theme_stylebox_override("hover", Palette.button_style(bg.lightened(0.18), Palette.UI_GOLD_LIGHT))
	b.add_theme_stylebox_override("pressed", Palette.button_style(bg.darkened(0.25)))
	b.add_theme_color_override("font_color", Palette.UI_TEXT)
	b.add_theme_font_size_override("font_size", 19)
	box.add_child(b)
	return b

## 底部版本角标。产品必须能一眼看出跑的是哪个版本
func _stamp(box: Control) -> void:
	var l := Label.new()
	l.text = "v%s · %s · 仅本地运行" % [AppState.VERSION, AppState.BUILD_STAGE]
	l.position = Vector2(60, 640)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	box.add_child(l)

# ============================================================ 主菜单
func show_main_menu() -> void:
	if _page == "main":
		return
	_page = "main"
	var box := _fresh("胜者为王", "三角洲行动 · 全面战场 · 20 vs 20 攻防")
	var b1 := _menu_button(box, "开 始 游 戏", 214.0, true)
	b1.pressed.connect(func(): get_parent().begin_new_match())
	var b2 := _menu_button(box, "设  置", 278.0)
	b2.pressed.connect(func(): AppState.goto(AppState.State.SETTINGS))
	var b3 := _menu_button(box, "退  出", 342.0)
	b3.pressed.connect(func(): get_tree().quit())

	# 右侧战况卡：文字直接压在战场上会被背景吃掉，必须垫一块木牌底。
	# 用 Panel（不是 PanelContainer）—— 容器会把子节点全部 fit 进自己的矩形，
	# 绝对定位就废了，这是部署页踩过的同一个坑
	var card := Panel.new()
	card.position = Vector2(596, 96)
	card.size = Vector2(452, 168)
	card.add_theme_stylebox_override("panel", Palette.panel_style(0.9, 2.0))
	box.add_child(card)
	var info := Label.new()
	info.position = Vector2(618, 116)
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Palette.UI_TEXT)
	info.text = "地图  烬区
模式  指挥官 · 20v20
编成  8 突击 / 6 支援 / 3 工程 / 3 侦察
载具  主战坦克 · 装甲车 · 防空车 · 武直 · 突击车"
	card.add_child(info)
	var tip := Label.new()
	tip.position = Vector2(618, 216)
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Palette.UI_GOLD_LIGHT)
	tip.text = "提示  控点 > 杀人。攻方兵力只有 180，守方无限。"
	card.add_child(tip)
	_stamp(box)

# ============================================================ 设置
func show_settings() -> void:
	_page = "settings"
	var box := _fresh("设置", "所有改动立即生效并自动保存")
	var y := 214.0
	y = _slider(box, "主音量", y, "master_volume", 0.0, 1.0)
	y = _slider(box, "震屏强度", y, "shake_scale", 0.0, 2.0)
	y = _toggle(box, "命中顿帧", y, "hitstop_enabled")
	y = _toggle(box, "辉光特效", y, "glow_enabled")
	y = _toggle(box, "显示帧率", y, "show_fps")
	var back := _menu_button(box, "返  回", y + 14.0)
	back.pressed.connect(func(): AppState.back())
	var reset := _menu_button(box, "恢复默认", y + 78.0)
	reset.pressed.connect(func():
		UserSettings.reset_defaults()
		show_settings())
	_stamp(box)

func _slider(box: Control, label: String, y: float, key: String, lo: float, hi: float) -> float:
	var l := Label.new()
	l.text = label
	l.position = Vector2(60, y)
	l.add_theme_font_size_override("font_size", 16)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = float(UserSettings.get(key))
	s.position = Vector2(210, y + 2)
	s.custom_minimum_size = Vector2(276, 22)
	box.add_child(s)
	var v := Label.new()
	v.position = Vector2(500, y)
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", Palette.UI_GOLD_LIGHT)
	v.text = "%d%%" % int(round(float(UserSettings.get(key)) * 100.0))
	box.add_child(v)
	s.value_changed.connect(func(nv: float):
		UserSettings.set_value(key, nv)
		v.text = "%d%%" % int(round(nv * 100.0)))
	return y + 48.0

func _toggle(box: Control, label: String, y: float, key: String) -> float:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(276, 38)
	b.position = Vector2(210, y)
	b.add_theme_font_size_override("font_size", 15)
	box.add_child(b)
	var paint := func():
		var on := bool(UserSettings.get(key))
		b.text = ("%s   开" % label) if on else ("%s   关" % label)
		b.add_theme_stylebox_override("normal",
			Palette.button_style(Palette.UI_WOOD_LIGHT if on else Palette.UI_WOOD,
				Palette.UI_GOLD if on else Palette.UI_TEXT_DIM))
	paint.call()
	b.pressed.connect(func():
		UserSettings.set_value(key, not bool(UserSettings.get(key)))
		paint.call())
	var l := Label.new()
	l.text = label
	l.position = Vector2(60, y + 8)
	l.add_theme_font_size_override("font_size", 16)
	box.add_child(l)
	return y + 48.0

# ============================================================ 暂停
func show_pause() -> void:
	if _page == "pause":
		return
	_page = "pause"
	var box := _fresh("已暂停", "对局冻结中 · Esc 继续")
	var b1 := _menu_button(box, "继  续", 214.0, true)
	b1.pressed.connect(func(): AppState.goto(AppState.State.PLAYING))
	var b2 := _menu_button(box, "设  置", 278.0)
	b2.pressed.connect(func(): AppState.goto(AppState.State.SETTINGS))
	var b3 := _menu_button(box, "返回主菜单", 342.0)
	b3.pressed.connect(func():
		AppState.goto(AppState.State.MAIN_MENU)
		get_parent().back_to_menu())
	var b4 := _menu_button(box, "退出游戏", 406.0)
	b4.pressed.connect(func(): get_tree().quit())
	var info := Label.new()
	info.position = Vector2(600, 120)
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Palette.UI_TEXT)
	info.text = "对局进度  兵力 %s : %s\n剩余时间  %s" % [
		MatchState.tickets_text(0), MatchState.tickets_text(1), MatchState.time_string()]
	box.add_child(info)
	_stamp(box)

## 主菜单的 attract mode：镜头在战场上缓慢巡游。
## 世界本来就在跑，这里只接管相机，让菜单背后是"活的"而不是静止帧
func _process(delta: float) -> void:
	if AppState.state != AppState.State.MAIN_MENU:
		return
	var main := get_parent()
	if main == null or not ("world" in main) or main.world == null:
		return
	var cam: Camera2D = main.world.camera
	if cam == null:
		return
	_pan_t += delta * 0.055
	var cx := 1500.0 + cos(_pan_t) * 620.0
	var cy := 1250.0 + sin(_pan_t * 0.7) * 380.0
	cam.global_position = cam.global_position.lerp(Vector2(cx, cy), clampf(delta * 1.2, 0.0, 1.0))
	cam.zoom = cam.zoom.lerp(Vector2.ONE * AppState.PREFERRED_MENU_ZOOM,
		clampf(delta * 1.0, 0.0, 1.0))
