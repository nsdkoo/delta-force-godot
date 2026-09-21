extends CanvasLayer
class_name HUD
## ============================================================================
## HUD · 战场界面
## ----------------------------------------------------------------------------
## 纯 Control 自绘（无 .tscn），监听 EventBus 获取事件，每帧读取 MatchState。
## 中文用 SystemFont（Godot 内置字体不含 CJK）。
## ============================================================================

var font: SystemFont
var font_bold: SystemFont
var layer_root: Control
var battle: BattleManager = null

# 事件驱动的瞬时状态
var feed_items: Array = []          ## {"text","color","t"}
var banner_text := ""
var banner_color := Color.WHITE
var banner_time := 0.0
var toast_text := ""
var toast_color := Color.WHITE
var toast_time := 0.0
var hitmarker := 0.0
var hitmarker_lethal := false
var hurt_flash := 0.0
var hurt_dir := 0.0
var hurt_dir_time := 0.0
var streak := 0
var uav := 0.0
var support_kind := ""
## 面板样式缓存：alpha 量化成整数当 key，避免每帧 new 一个 StyleBoxFlat
var _sb_cache: Dictionary = {}

## 命令行 `-- --scoreboard` 时强制展开计分板。
## 它是按住 Tab 才出现的临时界面，截图与美术比对没法合成按住动作，所以留这个开关。
var force_scoreboard := false

const FEED_MAX := 6
const BANNER_DUR := 3.2
const TOAST_DUR := 2.6

func _ready() -> void:
	layer = 10
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	font_bold = SystemFont.new()
	font_bold.font_names = font.font_names
	font_bold.font_weight = 700
	layer_root = Control.new()
	layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer_root)
	layer_root.draw.connect(_draw_hud)
	_connect_bus()

func _connect_bus() -> void:
	EventBus.kill_feed.connect(_on_feed)
	EventBus.feed.connect(_on_feed)
	EventBus.banner.connect(_on_banner)
	EventBus.toast.connect(_on_toast)
	EventBus.hitmarker.connect(_on_hitmarker)
	EventBus.player_hurt.connect(_on_hurt)
	EventBus.player_streak_changed.connect(func(s): streak = s)
	EventBus.player_uav.connect(func(t): uav = t)
	EventBus.support_ready.connect(_on_support_ready)
	EventBus.support_used.connect(func(_k, _p): support_kind = "")
	EventBus.objective_changed.connect(func(_t): pass)

func _on_feed(text: String, color: Color) -> void:
	feed_items.append({"text": text, "color": color,
		"t": Time.get_ticks_msec() / 1000.0})
	if feed_items.size() > FEED_MAX:
		feed_items.pop_front()

func _on_banner(text: String, color: Color, dur: float) -> void:
	banner_text = text
	banner_color = color
	banner_time = dur if dur > 0.0 else BANNER_DUR

func _on_toast(text: String, color: Color) -> void:
	toast_text = text
	toast_color = color
	toast_time = TOAST_DUR

func _on_hitmarker(_head: bool, lethal: bool, _dmg: float) -> void:
	hitmarker = 0.35
	hitmarker_lethal = lethal

func _on_hurt(dir: float, intensity: float) -> void:
	hurt_flash = minf(1.0, hurt_flash + intensity)
	hurt_dir = dir
	hurt_dir_time = 1.5

func _on_support_ready(kind: String) -> void:
	support_kind = kind

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(feed_items.size() - 1, -1, -1):
		if now - feed_items[i]["t"] > 7.5:
			feed_items.remove_at(i)
	if banner_time > 0.0:
		banner_time -= delta
	if toast_time > 0.0:
		toast_time -= delta
	if hitmarker > 0.0:
		hitmarker -= delta
	if hurt_flash > 0.0:
		hurt_flash = maxf(0.0, hurt_flash - delta * 1.7)
	if hurt_dir_time > 0.0:
		hurt_dir_time -= delta
	if uav > 0.0:
		uav = maxf(0.0, uav - delta)
	layer_root.queue_redraw()

# ============================================================ 绘制
func _draw_hud() -> void:
	var vp := layer_root.get_viewport_rect().size
	var player: Soldier = TeamManager.player
	if not MatchState.match_active and MatchState.phase != GameConfig.Phase.RESULT:
		return
	# 暗角
	_draw_vignette(vp)
	_draw_tickets(vp)
	_draw_captures(vp)
	_draw_feed()
	if player != null and is_instance_valid(player):
		_draw_squad(vp, player)
		var veh: CombatVehicle = _player_vehicle(player)
		if veh != null:
			_draw_vehicle(vp, player, veh)
		else:
			_draw_weapon(vp, player)
		_draw_minimap(vp, player)
		_draw_crosshair(vp, player)
		_draw_streak(vp)
		if not player.alive:
			_draw_death(vp, player)
	_draw_banner(vp)
	_draw_toast(vp)
	_draw_hurt(vp)
	_draw_rescue(vp, player)
	_draw_marks(vp)
	_draw_ops(vp)
	_draw_version(vp)
	# 计分板压在最上层：它是按住才会出现的临时界面
	if force_scoreboard or Input.is_action_pressed("scoreboard"):
		_draw_scoreboard(vp, player)

