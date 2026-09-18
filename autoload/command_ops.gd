extends Node
## ============================================================================
## CommandOps · 指挥部系统
## ----------------------------------------------------------------------------
## 胜者为王区别于普通攻防的地方全在这里。它统管四件事：
##
##   1. 阵营积分 —— 占点、击杀、摧毁载具、完成指挥官标记都进这个池子
##   2. 指挥官专属技能 —— 高价值据点 / 高威胁载具 / 紧急增援 / 阵线增援
##   3. 重火力支援 —— 炮兵齐射 / 制导导弹，用阵营积分兑换
##   4. 工事与指挥权 —— 小队长的建造额度、弹劾与接管
##
## 为什么不做成"指挥官专属对象"：
## 指挥官会被弹劾、会掉线、会换人。把积分和冷却挂在"阵营"上而不是"某个人"上，
## 换指挥时这些资源不会凭空重置 —— 真实对局里最忌讳的就是换个人就把技能刷一遍。
##
## 阵营积分是所有决策的唯一货币：技能要花、重火力要花，所以指挥官必须取舍
## —— 是标记目标拿加分，还是直接买一轮炮兵齐射。这个取舍就是"指挥官博弈"。
## ============================================================================

## 阵营积分被动增长（每秒）。保证一局里双方都能放出几次技能，
## 不至于因为没人占点就完全用不出指挥官系统
const POINT_TRICKLE := 1.5

var points: Array = [0.0, 0.0]
## 进行中的标记：{"team","kind","id","pos","until","window","reward","label"}
var marks: Array = []
## "team:skill" -> 剩余冷却秒
var skill_cd: Dictionary = {}
var heavy_cd: Dictionary = {}
## 每方的工事建造冷却与当前工事
var fort_cd: Array = [0.0, 0.0]
var forts: Array = [null, null]
## 弹劾请求：team -> {"by","votes","need"}
var impeach: Dictionary = {}
## 指挥官在任记录（用于结算与 UI）
var cmd_name: Array = ["—", "—"]
## 各方完成的标记数（结算的"指挥能力"标签用）
var marks_done: Array = [0, 0]

func _ready() -> void:
	EventBus.match_started.connect(reset)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.capture_state_changed.connect(_on_capture_changed)
	EventBus.vehicle_destroyed.connect(_on_vehicle_destroyed)
	EventBus.commander_elected.connect(_on_commander_elected)

func reset() -> void:
	points = [0.0, 0.0]
	marks.clear()
	skill_cd.clear()
	heavy_cd.clear()
	fort_cd = [0.0, 0.0]
	forts = [null, null]
	impeach.clear()
	cmd_name = ["—", "—"]
	marks_done = [0, 0]

func _process(delta: float) -> void:
	if not MatchState.match_active:
		return
	for t in 2:
		if points[t] < 9999.0:
			points[t] += POINT_TRICKLE * delta
	for k in skill_cd.keys():
		skill_cd[k] = maxf(0.0, float(skill_cd[k]) - delta)
	for k in heavy_cd.keys():
		heavy_cd[k] = maxf(0.0, float(heavy_cd[k]) - delta)
	for t in 2:
		fort_cd[t] = maxf(0.0, fort_cd[t] - delta)
	_tick_marks()
	_poll_input()

# ============================================================ 阵营积分
func add_points(team: int, amount: float, reason: String = "") -> void:
	if amount == 0.0:
		return
	points[team] = clampf(points[team] + amount, 0.0, 9999.0)
	EventBus.faction_points_changed.emit(team, points[team], amount)
	if reason != "" and amount >= 20.0:
		EventBus.feed.emit("【阵营积分 %s+%d】%s" % [GameConfig.TEAM_NAME[team], int(amount), reason],
			GameConfig.team_color(team))

func spend_points(team: int, amount: float) -> bool:
	if points[team] < amount:
		return false
	points[team] -= amount
	EventBus.faction_points_changed.emit(team, points[team], -amount)
	return true

func _on_unit_died(victim: Node2D, killer: Node2D, _hs: bool) -> void:
	if killer == null or not is_instance_valid(killer) or killer.team == victim.team:
		return
	add_points(killer.team, 6.0)

func _on_capture_changed(point_id: String, owner: int, _progress: float, _contested: bool) -> void:
	# 占点是最主要的积分来源：这条规则把"多看点"变成指挥官的收益，而不只是胜负条件
	if owner == GameConfig.Team.GTI:
		add_points(GameConfig.Team.GTI, 40.0, "占领 " + point_id)

