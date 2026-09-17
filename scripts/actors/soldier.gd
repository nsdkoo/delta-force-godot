class_name Soldier
extends CharacterBody2D
## ============================================================================
## Soldier · 干员
## ----------------------------------------------------------------------------
## 承载：身份 / 属性 / 武器 / 技能 / 移动 / 射击 / 受伤 / 阵亡 / 重生。
## 不含任何 AI 逻辑（由 BotBrain 驱动），不含任何 UI（由 EventBus 通知 HUD）。
## ============================================================================

const BulletScene := preload("res://scenes/projectiles/Bullet.tscn")

# ---------------------------------------------------------------- 身份
var team: int = GameConfig.Team.GTI
var op_class: int = GameConfig.OpClass.ASSAULT
var unit_name: String = ""
var is_player: bool = false
var is_bot: bool = true
var squad_id: int = 0
var is_squad_leader: bool = false
var is_commander: bool = false

# ---------------------------------------------------------------- 状态
var alive: bool = true
var hp: float = 100.0
var max_hp: float = 100.0
var respawn_timer: float = 0.0
var spawn_protection: float = 0.0
var speed_scale: float = 1.0

# ---------------------------------------------------------------- 武器
var weapon_id: String = "ar"
var weapon: Dictionary = {}
var ammo: int = 30
var reserve: int = 240
var is_reloading: bool = false
var reload_left: float = 0.0
var fire_cd: float = 0.0
var spread_heat: float = 0.0
var aim_dir: Vector2 = Vector2.RIGHT
var move_dir: Vector2 = Vector2.ZERO
var sprinting: bool = false
var aiming_down_sight: bool = false

# ---------------------------------------------------------------- 技能
var skill_cd: float = 0.0
var field_med_cd: float = 0.0
var in_vehicle: Node2D = null

# ---------------------------------------------------------------- 统计
var kills: int = 0
var deaths: int = 0
var damage_done: float = 0.0
var score: float = 0.0

# ---------------------------------------------------------------- 视觉
var body: Sprite2D
var info: Node2D
var _spawn_point: Vector2 = Vector2.ZERO
var _hit_flash: float = 0.0

signal died(victim: Soldier, killer: Soldier, headshot: bool)

func _ready() -> void:
	body = $Body
	info = $Info
	_apply_operator()
	# 碰撞：与建筑和敌方单位碰撞，同队不互相推挤
	collision_layer = GameConfig.team_layer(team)
	collision_mask = GameConfig.Layer.WORLD
	collision_mask |= GameConfig.Layer.TEAM_GTI if team == GameConfig.Team.HAVOC else GameConfig.Layer.TEAM_HAVOC
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	TeamManager.register_unit(self)
	info.draw.connect(_draw_info)
	EventBus.unit_spawned.emit(self)

# ---------------------------------------------------------------- 初始化
## 由生成器调用：配置兵种与身份
func setup(p_team: int, p_class: int, p_name: String, p_is_player: bool = false) -> void:
	team = p_team
	op_class = p_class
	unit_name = p_name
	is_player = p_is_player
	is_bot = not p_is_player
	_apply_operator()

func _apply_operator() -> void:
	var op: Dictionary = GameConfig.OPERATORS[op_class]
	weapon_id = op["weapon"]
	weapon = GameConfig.WEAPONS[weapon_id]
	max_hp = op["hp"]
	if alive:
		hp = max_hp
	speed_scale = op["speed"]
	ammo = weapon["mag"]
	reserve = weapon["reserve"]
	if body != null:
		var tex := AssetDB.operator_texture_for(op_class)
		if tex != null:
			body.texture = tex
			var k := AssetDB.OPERATOR_DRAW_WIDTH / float(tex.get_width())
			body.scale = Vector2(k, k)
		body.modulate = _tint_for_team()

func _tint_for_team() -> Color:
	if team == GameConfig.Team.GTI:
		return Color(0.78, 0.88, 1.0)
	return Color(1.0, 0.78, 0.72)

# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if not alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_do_respawn()
		return

	if spawn_protection > 0.0:
		spawn_protection -= delta
	if fire_cd > 0.0:
		fire_cd -= delta
	if spread_heat > 0.0:
		spread_heat = maxf(0.0, spread_heat - delta * 2.0)
	if skill_cd > 0.0:
		skill_cd -= delta
	if field_med_cd > 0.0:
		field_med_cd -= delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 4.0)
		body.modulate = _tint_for_team().lerp(Color(1, 0.4, 0.35), _hit_flash)

	_tick_reload(delta)
	# 移动由外部（玩家输入 / AI）写入 move_dir
	var spd := 200.0 * speed_scale
	if sprinting:
		spd *= 1.42
	if aiming_down_sight:
		spd *= 0.58
	velocity = move_dir * spd
	move_and_slide()
	# 朝向：始终朝瞄准方向
	if aim_dir.length_squared() > 0.001:
		rotation = aim_dir.angle()
	info.queue_redraw()

func _tick_reload(delta: float) -> void:
	if not is_reloading:
		return
	reload_left -= delta
	if reload_left <= 0.0:
		var need := mini(weapon["mag"] - ammo, reserve)
		ammo += need
		reserve -= need
		is_reloading = false

# ---------------------------------------------------------------- 射击
func can_fire() -> bool:
	return alive and fire_cd <= 0.0 and ammo > 0 and not is_reloading

func try_fire() -> bool:
	if not can_fire():
		if ammo <= 0 and not is_reloading:
			start_reload()
		return false
	var spread := _current_spread()
	var dir := aim_dir.rotated(deg_to_rad(randf_range(-spread, spread)))
	var muzzle: Vector2 = $Muzzle.global_position
	var root := get_tree().get_first_node_in_group("projectiles_root")
	if root == null:
		root = get_tree().current_scene
	var b := BulletScene.instantiate()
	root.add_child(b)
	b.setup(team, self, muzzle, dir, weapon)
	ammo -= 1
	fire_cd = 60.0 / weapon["rpm"]
	spread_heat = minf(1.0, spread_heat + weapon["recoil"])
	EventBus.shot_fired.emit(self, muzzle, dir, weapon_id)
	AudioManager.play_2d("shot_" + weapon_id, muzzle,
		AudioManager.volume_for(muzzle, _listener_pos()))
	return true

func _current_spread() -> float:
	var base: float = weapon["spread_deg"]
	var k := 1.0 + spread_heat * 1.7
	if sprinting:
		k *= 1.7
	if aiming_down_sight:
		k *= 0.38
	return base * k

func _listener_pos() -> Vector2:
	if TeamManager.player != null and is_instance_valid(TeamManager.player):
		return TeamManager.player.global_position
	return global_position

func start_reload() -> void:
	if is_reloading or reserve <= 0 or ammo >= weapon["mag"]:
		return
	is_reloading = true
	reload_left = weapon["reload"]
	AudioManager.play_2d("reload_a", global_position, AudioManager.volume_for(global_position, _listener_pos(), 200.0, 700.0))

# ---------------------------------------------------------------- 受伤 / 阵亡
func take_damage(amount: float, attacker: Soldier, headshot: bool = false) -> void:
	if not alive or spawn_protection > 0.0:
		return
	hp -= amount
	_hit_flash = 1.0
	if attacker != null and attacker.team != team:
		attacker.damage_done += amount
	if is_player:
		var dir := 0.0
		if attacker != null:
			dir = (attacker.global_position - global_position).angle()
		EventBus.player_hurt.emit(dir, clampf(amount / 60.0, 0.1, 1.0))
		AudioManager.play_ui("hurt", -8.0)
	EventBus.unit_damaged.emit(self, amount, attacker)
	if hp <= 0.0:
		_die(attacker, headshot)