## 版本角标 + 帧率。放在最角落、字号最小：它是给排障用的，不是给玩家看的
func _draw_version(vp: Vector2) -> void:
	if UserSettings.show_fps:
		var fps := int(round(Engine.get_frames_per_second()))
		layer_root.draw_string(font, Vector2(10, vp.y - 24), "%d FPS" % fps,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color("#57e08a") if fps >= 55 else (Color("#ffd24a") if fps >= 35 else Color("#ff5b4a")))
	layer_root.draw_string(font, Vector2(10, vp.y - 8),
		"v%s" % AppState.VERSION, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.UI_TEXT_DIM)

# ============================================================ 倒地与救援
## 倒地是"还能救回来的一段时间"，所以它必须在画面上有明确的读秒与入口提示，
## 否则玩家只会以为自己死了
func _draw_rescue(vp: Vector2, player: Soldier) -> void:
	if player == null or not is_instance_valid(player):
		return
	for u in TeamManager.downed_units(player.team):
		var sp := _to_screen(vp, u.global_position)
		if sp == Vector2.INF:
			continue
		if sp.x < -40.0 or sp.y < -40.0 or sp.x > vp.x + 40.0 or sp.y > vp.y + 40.0:
			continue
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 200.0)
		layer_root.draw_arc(sp, 21.0, 0, TAU, 22, Color(1.0, 0.62, 0.25, pulse), 2.4)
		var tag := ("你 · 待救援" if u.is_player else "%s · 待救援" % u.unit_name)
		layer_root.draw_string(font, sp + Vector2(25, 4), "%s %.0fs" % [tag, u.bleed_out],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffb45a"))
	if player.downed:
		layer_root.draw_rect(Rect2(0, vp.y * 0.5 - 84, vp.x, 168), _bg(0.58), true)
		layer_root.draw_string(font_bold, Vector2(vp.x * 0.5 - 66, vp.y * 0.5 - 8), "倒 地",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color("#ffb45a"))
		layer_root.draw_string(font, Vector2(vp.x * 0.5 - 200, vp.y * 0.5 + 30),
			"流血 %.1fs · WASD 爬行 · 队友靠近按 G 拖拽救援，救起可回 %.0f%% 血"
				% [maxf(0.0, player.bleed_out), GameConfig.REVIVE_HP_RATIO * 100.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.UI_TEXT)
	if player.drag_target != null and is_instance_valid(player.drag_target):
		var k := clampf(player.drag_target.revive_progress / GameConfig.REVIVE_TIME, 0.0, 1.0)
		var w := 280.0
		var r := Rect2(vp.x * 0.5 - w * 0.5, vp.y - 196.0, w, 28.0)
		_panel(r, 0.85)
		layer_root.draw_rect(Rect2(r.position.x + 9, r.position.y + 9, (w - 18) * k, 10),
			Color("#57e08a"), true)
		layer_root.draw_string(font_bold, Vector2(r.position.x + 10, r.position.y + 19),
			"救援中 %.0f%%" % (k * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.UI_TEXT)
# ============================================================ 指挥部
## 世界坐标 -> 屏幕坐标。HUD 是 CanvasLayer（屏幕空间），标记与落点在世界空间，
## 中间必须换算一次
func _to_screen(vp: Vector2, world: Vector2) -> Vector2:
	var view := get_tree().get_first_node_in_group("battlefield_view")
	if view != null:
		return view.world_to_screen(world)
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Vector2.INF
	return (world - cam.global_position) * cam.zoom + vp * 0.5

## 标记：五边形旗标 + 脉冲圈。敌我通用，靠颜色区分
func _draw_marks(vp: Vector2) -> void:
	if not MatchState.match_active and MatchState.phase != GameConfig.Phase.RESULT:
		return
	var col_map := {"vip_point": Palette.MARK_GOLD, "threat_veh": Palette.MARK_ATTACK}
	for m in CommandOps.marks:
		var sp := _to_screen(vp, m["pos"])
		if sp == Vector2.INF:
			continue
		var col: Color = col_map.get(m["kind"], Palette.MARK_GOLD)
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 220.0)
		layer_root.draw_arc(sp, 26.0 + pulse * 5.0, 0, TAU, 26, Color(col.r, col.g, col.b, 0.75), 2.4)
		var pts := PackedVector2Array()
		for i in 5:
			var a := -PI * 0.5 + TAU * float(i) / 5.0
			pts.append(sp + Vector2(cos(a), sin(a)) * 13.0)
		layer_root.draw_colored_polygon(pts, Palette.OUTLINE)
		var inner := PackedVector2Array()
		for p in pts:
			inner.append(sp + (p - sp) * 0.72)
		layer_root.draw_colored_polygon(inner, col)
		layer_root.draw_string(font_bold, sp + Vector2(20, -16), m["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

## 阵营积分 + 指挥官技能栏。
## 技能栏只在"玩家是指挥官"时出现 —— 不是指挥官的人看到一堆按不动的按钮
## 只会添乱，而指挥官看不到自己的技能就等于这套系统不存在
func _draw_ops(vp: Vector2) -> void:
	if not MatchState.match_active and MatchState.phase != GameConfig.Phase.RESULT:
		return
	# 积分条：挂在据点状态下面
	var y := 122.0
	var txt := "阵营积分   GTI %d      哈夫克 %d" % [int(CommandOps.points[0]), int(CommandOps.points[1])]
	var tw := 320.0
	_panel(Rect2((vp.x - tw) * 0.5, y, tw, 26.0), 0.72)
	layer_root.draw_string(font_bold, Vector2((vp.x - tw) * 0.5 + 14, y + 18), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.UI_TEXT)
	if not MatchState.commander_is_player(GameConfig.Team.GTI):
		return
	# 指挥官技能栏
	var ids := CommandOps.skill_defs(GameConfig.Team.GTI)
	var rows: Array = []
	var keys := ["[5]", "[6]"]
	for i in ids.size():
		var id: String = ids[i]
		var d: Dictionary = GameConfig.CMD_SKILLS[id]
		var cd := CommandOps.skill_cd_left(GameConfig.Team.GTI, id)
		var st := "就绪" if cd <= 0.0 else "冷却 %.0fs" % cd
		if CommandOps.points[GameConfig.Team.GTI] < float(d["cost"]):
			st = "积分不足"
		rows.append("%s %s  %d分  %s" % [keys[i] if i < keys.size() else "[-]", d["name"],
			int(d["cost"]), st])
	for kd in [["heavy_1", "artillery"], ["heavy_2", "missile"]]:
		var hd: Dictionary = GameConfig.HEAVY_SUPPORT[kd[1]]
		var hcd := CommandOps.heavy_cd_left(GameConfig.Team.GTI, kd[1])
		var hst := "就绪" if hcd <= 0.0 else "冷却 %.0fs" % hcd
		if CommandOps.points[GameConfig.Team.GTI] < float(hd["cost"]):
			hst = "积分不足"
		rows.append("%s %s  %d分  %s" % ["[7]" if kd[1] == "artillery" else "[8]",
			hd["name"], int(hd["cost"]), hst])
	var fcd := CommandOps.fort_cd_left(GameConfig.Team.GTI)
	rows.append("[B] 架设工事  %s" % ("就绪" if fcd <= 0.0 else "冷却 %.0fs" % fcd))

	var w2 := 300.0
	var h2 := 16.0 + rows.size() * 19.0
	var x2 := (vp.x - w2) * 0.5
	var y2 := vp.y - h2 - 14.0
	_panel(Rect2(x2, y2, w2, h2), 0.82)
	layer_root.draw_string(font_bold, Vector2(x2 + 10, y2 + 16), "指挥官指令",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.UI_GOLD_LIGHT)
	var ry := y2 + 32.0
	for r in rows:
		layer_root.draw_string(font, Vector2(x2 + 10, ry), r,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.UI_TEXT)
		ry += 19.0

func _player_vehicle(player: Soldier) -> CombatVehicle:
	if player.in_vehicle == null or not is_instance_valid(player.in_vehicle):
		return null
	return player.in_vehicle as CombatVehicle

func _draw_vignette(vp: Vector2) -> void:
	# 用四条渐隐边框模拟暗角（draw_rect 不支持渐变，用多层近似）
	var layers := 5
	for i in layers:
		var k := float(i) / float(layers)
		var inset := k * 40.0
		var a := 0.055 * (1.0 - k)
		layer_root.draw_rect(Rect2(0, 0, vp.x, inset), Color(0.05, 0.03, 0.01, a), true)
		layer_root.draw_rect(Rect2(0, vp.y - inset, vp.x, inset), Color(0.05, 0.03, 0.01, a), true)
		layer_root.draw_rect(Rect2(0, 0, inset, vp.y), Color(0.05, 0.03, 0.01, a), true)
		layer_root.draw_rect(Rect2(vp.x - inset, 0, inset, vp.y), Color(0.05, 0.03, 0.01, a), true)

## HUD 面板底：木牌 + 金边 + 大圆角。
## 用 draw_style_box 而不是 draw_rect —— draw_rect 画不出圆角，
## 而"圆角 + 亮金描边"正是卡通界面最容易一眼认出来的特征。
func _panel(r: Rect2, alpha: float = 0.88) -> void:
	var key := int(round(alpha * 100.0))
	if not _sb_cache.has(key):
		var a := float(key) / 100.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Palette.UI_WOOD.r, Palette.UI_WOOD.g, Palette.UI_WOOD.b, a)
		sb.border_color = Color(Palette.UI_GOLD.r, Palette.UI_GOLD.g, Palette.UI_GOLD.b, minf(1.0, a + 0.30))
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		_sb_cache[key] = sb
	layer_root.draw_style_box(_sb_cache[key], r)

## 无边框的深色底（播报条、横幅内的底衬），统一到木色系
func _bg(a: float) -> Color:
	return Color(Palette.UI_WOOD_DARK.r, Palette.UI_WOOD_DARK.g, Palette.UI_WOOD_DARK.b, a)

func _draw_tickets(vp: Vector2) -> void:
	var w := minf(560.0, vp.x * 0.5)
	var x := (vp.x - w) * 0.5
	var y := 14.0
	_panel(Rect2(x - 10, y - 8, w + 20, 52))
	var half := w * 0.5 - 6.0
	# 条底
	layer_root.draw_rect(Rect2(x, y, w, 12), Color(1, 1, 1, 0.08), true)
	# 攻方（左）/守方（右）
	var k0 := MatchState.ticket_ratio(0)
	var k1 := MatchState.ticket_ratio(1)
	layer_root.draw_rect(Rect2(x, y, half * k0, 12), GameConfig.TEAM_COLOR[0], true)
	layer_root.draw_rect(Rect2(x + w - half * k1, y, half * k1, 12), GameConfig.TEAM_COLOR[1], true)
	layer_root.draw_rect(Rect2(x + w * 0.5 - 3, y - 4, 6, 20), _bg(0.9), true)
	# 文本
	layer_root.draw_string(font_bold, Vector2(x + 4, y + 36), "GTI  %s" % MatchState.tickets_text(0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GameConfig.TEAM_COLOR[0])
	layer_root.draw_string(font_bold, Vector2(x + w - 130, y + 36), "哈夫克  %s" % MatchState.tickets_text(1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GameConfig.TEAM_COLOR[1])
	var clock := MatchState.overtime_label() if MatchState.overtime else MatchState.time_string()
	var clock_col := Color("#ff5b4a") if MatchState.overtime else Palette.UI_TEXT
	layer_root.draw_string(font, Vector2(x + w * 0.5 - 26, y + 36), clock,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, clock_col)

func _draw_captures(vp: Vector2) -> void:
	var n := GameConfig.CAPTURES.size()
	var cw := 52.0
	var gap := 6.0
	var seg_gap := 14.0
	# A / B / C 三组之间多留缝，一眼看出「先打 A 再开 B」
	var total := n * cw + (n - 1) * gap + 2.0 * seg_gap
	var x := (vp.x - total) * 0.5
	var y := 74.0
	var last_seg := -1
	for c in GameConfig.CAPTURES:
		var cseg: int = int(c["seg"])
		if last_seg >= 0 and cseg != last_seg:
			x += seg_gap
		last_seg = cseg
		var st: Dictionary = MatchState.captures[c["id"]]
		var unlocked := cseg <= MatchState.unlocked_segment
		var own: bool = st["owner"] == GameConfig.Team.GTI
		var col: Color = GameConfig.TEAM_COLOR[0] if own else GameConfig.TEAM_COLOR[1]
		if not unlocked:
			col = Color(0.55, 0.55, 0.58)
		var r := Rect2(x, y, cw, 30)
		layer_root.draw_rect(r, _bg(0.7), true)
		var prog: float = st["progress"] / 100.0
		if unlocked and prog > 0.001:
			layer_root.draw_rect(Rect2(x + 2, y + 28 - 26 * prog, cw - 4, 26 * prog),
				Color(1.0, 0.82, 0.29, 0.45), true)
		layer_root.draw_rect(r, col, false, 2.0)
		if unlocked and st["contested"]:
			layer_root.draw_rect(r.grow(2.0), Color(1.0, 0.82, 0.29, 0.9), false, 2.0)
		if cseg == MatchState.unlocked_segment:
			layer_root.draw_rect(r.grow(3.0), Color(1.0, 0.82, 0.29, 0.55), false, 1.5)
		layer_root.draw_string(font_bold, Vector2(x + 16, y + 21), c["id"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		x += cw + gap
	var seg := clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
	layer_root.draw_string(font, Vector2((vp.x - 280) * 0.5, y + 48),
		"当前目标区域：" + GameConfig.SEGMENTS[seg]["name"] + " · 攻占本区全部据点解锁下一区",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.UI_TEXT_DIM)

func _draw_feed() -> void:
	var y := 150.0
	for item in feed_items:
		var age: float = Time.get_ticks_msec() / 1000.0 - item["t"]
		var a := clampf(1.0 - age / 7.5, 0.12, 1.0)
		var col: Color = item["color"]
		layer_root.draw_rect(Rect2(10, y - 14, 420, 21), _bg(0.5 * a), true)
		layer_root.draw_rect(Rect2(10, y - 14, 3, 21), Color(col.r, col.g, col.b, a), true)
		layer_root.draw_string(font, Vector2(20, y + 1), item["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col.r, col.g, col.b, a))
		y += 24.0

func _draw_squad(vp: Vector2, player: Soldier) -> void:
	var sq: Squad = TeamManager.squad_of(player)
	if sq == null:
		return
	var w := 250.0
	var h := 26.0 + sq.members.size() * 30.0
	var x := 14.0
	var y := vp.y - h - 14.0
	_panel(Rect2(x, y, w, h))
	var team_cn: String = GameConfig.TEAM_ROLE[player.team]
	layer_root.draw_string(font_bold, Vector2(x + 10, y + 20),
		"第 %d 小队 · %s" % [sq.id % 5 + 1, team_cn], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Palette.UI_TEXT_DIM)
	if sq.order_kind >= 0:
		layer_root.draw_string(font, Vector2(x + 140, y + 20), sq.order_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GameConfig.ORDER_INFO[sq.order_kind]["color"])
	var oy := y + 34.0
	for m in sq.members:
		if not is_instance_valid(m):
			continue
		var col: Color = GameConfig.op(m.op_id)["color"]
		if not m.alive:
			col = Color(0.36, 0.42, 0.47)
		layer_root.draw_circle(Vector2(x + 18, oy), 5.0, col)
		var label: String = ("你" if m.is_player else m.unit_name) + " · " + GameConfig.CLASS_NAME_CN[m.op_class]
		layer_root.draw_string(font, Vector2(x + 30, oy + 5), label,
			HORIZONTAL_ALIGNMENT_LEFT, 180, 12, Palette.UI_TEXT)
		var k := clampf(m.hp / m.max_hp, 0.0, 1.0)
		layer_root.draw_rect(Rect2(x + 30, oy + 9, 190, 4), Color(0, 0, 0, 0.5), true)
		var hc := Color("#57e08a")
		if k < 0.3:
			hc = Color("#ff5b4a")
		elif k < 0.6:
			hc = Color("#ffd24a")
		layer_root.draw_rect(Rect2(x + 30, oy + 9, 190 * k, 4), hc, true)
		oy += 30.0

func _draw_weapon(vp: Vector2, player: Soldier) -> void:
	var w := 262.0
	var h := 118.0
	var x := vp.x - w - 14.0
	var y := vp.y - h - 14.0
	_panel(Rect2(x, y, w, h))
	layer_root.draw_string(font_bold, Vector2(x + 12, y + 26), player.weapon["name"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.UI_TEXT)
	if player.is_reloading:
		layer_root.draw_string(font, Vector2(x + 12, y + 48),
			"换弹中… %.1fs" % player.reload_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd24a"))
	else:
		layer_root.draw_string(font, Vector2(x + 12, y + 48),
			"弹匣 %d / %d    备弹 %d" % [player.ammo, player.weapon["mag"], player.reserve],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.UI_TEXT)
	var sk_ready := player.skill_cd <= 0.0
	var sk_col: Color = GameConfig.op(player.op_id)["color"] if sk_ready else Color(0.36, 0.42, 0.47)
	layer_root.draw_string(font, Vector2(x + 12, y + 70),
		"[Q] %s%s" % [GameConfig.op(player.op_id)["skill"],
			"  就绪" if sk_ready else "  冷却 %.1fs" % player.skill_cd],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, sk_col)
	layer_root.draw_string(font, Vector2(x + 12, y + 90),
		"[E] 野战急救%s" % ("  就绪" if player.field_med_cd <= 0.0 else "  冷却 %.1fs" % player.field_med_cd),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Palette.UI_TEXT if player.field_med_cd <= 0.0 else Color(0.36, 0.42, 0.47))
	var k := clampf(player.hp / player.max_hp, 0.0, 1.0)
	layer_root.draw_rect(Rect2(x + 12, y + 98, 238, 8), Color(0, 0, 0, 0.5), true)
	var hc := Color("#57e08a")
	if k < 0.25:
		hc = Color("#ff5b4a")
	elif k < 0.5:
		hc = Color("#ffd24a")
	layer_root.draw_rect(Rect2(x + 12, y + 98, 238 * k, 8), hc, true)

func _draw_minimap(vp: Vector2, player: Soldier) -> void:
	var mw := 216.0
	var mh := 150.0
	var x := vp.x - mw - 14.0
	var y := vp.y - mh - 150.0
	_panel(Rect2(x, y, mw, mh), 0.75)
	var sx := mw / GameConfig.WORLD_SIZE.x
	var sy := mh / GameConfig.WORLD_SIZE.y
	# 建筑
	for b in _map_buildings():
		var r: Rect2 = b["rect"]
		layer_root.draw_rect(Rect2(x + r.position.x * sx, y + r.position.y * sy,
			maxf(1.0, r.size.x * sx * 1.4), maxf(1.0, r.size.y * sy * 1.4)),
			Color(0.16, 0.14, 0.11, 0.55), true)
	# 据点
	for c in GameConfig.CAPTURES:
		var st: Dictionary = MatchState.captures[c["id"]]
		var own: bool = st["owner"] == GameConfig.Team.GTI
		var col: Color = GameConfig.TEAM_COLOR[0] if own else GameConfig.TEAM_COLOR[1]
		var p: Vector2 = c["pos"]
		layer_root.draw_circle(Vector2(x + p.x * sx, y + p.y * sy), 8.0,
			Color(col.r, col.g, col.b, 0.45))
		layer_root.draw_arc(Vector2(x + p.x * sx, y + p.y * sy), 8.0, 0, TAU, 16, col, 1.5)
		layer_root.draw_string(font_bold, Vector2(x + p.x * sx - 7, y + p.y * sy + 4), c["id"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	# 单位
	for u in TeamManager.alive_units():
		var is_visible: bool = u.team == player.team or uav > 0.0 or _is_spotted(u)
		if not is_visible:
			continue
		var up := Vector2(x + u.global_position.x * sx, y + u.global_position.y * sy)
		var c2: Color = GameConfig.TEAM_COLOR[u.team]
		if u.is_player:
			c2 = Color("#ffd24a")
		layer_root.draw_circle(up, 2.6 if u.is_player else 1.9, c2)
	# 视野框
	var cam := player.get_viewport().get_camera_2d()
	if cam != null:
		var vs := player.get_viewport_rect().size
		var cam_rect := Rect2(cam.global_position - vs * 0.5, vs)
		layer_root.draw_rect(Rect2(x + cam_rect.position.x * sx, y + cam_rect.position.y * sy,
			cam_rect.size.x * sx, cam_rect.size.y * sy), Color(1, 1, 1, 0.28), false, 1.0)
	layer_root.draw_string(font, Vector2(x + 4, y + mh - 5), "烬区 · 20v20", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Palette.UI_TEXT_DIM)

func _is_spotted(u: Soldier) -> bool:
	if not u.has_meta("spotted_until"):
		return false
	return u.get_meta("spotted_until") > Time.get_ticks_msec() / 1000.0

func _map_buildings() -> Array:
	var m = get_tree().get_first_node_in_group("world_map")
	if m != null and "buildings" in m:
		return m.buildings
	return []

func _draw_crosshair(vp: Vector2, player: Soldier) -> void:
	if not player.alive:
		return
	var c := layer_root.get_global_mouse_position()
	var spread := 16.0 + player.spread_heat * 22.0
	if player.aiming_down_sight:
		spread -= 8.0
	layer_root.draw_line(c + Vector2(-spread, 0), c + Vector2(-5, 0), Color(1, 1, 1, 0.85), 2.0)
	layer_root.draw_line(c + Vector2(5, 0), c + Vector2(spread, 0), Color(1, 1, 1, 0.85), 2.0)
	layer_root.draw_line(c + Vector2(0, -spread), c + Vector2(0, -5), Color(1, 1, 1, 0.85), 2.0)
	layer_root.draw_line(c + Vector2(0, 5), c + Vector2(0, spread), Color(1, 1, 1, 0.85), 2.0)
	if player.aiming_down_sight:
		layer_root.draw_arc(c, 7.0, 0, TAU, 20, Color(1, 0.82, 0.29, 0.5), 1.4)
	if hitmarker > 0.0:
		var col := Color(1, 0.35, 0.24, clampf(hitmarker * 3.0, 0.0, 1.0))
		var s := 12.0
		layer_root.draw_line(c + Vector2(-s, -s), c + Vector2(-4, -4), col, 3.0)
		layer_root.draw_line(c + Vector2(s, -s), c + Vector2(4, -4), col, 3.0)
		layer_root.draw_line(c + Vector2(-s, s), c + Vector2(-4, 4), col, 3.0)
		layer_root.draw_line(c + Vector2(s, s), c + Vector2(4, 4), col, 3.0)

func _draw_death(vp: Vector2, player: Soldier) -> void:
	layer_root.draw_rect(Rect2(0, vp.y * 0.5 - 70, vp.x, 140), _bg(0.55), true)
	layer_root.draw_string(font_bold, Vector2(vp.x * 0.5 - 60, vp.y * 0.5 - 8), "阵 亡",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color("#ff8a7a"))
	layer_root.draw_string(font, Vector2(vp.x * 0.5 - 140, vp.y * 0.5 + 26),
		"重生倒计时 %.1fs · 将在己方控制区重新部署" % maxf(0.0, player.respawn_timer),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.UI_TEXT)
	layer_root.draw_string(font, Vector2(vp.x * 0.5 - 110, vp.y * 0.5 + 50),
		"票数 -1 · 阵亡会消耗阵营票数", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.UI_TEXT_DIM)

func _draw_banner(vp: Vector2) -> void:
	if banner_time <= 0.0 or banner_text == "":
		return
	var a := clampf(banner_time / 0.6, 0.0, 1.0)
	var w := 640.0
	var r := Rect2((vp.x - w) * 0.5, vp.y * 0.19, w, 54)
	layer_root.draw_rect(r, _bg(0.84 * a), true)
	layer_root.draw_rect(r, Color(banner_color.r, banner_color.g, banner_color.b, a), false, 2.0)
	layer_root.draw_string(font_bold, Vector2(r.position.x + 26, r.position.y + 37), banner_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(banner_color.r, banner_color.g, banner_color.b, a))

func _draw_toast(vp: Vector2) -> void:
	if toast_time <= 0.0 or toast_text == "":
		return
	var a := clampf(toast_time / 0.5, 0.0, 1.0)
	var w := 420.0
	var r := Rect2((vp.x - w) * 0.5, vp.y - 150.0, w, 32)
	layer_root.draw_rect(r, _bg(0.8 * a), true)
	layer_root.draw_rect(r, Color(toast_color.r, toast_color.g, toast_color.b, 0.8 * a), false, 1.5)
	layer_root.draw_string(font_bold, Vector2(r.position.x + 14, r.position.y + 22), toast_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(toast_color.r, toast_color.g, toast_color.b, a))
	if support_kind != "":
		var t := "支援就绪 · 按 X 呼叫"
		layer_root.draw_string(font_bold, Vector2(vp.x * 0.5 - 80, r.position.y - 12), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd24a"))

func _draw_hurt(vp: Vector2) -> void:
	if hurt_flash > 0.0:
		layer_root.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.67, 0.07, 0.07, hurt_flash * 0.42), true)
	if hurt_dir_time > 0.0:
		var c := vp * 0.5
		var dir := Vector2(cos(hurt_dir), sin(hurt_dir))
		var a := clampf(hurt_dir_time / 0.7, 0.0, 1.0)
		var pts := PackedVector2Array([
			c + dir * 96.0,
			c + dir.rotated(0.22) * 142.0,
			c + dir.rotated(-0.22) * 142.0])
		layer_root.draw_colored_polygon(pts, Color(1.0, 0.36, 0.29, a * 0.85))

# ============================================================ 载具
## 驾驶时右侧面板由"武器"换成"车况"。车上没有弹匣与技能，但有弹种和 APS。
func _draw_vehicle(vp: Vector2, player: Soldier, veh: CombatVehicle) -> void:
	var w := 262.0
	var h := 118.0
	var x := vp.x - w - 14.0
	var y := vp.y - h - 14.0
	_panel(Rect2(x, y, w, h))
	layer_root.draw_string(font_bold, Vector2(x + 12, y + 26), veh.display_name(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.UI_TEXT)
	# 车体血量
	var k := clampf(veh.hp / maxf(veh.max_hp, 1.0), 0.0, 1.0)
	layer_root.draw_rect(Rect2(x + 12, y + 36, 238, 9), Color(0, 0, 0, 0.5), true)
	var hc := Color("#57e08a")
	if k < 0.25:
		hc = Color("#ff5b4a")
	elif k < 0.5:
		hc = Color("#ffd24a")
	layer_root.draw_rect(Rect2(x + 12, y + 36, 238 * k, 9), hc, true)
	layer_root.draw_string(font, Vector2(x + 12, y + 60), "%d / %d" % [int(veh.hp), int(veh.max_hp)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.UI_TEXT)
	# 弹种
	var ammo_col: Color = Color("#ffc24a") if veh.ammo_mode == 1 else Color("#8fc4ff")
	var ammo_txt := "[1/2] %s" % veh.ammo_label()
	if veh.ammo_switch_cd > 0.0:
		ammo_txt += "  装填 %.1fs" % veh.ammo_switch_cd
	layer_root.draw_string(font, Vector2(x + 12, y + 80), ammo_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ammo_col)
	# APS
	var aps_txt: String
	var aps_col: Color
	if veh.aps_timer > 0.0:
		aps_txt = "[3] 主动防御 生效 %.1fs" % veh.aps_timer
		aps_col = Color("#57e08a")
	elif veh.aps_cd > 0.0:
		aps_txt = "[3] 主动防御 冷却 %.1fs" % veh.aps_cd
		aps_col = Color(0.36, 0.42, 0.47)
	else:
		aps_txt = "[3] 主动防御 就绪"
		aps_col = Color("#8fc4ff")
	layer_root.draw_string(font, Vector2(x + 12, y + 100), aps_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, aps_col)
	layer_root.draw_string(font, Vector2(x + 150, y + 100), "[F] 下车",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.UI_TEXT_DIM)

# ============================================================ 连杀
## 右上角常驻：连杀数 / 到下一档的进度 / 待呼叫的支援 / UAV 剩余时间。
## 放在右上是因为左侧归击杀播报、顶部归票数与据点、右下归武器与雷达，
## 右上这块在整场战斗里都没有被占用。
func _draw_streak(vp: Vector2) -> void:
	var w := 252.0
	var h := 64.0
	var x := vp.x - w - 14.0
	var y := 14.0
	_panel(Rect2(x, y, w, h), 0.62)
	var cur := StreakManager.streak
	layer_root.draw_string(font_bold, Vector2(x + 12, y + 26), "连杀  %d" % cur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
		Color("#ffd24a") if cur > 0 else Palette.UI_TEXT_DIM)
	var nxt := StreakManager.next_threshold()
	if nxt > 0:
		layer_root.draw_string(font, Vector2(x + 100, y + 25), "下一档 %d 杀" % nxt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.UI_TEXT_DIM)
		# 进度条：用相邻两档之间的比例，到顶后填满
		var prev := 0
		for t in GameConfig.STREAK_REWARDS:
			if t < nxt:
				prev = t
		var k := clampf(float(cur - prev) / float(maxi(nxt - prev, 1)), 0.0, 1.0)
		layer_root.draw_rect(Rect2(x + 12, y + 34, 228, 5), Color(1, 1, 1, 0.1), true)
		layer_root.draw_rect(Rect2(x + 12, y + 34, 228 * k, 5), Color("#ffd24a"), true)
	else:
		layer_root.draw_string(font, Vector2(x + 100, y + 25), "全部解锁",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.UI_TEXT_DIM)
	# 待呼叫支援 / UAV
	if StreakManager.support_kind != "":
		layer_root.draw_string(font_bold, Vector2(x + 12, y + 54),
			"[X] %s 待呼叫" % StreakManager.support_label(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff9a3a"))
	elif uav > 0.0:
		layer_root.draw_string(font_bold, Vector2(x + 12, y + 54),
			"无人机侦察中  %.1fs" % uav, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8fc4ff"))

# ============================================================ 计分板
## 按住 Tab 显示。左右两列各一支队伍，按得分排序。
## 只读数据、不缓存 —— 计分板是低频界面，每帧重排 40 个元素的开销可以忽略，
## 而缓存反而会在重生/换兵种时显示陈旧数据。
func _draw_scoreboard(vp: Vector2, player: Soldier) -> void:
	var w := 1160.0
	var h := 600.0
	var px := (vp.x - w) * 0.5
	var py := (vp.y - h) * 0.5
	layer_root.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.02, 0.03, 0.04, 0.55), true)
	_panel(Rect2(px, py, w, h), 0.93)
	layer_root.draw_string(font_bold, Vector2(px + 24, py + 40), "战 绩 · 烬区",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.UI_TEXT)
	var head := "据点 %d / %d    %s" % [
		MatchState.owned_count(GameConfig.Team.GTI), GameConfig.CAPTURES.size(),
		MatchState.time_string()]
	layer_root.draw_string(font, Vector2(px + w - 300, py + 38), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.UI_TEXT_DIM)
	var col_w := 552.0
	for i in 2:
		_draw_score_column(px + 20.0 + float(i) * (col_w + 16.0), py + 62.0, col_w, i, player)

func _draw_score_column(x: float, y: float, w: float, team: int, player: Soldier) -> void:
	var col: Color = GameConfig.TEAM_COLOR[team]
	layer_root.draw_string(font_bold, Vector2(x + 4, y + 20),
		"%s · %s" % [GameConfig.TEAM_NAME[team], GameConfig.TEAM_ROLE[team]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	layer_root.draw_string(font, Vector2(x + w - 110, y + 20), "兵力  %s" % MatchState.tickets_text(team),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
	# 表头
	var hy := y + 34.0
	layer_root.draw_string(font, Vector2(x + 4, hy), "干员",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.UI_TEXT_DIM)
	for spec in [["兵种", 232.0], ["K", 300.0], ["D", 328.0], ["伤害", 360.0], ["得分", 452.0]]:
		layer_root.draw_string(font, Vector2(x + float(spec[1]), hy), str(spec[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.UI_TEXT_DIM)
	layer_root.draw_line(Vector2(x, hy + 4.0), Vector2(x + w - 30.0, hy + 4.0),
		Color(0.47, 0.71, 0.86, 0.2), 1.0)
	var units: Array = TeamManager.all_units(team)
	units.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var ry := hy + 20.0
	for u in units:
		var is_me: bool = player != null and is_instance_valid(player) and u == player
		var mine: bool = player != null and is_instance_valid(player) and u.team == player.team \
			and player.squad_id == u.squad_id
		if is_me:
			layer_root.draw_rect(Rect2(x - 2, ry - 11, w - 24, 19), Color(1.0, 0.82, 0.29, 0.16), true)
		elif mine:
			layer_root.draw_rect(Rect2(x - 2, ry - 11, w - 24, 19), Color(0.47, 0.71, 0.86, 0.09), true)
		var name_col := Palette.UI_TEXT if u.alive else Color(0.38, 0.43, 0.47)
		if is_me:
			name_col = Color("#ffd24a")
		var nm: String = ("你" if u.is_player else u.unit_name)
		if u.is_commander:
			nm = "★ " + nm
		elif u.is_squad_leader:
			nm = "▲ " + nm
		layer_root.draw_string(font, Vector2(x + 4, ry), nm,
			HORIZONTAL_ALIGNMENT_LEFT, 190, 12, name_col)
		layer_root.draw_string(font, Vector2(x + 232, ry), GameConfig.CLASS_NAME_CN[u.op_class],
			HORIZONTAL_ALIGNMENT_LEFT, 60, 12, Palette.UI_TEXT)
		layer_root.draw_string(font, Vector2(x + 300, ry), str(u.kills),
			HORIZONTAL_ALIGNMENT_LEFT, 24, 12, Palette.UI_TEXT)
		layer_root.draw_string(font, Vector2(x + 328, ry), str(u.deaths),
			HORIZONTAL_ALIGNMENT_LEFT, 24, 12, Palette.UI_TEXT_DIM)
		layer_root.draw_string(font, Vector2(x + 360, ry), str(int(u.damage_done)),
			HORIZONTAL_ALIGNMENT_LEFT, 80, 12, Palette.UI_TEXT)
		layer_root.draw_string(font, Vector2(x + 452, ry), str(int(u.score)),
			HORIZONTAL_ALIGNMENT_LEFT, 70, 12, name_col)
		ry += 20.0
	# 载具单列一节：它们是团队资产而不是某个人的战绩，混进干员榜会打乱排序
	ry += 6.0
	layer_root.draw_string(font, Vector2(x + 4, ry), "装甲",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.UI_TEXT_DIM)
	ry += 18.0
	for v in TeamManager.vehicles:
		if not is_instance_valid(v) or v.team != team:
			continue
		var st: String = "在场" if v.alive else "损毁  %.0fs" % maxf(0.0, v.respawn_timer)
		var vc: Color = Palette.UI_TEXT if v.alive else Color(0.38, 0.43, 0.47)
		layer_root.draw_string(font, Vector2(x + 4, ry),
			v.display_name() + ("（你驾驶）" if v.has_player_driver() else ""),
			HORIZONTAL_ALIGNMENT_LEFT, 220, 12, vc)
		layer_root.draw_string(font, Vector2(x + 300, ry), "%d / %d" % [int(v.hp), int(v.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, 90, 12, vc)
		layer_root.draw_string(font, Vector2(x + 400, ry), st,
			HORIZONTAL_ALIGNMENT_LEFT, 110, 12, vc)
		ry += 20.0