func _on_vehicle_destroyed(_pos: Vector2, name: String, _by_player: bool) -> void:
	# 摧毁方由 vehicle 自己结算分数，这里只给"阵营积分"
	pass

func _on_commander_elected(team: int, cmd_name_str: String, _is_player: bool, _votes: int) -> void:
	cmd_name[team] = cmd_name_str

# ============================================================ 指挥官技能
func skill_defs(team: int) -> Array:
	var out: Array = []
	for id in GameConfig.CMD_SKILLS:
		var d: Dictionary = GameConfig.CMD_SKILLS[id]
		var side: String = d["side"]
		if side == "attack" and team != GameConfig.Team.GTI:
			continue
		if side == "defend" and team != GameConfig.Team.HAVOC:
			continue
		out.append(id)
	return out

func skill_cd_left(team: int, id: String) -> float:
	return float(skill_cd.get(_key(team, id), 0.0))

func skill_cost(id: String) -> float:
	return float(GameConfig.CMD_SKILLS.get(id, {}).get("cost", 0.0))

func can_use_skill(team: int, id: String) -> bool:
	if not GameConfig.CMD_SKILLS.has(id):
		return false
	if not skill_defs(team).has(id):
		return false
	if skill_cd_left(team, id) > 0.0:
		return false
	return points[team] >= skill_cost(id)

## 释放指挥官技能。pos 为意图位置（标记类技能会就近吸附到合法目标）
func use_skill(team: int, id: String, pos: Vector2 = Vector2.INF) -> bool:
	if not can_use_skill(team, id):
		return false
	var d: Dictionary = GameConfig.CMD_SKILLS[id]
	if not spend_points(team, d["cost"]):
		return false
	var window: float = d.get("window", 60.0)
	var now := _now()
	match id:
		"vip_point":
			var cap := _nearest_capture(pos, team)
			marks.append({"team": team, "kind": "vip_point", "id": cap["id"], "pos": cap["pos"],
				"until": now + window, "reward": d["reward"], "label": "高价值据点 " + cap["id"]})
			EventBus.feed.emit("【指挥官】标记高价值据点 %s · 限时 %.0fs" % [cap["id"], window],
				Palette.MARK_GOLD)
		"threat_veh":
			var v := _nearest_enemy_vehicle(team, pos)
			if v == null:
				return false
			marks.append({"team": team, "kind": "threat_veh", "id": str(v.get_instance_id()),
				"pos": v.global_position, "until": now + window, "reward": d["reward"],
				"label": "高威胁载具"})
			EventBus.feed.emit("【指挥官】标记高威胁载具 · 全阵营可见 %.0fs" % window,
				Palette.MARK_WARN)
		"emergency":
			MatchState.fast_respawn = window
			EventBus.feed.emit("【指挥官】紧急增援 · %.0fs 内守方重部署加速" % window,
				GameConfig.TEAM_COLOR[GameConfig.Team.HAVOC])
		"reinforce":
			MatchState.free_redeploy = window
			EventBus.feed.emit("【指挥官】阵线增援 · %.0fs 内攻方重部署不扣兵力" % window,
				GameConfig.TEAM_COLOR[GameConfig.Team.GTI])
	skill_cd[_key(team, id)] = d["cd"]
	EventBus.cmd_skill_used.emit(team, id, pos)
	EventBus.cmd_skill_ready.emit(team, id, false)
	AudioManager.play_ui("announce", -2.0)
	return true

func _key(team: int, id: String) -> String:
	return "%d:%s" % [team, id]

## 挑一个最值得标记的据点。
## 攻方要"还没拿下的"，守方要"被打得最凶的" —— 同一句"高价值据点"
## 在两边指的不是同一个东西，这个函数就是把这层语义差补上
func _nearest_capture(pos: Vector2, team: int) -> Dictionary:
	if pos != Vector2.INF:
		var best: Dictionary = GameConfig.CAPTURES[0]
		var best_d := 1e12
		for c in GameConfig.CAPTURES:
			var d: float = pos.distance_squared_to(c["pos"])
			if d < best_d:
				best_d = d
				best = c
		return best
	var seg := clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
	if team == GameConfig.Team.GTI:
		for c in GameConfig.CAPTURES:
			if c["seg"] == seg and MatchState.captures[c["id"]]["owner"] != GameConfig.Team.GTI:
				return c
	# 守方：当前区域里攻方人数最多、最可能丢的那个点
	var worst: Dictionary = {}
	var worst_n := -1
	for c in GameConfig.CAPTURES:
		if c["seg"] != seg:
			continue
		var n := TeamManager.count_in_radius(c["pos"], c["radius"], GameConfig.Team.GTI)
		if n > worst_n:
			worst_n = n
			worst = c
	if not worst.is_empty():
		return worst
	return GameConfig.CAPTURES[4] if GameConfig.CAPTURES.size() > 4 else GameConfig.CAPTURES[0]

