extends Node
class_name BotBrain
## ============================================================================
## BotBrain · 干员 AI
## ----------------------------------------------------------------------------
## 有限状态机：ADVANCE（推进）/ ENGAGE（交火）/ RETREAT（撤离）/ HOLD（驻守）
## 决策节流 + 寻路节流，40 个 bot 各自错开，避免同帧集中开销。
## 指挥链：指挥官 -> 小队指令 -> bot 的 HIGH-LEVEL 目标点。
## ============================================================================

enum State { ADVANCE, ENGAGE, RETREAT, HOLD }

var unit: Soldier = null
var map: Node = null

var state: int = State.ADVANCE
var target: Node2D = null
var last_known: Vector2 = Vector2.ZERO
var target_memory: float = 0.0
var avoid_pos: Vector2 = Vector2.ZERO
var avoid_timer: float = 0.0

var path := PackedVector2Array()
var path_i: int = 0
var repath_t: float = 0.0
var think_t: float = 0.0
var strafe_phase: float = 0.0
var _stuck_t: float = 0.0
var _stuck_anchor: Vector2 = Vector2.ZERO
var _last_aim: Vector2 = Vector2.RIGHT

func _ready() -> void:
	unit = get_parent() as Soldier
	map = get_tree().get_first_node_in_group("world_map")
	think_t = randf() * 0.45
	strafe_phase = randf() * TAU

func _physics_process(delta: float) -> void:
	if not MatchState.match_active:
		if unit != null:
			unit.move_dir = Vector2.ZERO
		return
	if unit == null or not is_instance_valid(unit) or not unit.alive:
		return
	# 倒地的人不做决策，也不被指挥（由流血计时与救援者决定命运）
	if unit.downed:
		unit.move_dir = Vector2.ZERO
		return
	think_t -= delta
	repath_t -= delta
	if target_memory > 0.0:
		target_memory -= delta
	if avoid_timer > 0.0:
		avoid_timer -= delta
	if think_t <= 0.0:
		think_t = 0.30 + randf() * 0.24
		_check_rescue()
		_think()
	_act(delta)

# ============================================================ 决策
## 救人：倒地的队友是一个"二十秒兵力的窟窿"，救回来等于省下一次阵亡。
## 只有支援与侦察会去救 —— 突击在前面顶线，回头救人等于把阵线让出去
func _check_rescue() -> void:
	if unit.downed:
		return
	if unit.drag_target != null:
		if unit.drag_target.downed:
			return
		unit.release_drag()
		return
	if unit.op_class != GameConfig.OpClass.SUPPORT and unit.op_class != GameConfig.OpClass.RECON:
		return
	var t: Soldier = TeamManager.nearest_downed(unit.global_position, unit.team,
		GameConfig.REVIVE_RANGE * 0.9)
	if t != null:
		unit.start_drag(t)

func _think() -> void:
	var my_pos := unit.global_position
	# --- 索敌 ---
	var vision := 780.0
	if unit.op_class == GameConfig.OpClass.RECON:
		vision = 1200.0
	elif unit.op_class == GameConfig.OpClass.ENGINEER:
		vision = 880.0
	var enemy := TeamManager.nearest_visible_enemy(my_pos, unit.team, vision)
	if enemy != null:
		target = enemy
		last_known = enemy.global_position
		target_memory = 2.6
	elif target_memory <= 0.0:
		target = null

	# --- 状态判定 ---
	var low_hp := unit.hp < unit.max_hp * 0.32
	if low_hp:
		state = State.RETREAT
	elif enemy != null or (target_memory > 0.0 and target != null and is_instance_valid(target)):
		state = State.ENGAGE
	else:
		var order := _current_order()
		if order != Vector2.INF:
			var dist := my_pos.distance_to(order)
			state = State.HOLD if dist < 85.0 else State.ADVANCE
		else:
			state = State.ADVANCE
	# --- 重算路径 ---
	if state != State.ENGAGE or target == null:
		var goal := _goal_position()
		if repath_t <= 0.0 or path.is_empty():
			repath_t = 0.8 + randf() * 0.7
			_repath(goal)

