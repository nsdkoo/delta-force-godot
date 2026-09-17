extends Node2D
class_name Medkit
## 医疗包（支援兵大招）：范围内持续治疗友军

var team: int = GameConfig.Team.GTI
var radius: float = 120.0
var life: float = 15.0
var heal_rate: float = 9.0

func setup(p_team: int, pos: Vector2) -> void:
	team = p_team
	global_position = pos

func _ready() -> void:
	z_index = -12

func _physics_process(delta: float) -> void:
	life -= delta
	for u in TeamManager.alive_units(team):
		if global_position.distance_to(u.global_position) < radius:
			u.hp = minf(u.max_hp, u.hp + heal_rate * delta)
	queue_redraw()
	if life <= 0.0:
		queue_free()

func _draw() -> void:
	var a := clampf(life / 3.0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(0.34, 0.88, 0.54, 0.12 * a))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(0.34, 0.88, 0.54, 0.35 * a), 2.0)
	draw_rect(Rect2(-9, -3, 18, 6), Color(0.34, 0.88, 0.54, 0.95 * a), true)
	draw_rect(Rect2(-3, -9, 6, 18), Color(0.34, 0.88, 0.54, 0.95 * a), true)