func _nearest_enemy_vehicle(team: int, pos: Vector2) -> Node2D:
	var enemy := GameConfig.Team.HAVOC if team == GameConfig.Team.GTI else GameConfig.Team.GTI
	var best: Node2D = null
	var best_d := 1e12
	for v in TeamManager.vehicles:
		if not is_instance_valid(v) or not v.alive or v.team != enemy:
			continue
		var d: float = 1e9 if pos == Vector2.INF else pos.distance_squared_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best

# ============================================================ 标记结算
## 结算规则分两类：
##   高威胁载具 —— 目标被打掉就立刻结算（奖励"集火"这个即时行为）
##   高价值据点 —— 只在窗口结束时结算。占领类目标不能即时结算，否则守方
##                 标记一个自己已经拿着的据点就是"立刻完成"，变成刷分口子。
##                 到期时归属方是标记方，才算"限时内占领或守住"。
func _tick_marks() -> void:
	var now := _now()
	for i in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		var expired: bool = float(m["until"]) <= now
		var done := false
		if m["kind"] == "threat_veh":
			done = _vehicle_gone(m["id"])
		elif expired:
			done = MatchState.captures.get(m["id"], {}).get("owner", -1) == m["team"]
		if done:
			_complete_mark(m)
			marks.remove_at(i)
		elif expired:
			# 到期未完成：不扣分，标记失效（技能冷却照常走 —— 选错目标本身就是代价）
			EventBus.feed.emit("标记目标未达成 · %s" % m["label"], Palette.UI_TEXT_DIM)
			marks.remove_at(i)

func _vehicle_gone(id: String) -> bool:
	for v in TeamManager.vehicles:
		if is_instance_valid(v) and str(v.get_instance_id()) == id:
			return not v.alive
	return true

func _complete_mark(m: Dictionary) -> void:
	add_points(m["team"], float(m["reward"]),
		"完成 %s" % m["label"])
	marks_done[m["team"]] += 1
	EventBus.mark_completed.emit(m["team"], m["kind"], m["id"], float(m["reward"]))
	EventBus.banner.emit("标记目标达成 · %s（+%d）" % [m["label"], int(m["reward"])],
		Palette.MARK_GOLD, 3.0)

## 某个位置是否被标记（HUD 画高亮圈用）
func marks_for(team: int) -> Array:
	var out: Array = []
	for m in marks:
		if m["team"] == team:
			out.append(m)
	return out

# ============================================================ 重火力支援
func heavy_cd_left(team: int, kind: String) -> float:
	return float(heavy_cd.get(_key(team, kind), 0.0))

func can_use_heavy(team: int, kind: String) -> bool:
	if not GameConfig.HEAVY_SUPPORT.has(kind):
		return false
	if heavy_cd_left(team, kind) > 0.0:
		return false
	return points[team] >= float(GameConfig.HEAVY_SUPPORT[kind]["cost"])

## 花阵营积分换一轮重火力。走的是和连杀支援同一套落弹调度，
## 所以"支援击杀不计入连杀"那条规则在这里同样成立
func use_heavy(team: int, kind: String, pos: Vector2) -> bool:
	if not can_use_heavy(team, kind):
		return false
	var d: Dictionary = GameConfig.HEAVY_SUPPORT[kind]
	if not spend_points(team, d["cost"]):
		return false
	heavy_cd[_key(team, kind)] = d["cd"]
	var shooter: Soldier = TeamManager.player if team == GameConfig.Team.GTI else null
	var shots: int = int(d["shots"])
	for i in shots:
		var off := Vector2.ZERO
		if shots > 1:
			var a := randf() * TAU
			var r: float = randf() * float(d["radius"]) * 0.6
			off = Vector2(cos(a), sin(a)) * r
		StreakManager.queue_fire_mission(pos + off, float(d["radius"]), float(d["inf"]),
			float(d["veh"]), 2.6 if kind == "missile" else 1.9, 0.7 + float(i) * 0.22, shooter)
		# 制导导弹打 C1 厂房会累计坍塌进度（烬区地图机制）
		if kind == "missile":
			MatchState.register_missile_hit(pos + off)
	EventBus.heavy_support_used.emit(team, kind, pos)
	EventBus.banner.emit("%s · 已确认弹着点" % d["name"], Palette.MARK_ATTACK, 2.6)
	EventBus.feed.emit("【指挥官】呼叫%s（-%d 积分）" % [d["name"], int(d["cost"])],
		Palette.MARK_ATTACK)
	AudioManager.play_ui("alarm", -2.0)
	return true

