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
	# 指挥部的活：放技能、买重火力、架工事。
	# 玩家接管之后这三件事全部交给玩家，AI 不抢 —— 否则玩家刚买的重火力
	# 会被 AI 在同一秒花掉，指挥权就名存实亡了
	if not is_player and not MatchState.commander_is_player(team):
		_decide_ops(now)
		_try_build_fort(now)

## 指挥部决策：优先标记类技能（能换分），积分富余再买重火力
func _decide_ops(_now: float) -> void:
	var ids := CommandOps.skill_defs(team)
	for id in ["vip_point", "threat_veh", "reinforce", "emergency"]:
		if ids.has(id) and CommandOps.can_use_skill(team, id):
			CommandOps.use_skill(team, id, Vector2.INF)
			return
	if CommandOps.points[team] < 380.0:
		return
	var hot := _hottest_point()
	if hot == Vector2.INF:
		return
	if CommandOps.can_use_heavy(team, "missile"):
		CommandOps.use_heavy(team, "missile", hot)
	elif CommandOps.can_use_heavy(team, "artillery"):
		CommandOps.use_heavy(team, "artillery", hot)

## 当前最需要火力覆盖的位置：攻方打"正在争夺的点"，守方打"被压得最狠的点"
func _hottest_point() -> Vector2:
	var best := Vector2.INF
	var best_n := 0
	for c in GameConfig.CAPTURES:
		var enemy := GameConfig.Team.HAVOC if team == GameConfig.Team.GTI else GameConfig.Team.GTI
		var n := TeamManager.count_in_radius(c["pos"], c["radius"] + 40.0, enemy)
		if n > best_n:
			best_n = n
			best = c["pos"]
	return best if best_n >= 3 else Vector2.INF

## 小队长架工事：守方架在被打的据点圈内，攻方架在自己正在推进的方向上。
## 冷却 80/130 秒由 CommandOps 统一管，这里只负责在能建的时候挑个好位置
func _try_build_fort(_now: float) -> void:
	if not CommandOps.can_build_fort(team):
		return
	var squads := TeamManager.squads_of_team(team)
	if squads.is_empty():
		return
	var sq: Squad = squads[randi() % squads.size()]
	var ld: Soldier = sq.active_leader()
	if ld == null or not ld.alive:
		return
	# 工事种类按阵营分工：攻方要压制，守方要反装甲与防空
	var kinds: Array = ["bunker", "vulcan"] if team == GameConfig.Team.GTI else ["coastal", "aa"]
	CommandOps.build_fort(kinds[randi() % kinds.size()], ld)

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