func _die(killer: Soldier, headshot: bool) -> void:
	alive = false
	deaths += 1
	hp = 0.0
	respawn_timer = GameConfig.RESPAWN_DELAY
	velocity = Vector2.ZERO
	move_dir = Vector2.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	MatchState.spend_ticket(team)
	if killer != null and killer.team != team:
		killer.kills += 1
		killer.score += 100.0
		if killer.is_player:
			EventBus.hitmarker.emit(headshot, true, 0.0)
	var txt := "%s 击倒 %s%s" % [
		"—" if killer == null else ("你" if killer.is_player else killer.unit_name),
		"你" if is_player else unit_name,
		"〔爆头〕" if headshot else ""]
	EventBus.kill_feed.emit(txt, GameConfig.team_color(team) if killer != null and killer.team == team else Color("#ff9a8a"))
	EventBus.unit_died.emit(self, killer, headshot)
	died.emit(self, killer, headshot)
	if is_player:
		EventBus.player_death.emit(GameConfig.RESPAWN_DELAY)
	AudioManager.play_2d("boom_small", global_position, -12.0)

func _do_respawn() -> void:
	var base: Vector2 = GameConfig.BASE_POS[team]
	# 优先在己方控制的据点附近重生
	var owned: Array = []
	for c in GameConfig.CAPTURES:
		if MatchState.captures[c["id"]]["owner"] == team:
			owned.append(c["pos"])
	var pos := base
	if not owned.is_empty() and randf() < 0.72:
		pos = owned[randi() % owned.size()] + Vector2(randf_range(-90, 90), randf_range(-90, 90))
	else:
		pos = base + Vector2(0, randf_range(-320, 320))
	global_position = pos.clamp(Vector2(60, 60), GameConfig.WORLD_SIZE - Vector2(60, 60))
	alive = true
	hp = max_hp
	ammo = weapon["mag"]
	reserve = weapon["reserve"]
	is_reloading = false
	spawn_protection = 1.6
	visible = true
	collision_layer = GameConfig.team_layer(team)
	collision_mask = GameConfig.Layer.WORLD | (GameConfig.Layer.TEAM_GTI if team == GameConfig.Team.HAVOC else GameConfig.Layer.TEAM_HAVOC)
	body.modulate = _tint_for_team()
	if is_player:
		EventBus.player_respawned.emit(self)

# ---------------------------------------------------------------- 技能
func can_use_skill() -> bool:
	return alive and skill_cd <= 0.0

func start_skill_cd() -> void:
	skill_cd = GameConfig.OPERATORS[op_class]["skill_cd"]

# ---------------------------------------------------------------- 信息绘制
func _draw_info() -> void:
	if not alive:
		return
	var w := 30.0
	var h := 4.0
	# 血条
	info.draw_rect(Rect2(-w * 0.5, -30, w, h), Color(0, 0, 0, 0.62), true)
	var k := clampf(hp / max_hp, 0.0, 1.0)
	var col := Color("#57e08a")
	if k < 0.3:
		col = Color("#ff5b4a")
	elif k < 0.6:
		col = Color("#ffd24a")
	info.draw_rect(Rect2(-w * 0.5, -30, w * k, h), col, true)
	# 我方标识
	var is_ally: bool = TeamManager.player != null and team == TeamManager.player.team
	if is_ally:
		if is_squad_leader:
			info.draw_string(ThemeDB.fallback_font, Vector2(-6, -34), "▲", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color("#9fb3c2"))
		if is_commander:
			info.draw_string(ThemeDB.fallback_font, Vector2(-7, -34), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color("#ffd24a"))
		if not is_player:
			info.draw_string(ThemeDB.fallback_font, Vector2(-30, -38), unit_name, HORIZONTAL_ALIGNMENT_LEFT, 60, 11,
				Color(0.78, 0.86, 0.92, 0.8))
	if spawn_protection > 0.0:
		info.draw_arc(Vector2.ZERO, 22, 0, TAU, 20, Color(1, 1, 1, 0.5), 2.0)