func _goal_position() -> Vector2:
	var order := _current_order()
	if order != Vector2.INF:
		return order
	var seg := clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
	# 无指令：双方都围绕「当前开放区」——攻方推未占领点，守方死守开放区
	# （已失守的前序区官方规则下守方也不再进入，这里用目标聚焦近似）
	if unit.team == GameConfig.Team.GTI:
		var best := Vector2.INF
		var best_d := 1e12
		for c in GameConfig.CAPTURES:
			if int(c["seg"]) != seg:
				continue
			if MatchState.captures[c["id"]]["owner"] == GameConfig.Team.GTI:
				continue
			var d: float = unit.global_position.distance_squared_to(c["pos"])
			if d < best_d:
				best_d = d
				best = c["pos"]
		if best != Vector2.INF:
			return best
		# 当前区已全占但尚未推进信号时，压向下一段中线
		var nxt := mini(seg + 1, GameConfig.SEGMENTS.size() - 1)
		return Vector2(GameConfig.SEGMENTS[nxt]["x"], GameConfig.BASE_POS[GameConfig.Team.GTI].y)
	else:
		var best2 := Vector2.INF
		var best_d2 := 1e12
		for c in GameConfig.CAPTURES:
			if int(c["seg"]) != seg:
				continue
			var st: Dictionary = MatchState.captures[c["id"]]
			var weight := 1.0
			if int(st["attackers"]) > 0:
				weight = 0.28
			elif int(st["owner"]) == GameConfig.Team.GTI:
				weight = 0.55
			var d2: float = unit.global_position.distance_squared_to(c["pos"]) * weight
			if d2 < best_d2:
				best_d2 = d2
				best2 = c["pos"]
		if best2 != Vector2.INF:
			return best2
		return GameConfig.BASE_POS[GameConfig.Team.HAVOC]

func _current_order() -> Vector2:
	var sq: Squad = TeamManager.squad_of(unit)
	if sq == null or sq.order_kind < 0:
		return Vector2.INF
	if sq.order_pos == Vector2.ZERO:
		return Vector2.INF
	# 防御指令：按小队偏移站开
	if sq.order_kind == GameConfig.OrderKind.DEFEND:
		var ang := float(unit.squad_id % 8) * TAU / 8.0
		return sq.order_pos + Vector2(cos(ang), sin(ang)) * 130.0
	if sq.order_kind == GameConfig.OrderKind.WARN:
		return Vector2.INF
	return sq.order_pos

var _repath_goal: Vector2 = Vector2.INF

func _repath(goal: Vector2) -> void:
	if map == null or not is_instance_valid(map):
		return
	if map.line_of_sight(unit.global_position, goal) and unit.global_position.distance_to(goal) < 700.0:
		path = PackedVector2Array([goal])
		path_i = 0
		return
	path = map.find_path(unit.global_position, goal)
	path_i = 0

# ============================================================ 执行
func _act(delta: float) -> void:
	match state:
		State.RETREAT:
			_act_retreat()
		State.ENGAGE:
			_act_engage(delta)
		State.HOLD:
			_act_hold(delta)
		_:
			_act_advance()

func _act_retreat() -> void:
	var base: Vector2 = GameConfig.BASE_POS[unit.team]
	var dir := (base - unit.global_position).normalized()
	unit.move_dir = dir
	unit.sprinting = true
	unit.aim_dir = dir.rotated(PI)
	if unit.hp < unit.max_hp * 0.9 and unit.op_class == GameConfig.OpClass.SUPPORT and unit.can_use_skill():
		unit.start_skill_cd()

