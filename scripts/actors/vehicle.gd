class_name CombatVehicle
extends CharacterBody2D
## ============================================================================
## Vehicle · 载具
## ----------------------------------------------------------------------------
## 主战坦克 / 装甲车。车体与炮塔独立朝向；主炮两种弹种；主动防御系统(APS)
## 可拦截来袭飞弹（对应真实玩法里"没有完全体别开出门"的设定）。
## ============================================================================

enum Kind { TANK, APC }

var team: int = GameConfig.Team.GTI
var kind: int = Kind.TANK
var alive: bool = true
var hp: float = 3200.0
var max_hp: float = 3200.0
var radius: float = 40.0

var move_dir: Vector2 = Vector2.ZERO
var turret_dir: Vector2 = Vector2.RIGHT
var body_angle: float = 0.0
var turret_angle: float = 0.0

var fire_cd: float = 0.0
var mg_cd: float = 0.0
var aps_timer: float = 0.0
var aps_cd: float = 0.0
var want_fire: bool = false
var ammo_mode: int = 0            ## 0=穿甲弹 1=高爆弹
var driver: Soldier = null
var manual_gun: bool = false      ## 玩家驾驶时由 PlayerController 置位：机枪改为手动瞄准
var ammo_switch_cd: float = 0.0   ## 切弹种的装填锁，避免一键在两种弹之间来回刷
var shots: int = 0                ## 主炮发射计数（计分板与自检用）
var mg_shots: int = 0             ## 机枪发射计数
var respawn_timer: float = 0.0
var _data: Dictionary = {}
var _body: Sprite2D
var _turret: Sprite2D
var _trail_t: float = 0.0

## 炮塔最大转速（弧度/秒）。约 150°/s —— 正面遭遇完全够用，
## 但被绕到侧后就追不上，这正是"侧翼包抄"能成立的原因。
const TURRET_SLEW := 2.6
## 切换弹种的装填锁
const AMMO_SWITCH_TIME := 1.2

const MissileScript := preload("res://scripts/projectiles/missile.gd")

func setup(p_team: int, p_kind: int) -> void:
	team = p_team
	kind = p_kind

func _ready() -> void:
	_data = GameConfig.VEHICLES[GameConfig.VehKind.TANK if kind == Kind.TANK else GameConfig.VehKind.APC]
	max_hp = _data["hp"]
	hp = max_hp
	radius = _data["radius"]
	body_angle = 0.0 if team == GameConfig.Team.GTI else PI
	turret_angle = body_angle
	collision_layer = GameConfig.Layer.VEHICLE
	collision_mask = GameConfig.Layer.WORLD | GameConfig.Layer.VEHICLE
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_build_visual()
	TeamManager.register_vehicle(self)
	EventBus.feed.emit("%s 载具已就位" % GameConfig.TEAM_NAME[team], GameConfig.team_color(team))

func _build_visual() -> void:
	var kind_key := "tank" if kind == Kind.TANK else "apc"
	_body = Sprite2D.new()
	_body.texture = AssetDB.vehicle_body(kind_key, team)
	_body.rotation = PI * 0.5            ## 素材车头朝上，转 90° 对齐 ang=0 朝右
	_apply_scale(_body, radius * 2.05)
	add_child(_body)
	_turret = Sprite2D.new()
	_turret.texture = AssetDB.vehicle_turret(kind_key, team)
	_turret.rotation = PI * 0.5
	_apply_scale(_turret, radius * 0.74)
	add_child(_turret)
	var shape := CircleShape2D.new()
	shape.radius = radius * 0.86
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

func _apply_scale(sp: Sprite2D, target_w: float) -> void:
	if sp.texture == null:
		return
	var k := target_w / float(sp.texture.get_width())
	sp.scale = Vector2(k, k)

# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if not alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_do_respawn()
		return
	if fire_cd > 0.0:
		fire_cd -= delta
	if mg_cd > 0.0:
		mg_cd -= delta
	if aps_timer > 0.0:
		aps_timer -= delta
	if aps_cd > 0.0:
		aps_cd -= delta
	if ammo_switch_cd > 0.0:
		ammo_switch_cd -= delta

	# 炮塔按限速追目标方向。注意是"追"不是"赋值"：
	# 直接 turret_angle = turret_dir.angle() 会让炮塔瞬间对准任何方向，
	# 侧翼包抄就失去了意义。
	aim_turret(turret_dir, delta)

	var speed: float = _data["speed"]
	velocity = move_dir * speed
	if move_dir.length_squared() > 0.01:
		body_angle = GameConfig.angle_lerp(body_angle, move_dir.angle(), delta * 1.7)
		if _trail_t <= 0.0:
			_trail_t = 0.09
	move_and_slide()
	rotation = body_angle
	_turret.rotation = turret_angle - body_angle + PI * 0.5
	if _trail_t > 0.0:
		_trail_t -= delta

	# 乘员跟着车走。这一步不能省 —— 据点占领、索敌、AI 选目标全都按
	# global_position 算半径。车上的人如果留在上车点，他会在原地"占点"，
	# 而敌人会朝一个空位置开枪。
	if driver != null and is_instance_valid(driver):
		driver.global_position = global_position

	# 碾压步兵
	for u in TeamManager.alive_units():
		if u.team == team:
			continue
		if global_position.distance_to(u.global_position) < radius + 8.0:
			u.take_damage(140.0 * delta * 6.0, driver)

	if want_fire:
		_try_main_gun()
		_try_mg()

