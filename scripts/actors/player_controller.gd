extends Node
class_name PlayerController
## ============================================================================
## PlayerController · 玩家输入
## ----------------------------------------------------------------------------
## 独立于 Soldier 之外：只负责读输入、写状态。Soldier 不关心自己是人还是 AI。
##
## 步行与驾驶走同一条思路 —— 把键鼠翻译成目标对象身上的几个字段：
##   步行：soldier.move_dir / aim_dir / want_fire
##   驾驶：vehicle.move_dir / turret_dir / want_fire
## 两种模式互斥，但都只是"写字段"，所以战斗逻辑一行都不用改。
## ============================================================================

## 可上车距离。给得比载具半径大一些，站车边就能按 F，不用精确贴上去
const BOARD_RANGE := 130.0

var soldier: Soldier = null
var camera: Camera2D = null
var vehicle: CombatVehicle = null
var ads: float = 0.0
var last_damage_flash := 0.0
## 调试用：大于 0 时压过步行/驾驶的常规缩放。
## 美术走查需要把镜头推到很近看单个单位的描边，正常玩法不需要这个。
var zoom_override: float = 0.0
## 产品外壳接管标志：主菜单期间由 AppShell 驱动相机（attract mode），
## 这里只负责"不读输入、不抢相机"。开关由 main.gd 在进/出菜单时设置。
var shell_mode: bool = false

func attach(p_soldier: Soldier, p_camera: Camera2D) -> void:
	soldier = p_soldier
	camera = p_camera
	if camera != null:
		camera.global_position = soldier.global_position

func _physics_process(delta: float) -> void:
	if soldier == null or not is_instance_valid(soldier):
		return

	# 主菜单期间把控制权整个让出去：相机归 AppShell，输入不读。
	# 少了这一步，玩家在菜单里按 WASD 会在背后动来动去，菜单就"不干净"了
	if shell_mode:
		_apply_camera(delta, true)
		return

	# 静音是全局开关，跟步兵/驾驶状态无关，所以放在状态判断之前
	if Input.is_action_just_pressed("mute"):
		var now_muted := AudioManager.toggle_mute()
		EventBus.toast.emit("音效已静音" if now_muted else "音效已恢复", Color("#8fc4ff"))

	# 驾驶状态的合法性每帧校验：载具被击毁时会自己把乘员抛出来，
	# 这个引用会变成失效指针，必须在这里发现并退出驾驶模式
	if vehicle != null and (not is_instance_valid(vehicle) or vehicle.driver != soldier):
		_release_vehicle()

	if vehicle != null:
		_drive_vehicle(delta)
		return

	if not soldier.alive:
		soldier.move_dir = Vector2.ZERO
		soldier.sprinting = false
		return
	_move_on_foot(delta)

## 相机：跟随 + 缩放 + 震屏偏移。
## attract 为真时不做跟随（跟随归 AppShell 的 attract mode）。
## base_zoom 用于驾驶时的拉远视角。
## 震屏用 camera.offset 而不是改 global_position —— offset 是纯表现层的
## 偏移，不会和跟随逻辑互相打架，也不用担心把镜头推出世界边界
func _apply_camera(delta: float, attract: bool, base_zoom: float = 0.0) -> void:
	if camera == null:
		return
	if not attract:
		var target := soldier.global_position + soldier.aim_dir * 90.0
		camera.global_position = camera.global_position.lerp(target, clampf(delta * 7.0, 0.0, 1.0))
	var z := zoom_override if zoom_override > 0.0 else (
		1.24 if soldier.aiming_down_sight else (base_zoom if base_zoom > 0.0 else 1.06))
	if attract:
		z = 1.15
	camera.zoom = camera.zoom.lerp(Vector2.ONE * z, clampf(delta * 8.0, 0.0, 1.0))
	camera.offset = ImpactFx.offset()

# ============================================================ 步行
func _move_on_foot(delta: float) -> void:
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
	if Input.is_action_just_pressed("enter_vehicle"):
		_try_board()
	if Input.is_action_just_pressed("rescue"):
		_toggle_rescue()
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
		_apply_camera(delta, false)

