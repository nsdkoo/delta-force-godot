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
var respawn_timer: float = 0.0
var _data: Dictionary = {}
var _body: Sprite2D
var _turret: Sprite2D
var _trail_t: float = 0.0

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
	if absf(GameConfig.angle_wrap(turret_angle - (turret_dir.angle()))) > 0.12:
		return
	fire_cd = _data["reload"]
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
	var enemy := TeamManager.nearest_visible_enemy(global_position, team, 900.0)
	if enemy == null:
		return
	var dir := (enemy.global_position - global_position).normalized()
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
	if driver != null:
		driver.in_vehicle = null
		driver = null
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

## 玩家进出载具
func enter(p: Soldier) -> void:
	driver = p
	p.in_vehicle = self
	p.visible = false

func exit_vehicle() -> void:
	if driver != null:
		driver.global_position = global_position + Vector2(0, radius + 26.0)
		driver.visible = true
		driver.in_vehicle = null
		driver = null
