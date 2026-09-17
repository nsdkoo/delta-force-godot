extends Node2D
class_name Grenade
## 动能手雷（突击兵大招）：抛物线飞行，范围伤害

var team: int = GameConfig.Team.GTI
var shooter: Soldier = null
var from_pos: Vector2 = Vector2.ZERO
var to_pos: Vector2 = Vector2.ZERO
var fuse: float = 1.1
var travel: float = 0.0
var duration: float = 0.55
var radius: float = 190.0

func setup(p_team: int, p_shooter: Soldier, from: Vector2, to: Vector2) -> void:
	team = p_team
	shooter = p_shooter
	from_pos = from
	to_pos = to
	global_position = from

func _ready() -> void:
	z_index = 7

func _physics_process(delta: float) -> void:
	if travel < duration:
		travel += delta
		global_position = from_pos.lerp(to_pos, clampf(travel / duration, 0.0, 1.0))
	fuse -= delta
	queue_redraw()
	if fuse <= 0.0:
		_explode()

func _explode() -> void:
	EventBus.explosion.emit(global_position, 1.9, "boom")
	AudioManager.play_2d("boom_big", global_position, -3.0)
	for u in TeamManager.alive_units():
		if u.team == team:
			continue
		var d := global_position.distance_to(u.global_position)
		if d < radius:
			u.take_damage(130.0 * (1.0 - d / radius), shooter)
	for v in TeamManager.vehicles:
		if not is_instance_valid(v) or not v.alive or v.team == team:
			continue
		if global_position.distance_to(v.global_position) < radius + 20.0:
			v.take_damage(60.0, shooter)
	queue_free()

func _draw() -> void:
	var blink := 0.5 + 0.5 * absf(sin(fuse * 12.0))
	draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.6, 0.23))
	draw_arc(Vector2.ZERO, 14.0 + (1.0 - blink) * 8.0, 0, TAU, 20,
		Color(1.0, 0.35, 0.16, 0.35 + blink * 0.4), 2.0)