func _try_main_gun() -> void:
	if fire_cd > 0.0:
		return
	# 炮口没对上就打不出去 —— 炮塔有转速限制，所以"被绕侧"是真的打不到人
	if not turret_ready():
		return
	fire_cd = _data["reload"]
	shots += 1
	EventBus.explosion.emit(global_position + turret_dir * (radius + 10.0), 1.2, "muzzle")
	AudioManager.play_2d("shot_cannon", global_position,
		AudioManager.volume_for(global_position, _listener(), 400.0, 2600.0))
	# 用射线判定主炮命中
	var from := global_position + turret_dir * (radius + 10.0)
	var to := from + turret_dir * 1400.0
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = GameConfig.Layer.WORLD | _enemy_layer() | GameConfig.Layer.VEHICLE
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var impact := to
	if not hit.is_empty():
		impact = hit.position
		var col = hit.collider
		if col is CombatVehicle:
			col.take_damage(_data["cannon_damage"], driver)
		elif col is Soldier:
			col.take_damage(_data["cannon_infantry"], driver)
	_splash(impact)

func _splash(center: Vector2) -> void:
	EventBus.explosion.emit(center, 2.0, "boom")
	AudioManager.play_2d("boom_big", center, AudioManager.volume_for(center, _listener(), 500.0, 3000.0))
	var inf: float = _data["cannon_infantry"] * (1.0 if ammo_mode == 1 else 0.7)
	for u in TeamManager.alive_units():
		if u.team == team:
			continue
		var d := center.distance_to(u.global_position)
		if d < _data["splash"]:
			u.take_damage(inf * (1.0 - d / _data["splash"]), driver)
	for v in TeamManager.vehicles:
		if is_instance_valid(v) and v.alive and v.team != team:
			if center.distance_to(v.global_position) < _data["splash"] + 30.0:
				v.take_damage(_data["cannon_damage"] * 0.35, driver)

func _try_mg() -> void:
	if mg_cd > 0.0:
		return
	mg_cd = 0.09
	var dir: Vector2
	if manual_gun:
		# 玩家驾驶：机枪跟随炮塔朝向手动点射，不做自动索敌
		if not turret_ready(0.25):
			return
		dir = turret_dir
	else:
		var enemy := TeamManager.nearest_visible_enemy(global_position, team, 900.0)
		if enemy == null:
			return
		dir = (enemy.global_position - global_position).normalized()
	mg_shots += 1
	EventBus.shot_fired.emit(self, global_position + dir * radius, dir, "mg_veh")
	# 机枪：命中判定走一次射线
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position + dir * radius,
		global_position + dir * radius + dir * 900.0)
	q.collision_mask = GameConfig.Layer.WORLD | _enemy_layer()
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.collider is Soldier:
		hit.collider.take_damage(_data["mg_damage"], driver)
	AudioManager.play_2d("shot_mg_veh", global_position, -14.0)

func _enemy_layer() -> int:
	return GameConfig.Layer.TEAM_HAVOC if team == GameConfig.Team.GTI else GameConfig.Layer.TEAM_GTI

func _listener() -> Vector2:
	if TeamManager.player != null and is_instance_valid(TeamManager.player):
		return TeamManager.player.global_position
	return global_position