# ============================================================ 工事
## 只有小队长能造；攻方 80s / 守方 130s 冷却；同时最多 1 个，新建替换旧的
func fort_cd_left(team: int) -> float:
	return fort_cd[team]

func can_build_fort(team: int) -> bool:
	return fort_cd[team] <= 0.0 and MatchState.match_active

func build_fort(kind: String, builder: Soldier) -> bool:
	if builder == null or not is_instance_valid(builder):
		return false
	var team := builder.team
	if not can_build_fort(team):
		EventBus.toast.emit("工事建造冷却中 %.0fs" % fort_cd[team], Palette.UI_TEXT_DIM)
		return false
	if not GameConfig.FORTIFICATIONS.has(kind):
		return false
	var map := get_tree().get_first_node_in_group("world_map")
	if map == null:
		return false
	# 同时最多 1 个：旧的直接拆掉，而不是拒绝新建 ——
	# 阵地是会被打丢的，不允许就地换新工事的话，队长会被一个摆错位置的工事锁死
	_remove_fort(team)
	var f: Fortification = FortificationScript.new()
	map.units_root.add_child(f)
	f.setup(team, kind)
	f.global_position = builder.global_position + builder.aim_dir * 70.0
	forts[team] = f
	fort_cd[team] = float(GameConfig.FORTIFICATIONS[kind]["cd_def"]) if team == GameConfig.Team.HAVOC \
		else float(GameConfig.FORTIFICATIONS[kind]["cd_atk"])
	EventBus.fort_built.emit(team, kind, f.global_position)
	EventBus.feed.emit("%s 在小队阵地架起%s" % [
		"指挥链" if not builder.is_player else "你", GameConfig.FORTIFICATIONS[kind]["name"]],
		GameConfig.team_color(team))
	return true

func _remove_fort(team: int) -> void:
	var f = forts[team]
	if f != null and is_instance_valid(f):
		# 先摘掉 alive 再 queue_free：queue_free 要到本帧末才生效，
		# 这期间旧工事还会继续开火。阵地交接不该多打出一轮子弹
		f.alive = false
		f.queue_free()
	forts[team] = null

func on_fort_destroyed(team: int, kind: String) -> void:
	forts[team] = null
	EventBus.fort_destroyed.emit(team, kind)

# ============================================================ 指挥权
## 发起弹劾：需要 12 人同意，且发起者在局内积分排名前 10
## 这里不弹二次确认框 —— 20 人对局里"发起即表决"更接近实际节奏，
## 表决结果由当前战况与阵营成员的存活质量折算
func request_impeach(by: Soldier) -> bool:
	if by == null or not is_instance_valid(by) or not by.alive:
		return false
	var team := by.team
	if MatchState.commander_is_player(team):
		EventBus.toast.emit("你已经是本阵营指挥官", Palette.UI_TEXT_DIM)
		return false
	impeach[team] = {"by": by, "votes": 0, "need": 12}
	var votes := _count_impeach_votes(by)
	impeach[team]["votes"] = votes
	if votes < 12:
		EventBus.feed.emit("弹劾未通过 · 同意 %d / 12" % votes, Palette.MARK_WARN)
		EventBus.toast.emit("弹劾未通过 · 同意 %d / 12" % votes, Palette.MARK_WARN)
		impeach.erase(team)
		return false
	_transfer_command(team, by, "弹劾通过")
	return true

## 温和接管：申请即生效（对局里指挥官主动让权是最快的换人方式）
func request_transfer(by: Soldier) -> bool:
	if by == null or not is_instance_valid(by) or not by.alive:
		return false
	if MatchState.commander_is_player(by.team):
		EventBus.toast.emit("你已经是本阵营指挥官", Palette.UI_TEXT_DIM)
		return false
	_transfer_command(by.team, by, "申请接管")
	return true