func _act_engage(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		state = State.ADVANCE
		return
	var to_target := target.global_position - unit.global_position
	var d := to_target.length()
	unit.aim_dir = to_target / maxf(d, 0.001)
	_last_aim = unit.aim_dir
	# 开火 —— 略降 AI 射速，避免 40 人同时哒哒哒把音效糊成「噔噔噔」
	if d < unit.weapon["range"] and map != null and map.line_of_sight(unit.global_position, target.global_position):
		if randf() < 0.72:
			unit.try_fire()
		if unit.ammo <= 0:
			unit.start_reload()
	# 工程兵优先放巡飞弹打载具
	if unit.op_class == GameConfig.OpClass.ENGINEER and unit.can_use_skill():
		var veh := TeamManager.nearest_enemy_vehicle(unit.global_position, unit.team, 900.0)
		if veh != null:
			unit.start_skill_cd()
			if map != null and map.has_method("spawn_missile"):
				map.spawn_missile(unit, veh.global_position, veh)
	# 走位：保持理想交战距离 + 横向拉扯
	strafe_phase += delta * 1.6
	var ideal := 300.0
	if unit.op_class == GameConfig.OpClass.RECON:
		ideal = 560.0
	elif unit.op_class == GameConfig.OpClass.ENGINEER:
		ideal = 240.0
	var move := Vector2.ZERO
	if d > ideal + 60.0:
		move += to_target.normalized()
	elif d < ideal - 80.0:
		move -= to_target.normalized()
	var perp := Vector2(-to_target.y, to_target.x).normalized()
	move += perp * sin(strafe_phase) * 0.9
	var objective := _goal_position()
	if unit.team == GameConfig.Team.GTI and unit.global_position.distance_to(objective) > 105.0:
		move = move * 0.32 + (objective - unit.global_position).normalized() * 0.92
	unit.move_dir = move.normalized() if move.length() > 0.01 else Vector2.ZERO
	unit.sprinting = false

func _act_hold(delta: float) -> void:
	var goal := _goal_position()
	var to_goal := goal - unit.global_position
	if to_goal.length() > 85.0:
		_follow_path_or(goal)
	else:
		unit.move_dir = Vector2.ZERO
		unit.sprinting = false
		# 驻守时缓慢扫视 —— 限速，避免 aim_dir 每帧猛转
		strafe_phase += delta * 0.5
		var sweep := _last_aim.rotated(sin(strafe_phase) * delta * 0.35)
		if sweep.length_squared() > 0.001:
			unit.aim_dir = sweep.normalized()
			_last_aim = unit.aim_dir

func _act_advance() -> void:
	var goal := _goal_position()
	_follow_path_or(goal)

func _follow_path_or(goal: Vector2) -> void:
	# 卡住检测：想走但几乎没挪窝 → 清空路径、绕开随机偏移再寻路
	if unit.move_dir.length_squared() > 0.04:
		var moved := unit.global_position.distance_to(_stuck_anchor)
		if moved < 10.0:
			_stuck_t += get_physics_process_delta_time()
		else:
			_stuck_t = 0.0
			_stuck_anchor = unit.global_position
		if _stuck_t > 0.55:
			_stuck_t = 0.0
			_stuck_anchor = unit.global_position
			path = PackedVector2Array()
			path_i = 0
			repath_t = 0.0
			goal += Vector2(randf_range(-280.0, 280.0), randf_range(-280.0, 280.0))
			goal = goal.clamp(Vector2(80, 80), GameConfig.WORLD_SIZE - Vector2(80, 80))
	else:
		_stuck_t = 0.0
		_stuck_anchor = unit.global_position

	if map == null or not is_instance_valid(map):
		unit.move_dir = (goal - unit.global_position).normalized()
		_set_move_aim()
		return
	if path.is_empty() or path_i >= path.size():
		if repath_t <= 0.0:
			repath_t = 0.8 + randf() * 0.7
			_repath(goal)
		if path.is_empty():
			unit.move_dir = (goal - unit.global_position).normalized()
			_set_move_aim()
			return
	while path_i < path.size() and unit.global_position.distance_to(path[path_i]) < 28.0:
		path_i += 1
	if path_i >= path.size():
		path = PackedVector2Array()
		unit.move_dir = Vector2.ZERO
		return
	var dir := (path[path_i] - unit.global_position).normalized()
	unit.move_dir = dir
	unit.sprinting = unit.global_position.distance_to(goal) > 420.0 and state == State.ADVANCE
	_set_move_aim()

## 只有真的在移动时才改朝向，卡住时保持上一帧瞄准，杜绝墙角原地疯转
func _set_move_aim() -> void:
	if unit.get_real_velocity().length() < 18.0:
		unit.aim_dir = _last_aim
		return
	if unit.move_dir.length_squared() > 0.01:
		unit.aim_dir = unit.move_dir
		_last_aim = unit.aim_dir
