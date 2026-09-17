extends Node2D
class_name Missile
## 巡飞弹（工程兵大招）：追踪目标，可被载具主动防御系统（APS）拦截

var team: int = GameConfig.Team.GTI
var shooter: Soldier = null
var target: Node2D = null
var target_pos: Vector2 = Vector2.ZERO
var speed: float = 430.0
var damage: float = 900.0
var life: float = 7.0
var _trail_t: float = 0.0

func setup(p_team: int, p_shooter: Soldier, from: Vector2, p_target: Node2D, p_pos: Vector2) -> void:
	team = p_team
	shooter = p_shooter
	global_position = from
	target = p_target
	target_pos = p_pos
	damage = 900.0 if p_target != null and p_target.has_method("take_damage") and p_target is not Soldier else 200.0

func _ready() -> void:
	z_index = 7

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_burst(false)
		return
	var dest := target_pos
	if target != null and is_instance_valid(target) and target.get("alive") != false:
		dest = target.global_position
	var to_dest := dest - global_position
	var d := to_dest.length()
	if d < 26.0:
		_burst(true)
		return
	var dir := to_dest / maxf(d, 0.001)
	rotation = dir.angle()
	global_position += dir * speed * delta
	# APS 拦截
	for v in TeamManager.vehicles:
		if not is_instance_valid(v) or not v.alive or v.team == team:
			continue
		if v.has_method("aps_active") and v.aps_active() and global_position.distance_to(v.global_position) < GameConfig.APS_RANGE:
			_burst(false)
			EventBus.feed.emit("主动防御拦截来袭飞弹", Color("#8fc4ff"))
			return
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.03
		EventBus.explosion.emit(global_position, 0.12, "smoke")

func _burst(hit: bool) -> void:
	EventBus.explosion.emit(global_position, 1.6 if hit else 0.9, "boom")
	if hit:
		if target != null and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(damage, shooter)
		else:
			for u in TeamManager.alive_units():
				if u.team != team and global_position.distance_to(u.global_position) < 130.0:
					u.take_damage(damage * 0.7, shooter)
	AudioManager.play_2d("boom_big", global_position, -4.0)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(0.95, 0.95, 0.95))
	draw_arc(Vector2.ZERO, 13.0, 0, TAU, 16, Color(1.0, 0.68, 0.35, 0.85), 2.5)