func _transfer_command(team: int, to: Soldier, reason: String) -> void:
	MatchState.set_commander_player(team, to.is_player)
	cmd_name[team] = to.unit_name if not to.is_player else "你"
	EventBus.commander_replaced.emit(team, cmd_name[team], to.is_player)
	EventBus.banner.emit("GTI 指挥官更替 · %s（%s）" % [cmd_name[team], reason],
		GameConfig.team_color(team), 3.4)
	EventBus.feed.emit("指挥权变更 · %s" % reason, GameConfig.team_color(team))
	if to.is_player:
		EventBus.toast.emit("你已接管指挥权 · 5/6 技能 · 7/8 重火力 · B 工事", Palette.MARK_GOLD)

## 同意票的折算：指挥官越"没在做事"，同意票越多。
## 判据用三个可观测量：占据点进度差、本人存活、标记完成数
func _count_impeach_votes(by: Soldier) -> int:
	var team := by.team
	var owned := MatchState.owned_count(team)
	var opposite := MatchState.owned_count(GameConfig.Team.HAVOC if team == GameConfig.Team.GTI
		else GameConfig.Team.GTI)
	var base := 6 + (opposite - owned) * 3
	var alive := TeamManager.alive_count(team)
	base += int(float(alive) * 0.15)
	var rank_ok := by.score > 0.0
	if rank_ok:
		base += 3
	return clampi(base, 0, 20)

# ============================================================ 玩家输入
## 数字键 5/6 放技能，7/8 放重火力，B 架工事；倒地救援的 G 键在 Soldier 侧处理
func _poll_input() -> void:
	var p: Soldier = TeamManager.player
	var has_player: bool = p != null and is_instance_valid(p) and p.alive
	var target := Vector2.INF
	if has_player:
		target = p.get_global_mouse_position()

	# 架工事只需要小队长身份，不需要指挥权
	if Input.is_action_just_pressed("build_fort"):
		if not has_player:
			EventBus.toast.emit("阵亡状态无法施工", Palette.UI_TEXT_DIM)
		elif not p.is_squad_leader:
			EventBus.toast.emit("只有小队长能架设工事", Palette.UI_TEXT_DIM)
		else:
			build_fort("coastal" if p.team == GameConfig.Team.HAVOC else "bunker", p)

	if not MatchState.commander_is_player(GameConfig.Team.GTI):
		return
	if not has_player:
		return
	var ids := skill_defs(GameConfig.Team.GTI)
	if Input.is_action_just_pressed("cmd_skill_1") and ids.size() > 0:
		if not use_skill(GameConfig.Team.GTI, ids[0], target):
			EventBus.toast.emit("技能不可用 · 冷却 %.0fs / 需要 %d 积分" % [
				skill_cd_left(GameConfig.Team.GTI, ids[0]), int(skill_cost(ids[0]))], Palette.UI_TEXT_DIM)
	if Input.is_action_just_pressed("cmd_skill_2") and ids.size() > 1:
		if not use_skill(GameConfig.Team.GTI, ids[1], target):
			EventBus.toast.emit("技能不可用 · 冷却 %.0fs / 需要 %d 积分" % [
				skill_cd_left(GameConfig.Team.GTI, ids[1]), int(skill_cost(ids[1]))], Palette.UI_TEXT_DIM)
	if Input.is_action_just_pressed("heavy_1"):
		if not use_heavy(GameConfig.Team.GTI, "artillery", target):
			EventBus.toast.emit("炮兵齐射不可用 · 冷却 %.0fs / 需要 %d 积分" % [
				heavy_cd_left(GameConfig.Team.GTI, "artillery"),
				int(GameConfig.HEAVY_SUPPORT["artillery"]["cost"])], Palette.UI_TEXT_DIM)
	if Input.is_action_just_pressed("heavy_2"):
		if not use_heavy(GameConfig.Team.GTI, "missile", target):
			EventBus.toast.emit("制导导弹不可用 · 冷却 %.0fs / 需要 %d 积分" % [
				heavy_cd_left(GameConfig.Team.GTI, "missile"),
				int(GameConfig.HEAVY_SUPPORT["missile"]["cost"])], Palette.UI_TEXT_DIM)

const FortificationScript := preload("res://scripts/systems/fortification.gd")

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
