extends Node
class_name PlayerController
## ============================================================================
## PlayerController · 玩家输入
## ----------------------------------------------------------------------------
## 独立于 Soldier 之外：只负责读输入、写状态。Soldier 不关心自己是人还是 AI。
## ============================================================================

var soldier: Soldier = null
var camera: Camera2D = null
var ads: float = 0.0
var last_damage_flash := 0.0

func attach(p_soldier: Soldier, p_camera: Camera2D) -> void:
	soldier = p_soldier
	camera = p_camera
	if camera != null:
		camera.global_position = soldier.global_position

func _physics_process(delta: float) -> void:
	if soldier == null or not is_instance_valid(soldier):
		return
	if not soldier.alive:
		soldier.move_dir = Vector2.ZERO
		soldier.sprinting = false
		return

	# --- 移动 ---
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	soldier.move_dir = input_dir
	soldier.sprinting = Input.is_action_pressed("sprint") \
		and input_dir.length() > 0.15 and ads < 0.4 and not soldier.aiming_down_sight

	# --- 瞄准（鼠标世界坐标）---
	var mouse_world := soldier.get_global_mouse_position()
	var to_mouse := mouse_world - soldier.global_position
	if to_mouse.length_squared() > 4.0:
		soldier.aim_dir = to_mouse.normalized()

	# --- 开镜 ---
	var want_ads := Input.is_action_pressed("aim")
	ads = lerp(ads, 1.0 if want_ads else 0.0, clampf(delta * 11.0, 0.0, 1.0))
	soldier.aiming_down_sight = ads > 0.5

	# --- 射击 ---
	var w: Dictionary = soldier.weapon
	var auto: bool = w.get("auto", true)
	if auto:
		if Input.is_action_pressed("fire"):
			soldier.try_fire()
	else:
		if Input.is_action_just_pressed("fire"):
			soldier.try_fire()

	# --- 交互 ---
	if Input.is_action_just_pressed("reload"):
		soldier.start_reload()
	if Input.is_action_just_pressed("skill"):
		_use_skill()
	if Input.is_action_just_pressed("field_med"):
		_use_field_med()

	# --- 相机 ---
	if camera != null:
		var target := soldier.global_position + soldier.aim_dir * 90.0
		camera.global_position = camera.global_position.lerp(target, clampf(delta * 7.0, 0.0, 1.0))
		camera.zoom = camera.zoom.lerp(Vector2.ONE * (1.24 if soldier.aiming_down_sight else 1.06),
			clampf(delta * 8.0, 0.0, 1.0))

func _use_skill() -> void:
	if not soldier.can_use_skill():
		EventBus.toast.emit("技能冷却中 %.1fs" % soldier.skill_cd, Color("#7f97a8"))
		return
	var map = get_tree().get_first_node_in_group("world_map")
	match soldier.op_class:
		GameConfig.OpClass.ENGINEER:
			var veh := TeamManager.nearest_enemy_vehicle(soldier.global_position, soldier.team, 900.0)
			var target_pos: Vector2
			if veh != null:
				target_pos = veh.global_position
			else:
				var en := TeamManager.nearest_visible_enemy(soldier.global_position, soldier.team, 900.0)
				target_pos = en.global_position if en != null else soldier.get_global_mouse_position()
			if map != null and map.has_method("spawn_missile"):
				map.spawn_missile(soldier, target_pos, veh)
			EventBus.toast.emit("巡飞弹已发射 · 追踪目标", Color("#ffc24a"))
		GameConfig.OpClass.ASSAULT:
			var throw_at := soldier.get_global_mouse_position()
			if map != null and map.has_method("spawn_grenade"):
				map.spawn_grenade(soldier, throw_at)
			EventBus.toast.emit("动能手雷已投掷", Color("#ff6b57"))
		GameConfig.OpClass.SUPPORT:
			if map != null and map.has_method("spawn_medkit"):
				map.spawn_medkit(soldier)
			EventBus.toast.emit("医疗包已投放", Color("#57e08a"))
		GameConfig.OpClass.RECON:
			var n := 0
			for u in TeamManager.alive_units():
				if u.team != soldier.team and soldier.global_position.distance_to(u.global_position) < 1200.0:
					u.set_meta("spotted_until", Time.get_ticks_msec() / 1000.0 + 7.0)
					n += 1
			EventBus.toast.emit("声波探测 · 标记 %d 个敌方目标" % n, Color("#8fc4ff"))
	soldier.start_skill_cd()

func _use_field_med() -> void:
	if soldier.field_med_cd > 0.0:
		EventBus.toast.emit("野战急救冷却中 %.1fs" % soldier.field_med_cd, Color("#7f97a8"))
		return
	soldier.field_med_cd = 14.0
	var healed := 0
	for u in TeamManager.alive_units(soldier.team):
		if soldier.global_position.distance_to(u.global_position) < 120.0:
			u.hp = minf(u.max_hp, u.hp + 25.0)
			healed += 1
	EventBus.toast.emit("野战急救 · 治疗 %d 名友军" % healed, Color("#57e08a"))