## 拖拽救援开关。G 按下即抓、再按松开；走远了会自动断
func _toggle_rescue() -> void:
	if soldier.drag_target != null:
		soldier.release_drag()
		EventBus.toast.emit("已松开救援目标", Palette.UI_TEXT_DIM)
		return
	var t: Soldier = TeamManager.nearest_downed(soldier.global_position, soldier.team,
		GameConfig.REVIVE_RANGE)
	if t == null:
		EventBus.toast.emit("附近没有需要救援的队友", Palette.UI_TEXT_DIM)
		return
	if soldier.start_drag(t):
		EventBus.toast.emit("拖拽救援中 · 保持接触 %.0f 秒" % GameConfig.REVIVE_TIME,
			Color("#57e08a"))

# ============================================================ 驾驶
func _try_board() -> void:
	if soldier.in_vehicle != null:
		return
	var v: CombatVehicle = TeamManager.nearest_friendly_vehicle(
		soldier.global_position, soldier.team, BOARD_RANGE)
	if v == null:
		EventBus.toast.emit("附近没有可搭乘的载具", Color("#7f97a8"))
		return
	if not v.enter(soldier):
		EventBus.toast.emit("该载具已有驾驶员", Color("#7f97a8"))
		return
	vehicle = v
	v.manual_gun = true
	EventBus.toast.emit("%s · 左键开炮 / 1-2 弹种 / 3 主动防御 / F 下车" % v.display_name(),
		Color("#8fc4ff"))

func _release_vehicle() -> void:
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.manual_gun = false
		if vehicle.driver == soldier:
			vehicle.exit_vehicle()
	vehicle = null

func _drive_vehicle(delta: float) -> void:
	# --- 车体 ---
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	vehicle.move_dir = input_dir

	# --- 炮塔（鼠标世界坐标，按转速限制追过去，不是瞬间对准）---
	var mouse_world := vehicle.get_global_mouse_position()
	var to_mouse := mouse_world - vehicle.global_position
	if to_mouse.length_squared() > 64.0:
		vehicle.turret_dir = to_mouse.normalized()

	# --- 主炮 / 机枪 ---
	vehicle.want_fire = Input.is_action_pressed("fire")

	# --- 弹种与主动防御 ---
	if Input.is_action_just_pressed("swap_ammo"):
		if not vehicle.switch_ammo(0):
			EventBus.toast.emit("已是%s" % vehicle.ammo_label(), Color("#7f97a8"))
	if Input.is_action_just_pressed("swap_ammo2"):
		if not vehicle.switch_ammo(1):
			EventBus.toast.emit("已是%s" % vehicle.ammo_label(), Color("#7f97a8"))
	if Input.is_action_just_pressed("aps"):
		if vehicle.activate_aps():
			EventBus.toast.emit("主动防御启动 · %.0fs" % GameConfig.APS_DURATION, Color("#8fc4ff"))
		else:
			EventBus.toast.emit("APS 冷却中 %.0fs" % maxf(0.0, vehicle.aps_cd), Color("#7f97a8"))

	# --- 下车 ---
	# 必须立刻 return：_release_vehicle 会把 vehicle 置空，
	# 继续往下走会在同一帧里解引用空对象
	if Input.is_action_just_pressed("enter_vehicle"):
		_release_vehicle()
		return

	# --- 相机：车身是重家伙，跟得比步兵慢一点，视野拉远 ---
	if camera != null:
		camera.global_position = camera.global_position.lerp(vehicle.global_position,
			clampf(delta * 5.0, 0.0, 1.0))
		_apply_camera(delta, false, 0.86)

# ============================================================ 技能
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
			# 标记时长与半径由干员被动决定（露娜拉长时长、银翼放大范围）
			var n := 0
			var until := Time.get_ticks_msec() / 1000.0 + soldier.spot_duration()
			for u in TeamManager.alive_units():
				if u.team != soldier.team 						and soldier.global_position.distance_to(u.global_position) < soldier.spot_radius():
					u.set_meta("spotted_until", until)
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