# ---------------------------------------------------------------- 炮塔 / 弹种
## 把炮塔朝 dir 转过去，单帧转角不超过 TURRET_SLEW * delta
func aim_turret(dir: Vector2, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var diff := GameConfig.angle_wrap(dir.angle() - turret_angle)
	turret_angle = wrapf(turret_angle + clampf(diff, -TURRET_SLEW * delta, TURRET_SLEW * delta), -PI, PI)

## 炮口是否已经对上来袭方向（主炮开火的唯一前置条件）
func turret_ready(tolerance: float = 0.12) -> bool:
	return absf(GameConfig.angle_wrap(turret_angle - turret_dir.angle())) <= tolerance

## 切换弹种。有装填锁，否则战斗中 1/2 连按可以绕过主炮的 6.5 秒装填
func switch_ammo(mode: int) -> bool:
	if not alive or ammo_switch_cd > 0.0 or mode == ammo_mode:
		return false
	ammo_mode = mode
	ammo_switch_cd = AMMO_SWITCH_TIME
	fire_cd = maxf(fire_cd, AMMO_SWITCH_TIME)
	EventBus.feed.emit("%s 装填%s" % [display_name(), "高爆弹" if mode == 1 else "穿甲弹"],
		Color("#ffc24a") if mode == 1 else Color("#8fc4ff"))
	AudioManager.play_2d("reload_b", global_position, -4.0)
	return true

func ammo_label() -> String:
	return "高爆弹" if ammo_mode == 1 else "穿甲弹"

func display_name() -> String:
	return _data.get("name", "载具")

func kind_key() -> String:
	return "tank" if kind == Kind.TANK else "apc"

# ---------------------------------------------------------------- APS
func activate_aps() -> bool:
	if aps_timer > 0.0 or aps_cd > 0.0 or not alive:
		return false
	aps_timer = GameConfig.APS_DURATION
	aps_cd = GameConfig.APS_COOLDOWN
	EventBus.feed.emit("主动防御系统启动 · %.0fs" % GameConfig.APS_DURATION, Color("#8fc4ff"))
	AudioManager.play_2d("ui_up", global_position, -6.0)
	return true

func aps_active() -> bool:
	return alive and aps_timer > 0.0

# ---------------------------------------------------------------- 损伤
func take_damage(amount: float, attacker: Soldier) -> void:
	if not alive:
		return
	if aps_timer > 0.0:
		# APS 生效期间吸收飞弹类伤害
		if amount >= 200.0:
			EventBus.feed.emit("主动防御拦截来袭飞弹", Color("#8fc4ff"))
			return
	hp -= amount
	if attacker != null and attacker.team != team:
		attacker.damage_done += amount
		if attacker.is_player:
			EventBus.hitmarker.emit(false, hp <= 0.0, amount)
	if hp <= 0.0:
		_destroy(attacker)

func _destroy(attacker: Soldier) -> void:
	alive = false
	hp = 0.0
	respawn_timer = 22.0
	visible = false
	collision_layer = 0
	collision_mask = 0
	# 乘员要真正被抛出去。这里不能只把 driver 置空 ——
	# 那样玩家会以"隐形 + 零碰撞"的状态留在原地，再也回不到战场上。
	if driver != null:
		var crew: Soldier = driver
		exit_vehicle()
		## 载具被毁不等于乘员阵亡：重伤留一口气，而不是直接判死
		crew.take_damage(minf(70.0, maxf(0.0, crew.hp - 1.0)), attacker)
	EventBus.explosion.emit(global_position, 2.8, "boom")
	EventBus.vehicle_destroyed.emit(global_position, _data["name"],
		attacker != null and attacker.is_player)
	EventBus.feed.emit("%s 摧毁 %s" % ["你" if attacker != null and attacker.is_player else "—", _data["name"]],
		Color("#ffc24a"))
	if attacker != null:
		attacker.score += 250.0

func _do_respawn() -> void:
	var base: Vector2 = GameConfig.BASE_POS[team]
	global_position = base + Vector2((60.0 if team == GameConfig.Team.GTI else -60.0),
		randf_range(-120.0, 120.0))
	alive = true
	hp = max_hp
	aps_timer = 0.0
	aps_cd = 0.0
	fire_cd = 0.0
	visible = true
	collision_layer = GameConfig.Layer.VEHICLE
	collision_mask = GameConfig.Layer.WORLD | GameConfig.Layer.VEHICLE

# ---------------------------------------------------------------- 乘员
## 玩家进出载具
func enter(p: Soldier) -> bool:
	if not alive or driver != null or p == null or not p.alive:
		return false
	# 一个人只能在一辆车里：否则会出现两辆车同时记着同一个驾驶员
	if p.in_vehicle != null:
		return false
	driver = p
	p.in_vehicle = self
	p.visible = false
	# 乘员退出物理世界：否则车上会留下一个看不见的碰撞体，挡人挡枪挡射线
	p.park_for_vehicle()
	# 上车瞬间炮塔对齐车头，避免沿用上一任驾驶员的朝向
	turret_dir = Vector2.from_angle(body_angle)
	p.aim_dir = turret_dir
	AudioManager.play_2d("ui_up", global_position, -2.0)
	EventBus.feed.emit("已进入 %s" % display_name(), GameConfig.team_color(team))
	return true

func exit_vehicle() -> void:
	if driver == null:
		return
	var p: Soldier = driver
	driver = null
	p.in_vehicle = null
	p.global_position = _eject_position()
	p.visible = true
	p.aim_dir = turret_dir
	p.restore_physics()
	EventBus.feed.emit("已离开 %s" % display_name(), Color("#8fc4ff"))

## 下车落点：优先找四个方向里第一个可站人的位置。
## 直接写死"车下方 26 像素"在贴墙停车时会把下车的人塞进建筑里。
func _eject_position() -> Vector2:
	var map := get_tree().get_first_node_in_group("world_map")
	var d := radius + 30.0
	var candidates := [Vector2(0, d), Vector2(0, -d), Vector2(d, 0), Vector2(-d, 0)]
	for c in candidates:
		var p: Vector2 = global_position + c
		if p.x < 40.0 or p.y < 40.0 or p.x > GameConfig.WORLD_SIZE.x - 40.0 or p.y > GameConfig.WORLD_SIZE.y - 40.0:
			continue
		if map != null and map.has_method("is_walkable") and not map.is_walkable(p):
			continue
		return p
	return global_position + Vector2(0, d)

func has_player_driver() -> bool:
	return driver != null and driver.is_player
