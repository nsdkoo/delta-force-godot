extends Node
class_name CommanderAI
## ============================================================================
## CommanderAI · 指挥官
## ----------------------------------------------------------------------------
## 对应真实玩法里的「指挥官系统」：分析战场 -> 决策 -> 通过小队下达指令。
## 玩家当选时本 AI 不接管，改由玩家在战术地图上下达（事件走同一条链路）。
## ============================================================================

var team: int = GameConfig.Team.GTI
var cmd_name: String = ""
var is_player: bool = false
var interval: float = 7.0
var think_t: float = 2.0
var last_mark: float = -99.0
var last_warn: float = -99.0
var last_support: float = -99.0
var active: bool = false

func setup(p_team: int, p_name: String, p_is_player: bool) -> void:
	team = p_team
	cmd_name = p_name
	is_player = p_is_player
	active = not p_is_player
	think_t = randf() * interval

func _process(delta: float) -> void:
	if not active or not MatchState.match_active:
		return
	think_t -= delta
	if think_t > 0.0:
		return
	think_t = interval + randf() * 3.0
	_decide()

# ---------------------------------------------------------------- 决策
func _decide() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if team == GameConfig.Team.GTI:
		_decide_attack(now)
	else:
		_decide_defend(now)

func _decide_attack(now: float) -> void:
	var seg := clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
	# 统计各据点兵力，挑一个"最值得打"的
	var best: Dictionary = {}
	var best_score := -1e9
	for c in GameConfig.CAPTURES:
		if c["seg"] != seg:
			continue
		if MatchState.captures[c["id"]]["owner"] == GameConfig.Team.GTI:
			continue
		var att := TeamManager.count_in_radius(c["pos"], 360.0, GameConfig.Team.GTI)
		var def := TeamManager.count_in_radius(c["pos"], 360.0, GameConfig.Team.HAVOC)
		var cpos: Vector2 = c["pos"]
		var score: float = float(att - def) * 1.5 - cpos.distance_to(GameConfig.BASE_POS[team]) * 0.002
		if score > best_score:
			best_score = score
			best = c
	if best.is_empty():
		return
	_assign_squads(GameConfig.OrderKind.ATTACK, best["pos"], "全队进攻 " + best["name"])
	if now - last_mark > 9.0:
		last_mark = now
		EventBus.order_issued.emit(team, GameConfig.OrderKind.ATTACK, best["pos"], "进攻 " + best["name"])
		if not is_player and TeamManager.player != null and TeamManager.player.team == team:
			EventBus.feed.emit("【指挥官】%s：全队进攻 %s" % [cmd_name, best["name"]], Color("#ffd24a"))
	# 发现敌方载具则点名反载具
	var veh := _find_enemy_vehicle()
	if veh != null and now - last_warn > 15.0:
		last_warn = now
		var eng_squad := _pick_squad_with_class(GameConfig.OpClass.ENGINEER)
		if eng_squad != null:
			eng_squad.set_order(GameConfig.OrderKind.ATTACK, veh.global_position, "集火敌方装甲", now)
			if not is_player and TeamManager.player != null and TeamManager.player.team == team:
				EventBus.feed.emit("【指挥官】%s：工程兵切反载具，集火敌方装甲" % cmd_name, Color("#ff9a3a"))

func _decide_defend(now: float) -> void:
	var best: Dictionary = {}
	var best_score := -1e9
	for c in GameConfig.CAPTURES:
		var st: Dictionary = MatchState.captures[c["id"]]
		var att: int = st["attackers"]
		var def: int = st["defenders"]
		var cpos2: Vector2 = c["pos"]
		var score: float = float(att - def) * 2.0
		if st["owner"] != GameConfig.Team.HAVOC:
			score += 12.0
		score -= cpos2.distance_to(GameConfig.BASE_POS[team]) * 0.001
		if score > best_score:
			best_score = score
			best = c
	if best.is_empty():
		return
	_assign_squads(GameConfig.OrderKind.DEFEND, best["pos"], "坚守 " + best["name"])
	if now - last_mark > 10.0:
		last_mark = now
		EventBus.order_issued.emit(team, GameConfig.OrderKind.DEFEND, best["pos"], "防守 " + best["name"])
		if not is_player and TeamManager.player != null and TeamManager.player.team == team:
			EventBus.feed.emit("【指挥官】%s：小队回防 %s" % [cmd_name, best["name"]], Color("#8fc4ff"))

# ---------------------------------------------------------------- 指令下发
func _assign_squads(kind: int, pos: Vector2, label: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var squads := TeamManager.squads_of_team(team)
	for i in squads.size():
		var sq: Squad = squads[i]
		if sq.size_alive() == 0:
			continue
		var offset := Vector2.ZERO
		if kind == GameConfig.OrderKind.DEFEND:
			var a := float(i) * TAU / maxf(1.0, float(squads.size()))
			offset = Vector2(cos(a), sin(a)) * 150.0
		elif i % 3 == 2:
			offset = Vector2(0, -260)   # 侧翼
		sq.set_order(kind, pos + offset, label, now)

func _find_enemy_vehicle() -> Node2D:
	var enemy_team := GameConfig.Team.HAVOC if team == GameConfig.Team.GTI else GameConfig.Team.GTI
	for v in TeamManager.vehicles:
		if is_instance_valid(v) and v.alive and v.team == enemy_team:
			return v
	return null

func _pick_squad_with_class(op_class: int) -> Squad:
	var best: Squad = null
	var best_n := -1
	for sq in TeamManager.squads_of_team(team):
		var n := 0
		for m in sq.alive_members():
			if m.op_class == op_class:
				n += 1
		if n > best_n:
			best_n = n
			best = sq
	return best
