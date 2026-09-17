extends Node
class_name VehicleBrain
## ============================================================================
## VehicleBrain · 载具 AI
## ----------------------------------------------------------------------------
## 驾驶逻辑：无驾驶员时自动推进到前线，炮塔锁定最近敌人，主炮就开火，
## 遭到锁定/命中时自动开启主动防御（APS）。玩家进入后本 AI 停止接管。
## ============================================================================

var veh: CombatVehicle = null
var map: Node = null
var think_t: float = 0.0
var target: Node2D = null
var target_pos: Vector2 = Vector2.INF
var stuck_t: float = 0.0
var stuck_check: Vector2 = Vector2.ZERO

func _ready() -> void:
	veh = get_parent() as CombatVehicle
	map = get_tree().get_first_node_in_group("world_map")
	think_t = randf() * 0.4
	stuck_check = veh.global_position

func _physics_process(delta: float) -> void:
	if veh == null or not is_instance_valid(veh) or not veh.alive:
		return
	if veh.driver != null:
		# 玩家驾驶：交由 PlayerController 写入
		return
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.45 + randf() * 0.25
		_think()
	_drive(delta)

func _think() -> void:
	var enemy := TeamManager.nearest_visible_enemy(veh.global_position, veh.team, 1100.0)
	target = enemy
	if enemy != null:
		target_pos = enemy.global_position
	else:
		# 无敌情：推进到当前目标区域
		if veh.team == GameConfig.Team.GTI:
			var seg := clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
			target_pos = GameConfig.CAPTURES[seg * 2]["pos"]
		else:
			var best := Vector2.INF
			var best_d := 1e12
			for c in GameConfig.CAPTURES:
				var st: Dictionary = MatchState.captures[c["id"]]
				if st["attackers"] <= 0:
					continue
				var p: Vector2 = c["pos"]
				var d := veh.global_position.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = p
			target_pos = best if best != Vector2.INF else GameConfig.CAPTURES[4]["pos"]

func _drive(delta: float) -> void:
	if target_pos == Vector2.INF:
		veh.move_dir = Vector2.ZERO
		veh.want_fire = false
		return
	var to_target := target_pos - veh.global_position
	var dist := to_target.length()
	# 炮塔锁敌：只写"想要的方向"，实际转角由 CombatVehicle.aim_turret 按转速限制推进
	veh.turret_dir = to_target / maxf(dist, 0.001)
	# 车体推进到约 420 距离
	if target != null:
		veh.move_dir = to_target.normalized() if dist > 420.0 else Vector2(-to_target.y, to_target.x).normalized() * 0.4
	else:
		veh.move_dir = to_target.normalized() if dist > 260.0 else Vector2.ZERO
	veh.want_fire = target != null and dist < 1300.0
	# 卡住检测：连续不动则换个方向
	stuck_t += delta
	if stuck_t > 1.6:
		stuck_t = 0.0
		if veh.global_position.distance_to(stuck_check) < 24.0:
			veh.move_dir = veh.move_dir.rotated(randf_range(-1.2, 1.2))
		stuck_check = veh.global_position
	# 遭到步兵贴近时自动开 APS
	if veh.aps_cd <= 0.0 and veh.aps_timer <= 0.0:
		var threat := TeamManager.nearest_visible_enemy(veh.global_position, veh.team, 320.0)
		if threat != null and threat.op_class == GameConfig.OpClass.ENGINEER:
			veh.activate_aps()
