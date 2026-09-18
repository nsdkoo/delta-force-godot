extends Node2D
## ============================================================================
## Bullet · 弹道
## ----------------------------------------------------------------------------
## 用物理射线做逐帧扫掠（swept raycast），高速子弹不会穿透目标。
## 命中判定：墙体 / 敌方干员 / 敌方载具。
## ============================================================================

const HEADSHOT_CHANCE := 0.13

var team: int = GameConfig.Team.GTI
var shooter: Soldier = null
var dir: Vector2 = Vector2.RIGHT
var speed: float = 1500.0
var damage: float = 17.0
var life: float = 1.4
var weapon_id: String = "ar"
var _prev: Vector2 = Vector2.ZERO

func setup(p_team: int, p_shooter: Soldier, from: Vector2, p_dir: Vector2, weapon: Dictionary) -> void:
	team = p_team
	shooter = p_shooter
	global_position = from
	_prev = from
	dir = p_dir.normalized()
	speed = weapon["speed"]
	damage = weapon["damage"]
	weapon_id = weapon.get("key", "ar")

func _ready() -> void:
	z_index = 5
	rotation = dir.angle()

func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + dir * speed * delta
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = GameConfig.Layer.WORLD | _enemy_layer() | GameConfig.Layer.VEHICLE
	q.collide_with_areas = false
	if shooter != null and is_instance_valid(shooter):
		q.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		_on_hit(hit)
		return
	_prev = global_position
	global_position = to
	life -= delta
	if life <= 0.0:
		queue_free()

func _enemy_layer() -> int:
	return GameConfig.Layer.TEAM_HAVOC if team == GameConfig.Team.GTI else GameConfig.Layer.TEAM_GTI

func _on_hit(hit: Dictionary) -> void:
	var col = hit.collider
	var pos: Vector2 = hit.position
	if col is Soldier:
		var head := randf() < HEADSHOT_CHANCE
		var dmg := damage * (1.9 if head else 1.0)
		var lethal: bool = col.hp <= dmg
		col.take_damage(dmg, shooter, head)
		if shooter != null and shooter.is_player:
			EventBus.hitmarker.emit(head, lethal, dmg)
		AudioManager.play_2d("hit_head" if head else "hit_flesh", pos,
			AudioManager.volume_for(pos, _listener()))
		EventBus.impact.emit(pos, hit.get("normal", Vector2.UP), "flesh")
	elif col is Node2D and col.has_method("take_damage"):
		# 默认 15%：载具是装甲目标，枪械只能磨。工事这类"该被打掉的东西"
		# 自己声明 bullet_damage_scale = 1.0 拿满伤害
		var scale := 0.15
		if "bullet_damage_scale" in col:
			scale = col.bullet_damage_scale
		# 空中目标单独一套：它是薄皮但难打中，普通枪械效率很低，
		# 狙击枪是唯一能"空摘飞行员"的枪械（对应文档里的空摘成就）
		if col is CombatVehicle and col.is_air:
			scale = 1.8 if weapon_id == "sniper" else 0.7
		# 工程兵的反载具加成：打载具时伤害上浮
		if col is CombatVehicle and shooter != null and is_instance_valid(shooter) 				and shooter.has_method("has_at_boost") and shooter.has_at_boost():
			scale *= 1.6
		col.take_damage(damage * scale, shooter)
		EventBus.impact.emit(pos, hit.get("normal", Vector2.UP), "metal")
		AudioManager.play_2d("hit_metal", pos, AudioManager.volume_for(pos, _listener()))
	else:
		EventBus.impact.emit(pos, hit.get("normal", Vector2.UP), "sand")
	queue_free()

func _listener() -> Vector2:
	if TeamManager.player != null and is_instance_valid(TeamManager.player):
		return TeamManager.player.global_position
	return global_position

func _draw() -> void:
	# 曳光：从上一位置拖一条渐隐的短线
	var tail := _prev - global_position
	if tail.length() < 1.0:
		tail = -dir * 26.0
	draw_line(Vector2.ZERO, tail * 1.6, Color(1.0, 0.73, 0.41, 0.28), 4.0)
	draw_line(Vector2.ZERO, tail, Color(1.0, 0.92, 0.68, 0.95), 1.8)
	draw_circle(Vector2.ZERO, 1.8, Color(1.0, 0.97, 0.85, 0.9))
