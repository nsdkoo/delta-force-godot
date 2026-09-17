extends Node2D
class_name CapturePoint
## ============================================================================
## CapturePoint · 据点
## ----------------------------------------------------------------------------
## 半径内人数差决定占领进度。攻方（GTI）推进进度到 100 即翻转归属。
## 未解锁区域内的据点强制归守方（对应真实玩法：区域未开放不可占）。
## ============================================================================

var point_id: String = ""
var cap_name: String = ""
var seg: int = 0
var radius: float = 150.0
var own_team: int = GameConfig.Team.HAVOC
var progress: float = 0.0          ## 0 = 完全守方 / 100 = 完全攻方
var contested: bool = false
var attackers: int = 0
var defenders: int = 0

const RATE := 6.2                   ## 每秒进度变化（按人数差缩放）

func setup(def: Dictionary) -> void:
	point_id = def["id"]
	cap_name = def["name"]
	seg = def["seg"]
	radius = def["radius"]
	global_position = def["pos"]
	own_team = GameConfig.Team.HAVOC
	progress = 0.0
	z_index = -18                    ## 画在地面装饰之上、建筑之下

func _ready() -> void:
	z_as_relative = true
	queue_redraw()

func _process(delta: float) -> void:
	refresh(delta)

func refresh(delta: float) -> void:
	attackers = TeamManager.count_in_radius(global_position, radius, GameConfig.Team.GTI)
	defenders = TeamManager.count_in_radius(global_position, radius, GameConfig.Team.HAVOC)
	contested = attackers > 0 and defenders > 0

	# 未解锁区域：强制守方
	if seg > MatchState.unlocked_segment:
		if own_team != GameConfig.Team.HAVOC:
			own_team = GameConfig.Team.HAVOC
			progress = 0.0
			_flush()
		else:
			progress = 0.0
		return

	var diff := attackers - defenders
	if diff != 0:
		progress = clampf(progress + float(diff) * RATE * delta, 0.0, 100.0)
		if progress >= 100.0 and own_team != GameConfig.Team.GTI:
			own_team = GameConfig.Team.GTI
			progress = 100.0
		elif progress <= 0.0 and own_team != GameConfig.Team.HAVOC:
			own_team = GameConfig.Team.HAVOC
			progress = 0.0
	_flush()
	queue_redraw()

func _flush() -> void:
	MatchState.apply_capture(point_id, own_team, progress, contested, attackers, defenders)

func display_progress() -> float:
	# 守方持有：显示攻方推进度（0->100 表示即将被占）
	return progress

func _draw() -> void:
	var col := GameConfig.team_color(own_team)
	# 区域填充
	draw_circle(Vector2.ZERO, radius, Color(col.r, col.g, col.b, 0.10))
	# 外圈
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(col.r, col.g, col.b, 0.7), 4.0)
	# 进度弧（从 -90° 顺时针）
	if progress > 0.5:
		var start := -PI * 0.5
		var end := start + TAU * (progress / 100.0)
		var pcol := Color("#ffd24a") if contested else col
		draw_arc(Vector2.ZERO, radius - 6.0, start, end, 64, pcol, 6.0)
	# 争夺闪烁
	if contested:
		var a := 0.35 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.006))
		draw_arc(Vector2.ZERO, radius + 6.0, 0, TAU, 64, Color(1.0, 0.82, 0.29, a), 3.0)
	# 标签
	var font := ThemeDB.fallback_font
	var label := "%s %s" % [point_id, cap_name]
	draw_string(font, Vector2(-radius, -radius - 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.94, 0.96, 0.98, 0.9))
