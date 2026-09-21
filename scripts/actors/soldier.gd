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
var op_id: String = "redwolf"
var op_class: int = GameConfig.OpClass.ASSAULT
var unit_name: String = ""
var is_player: bool = false
var is_bot: bool = true
var squad_id: int = 0
var is_squad_leader: bool = false
var is_commander: bool = false
## 干员被动：exo（击杀回血+移速）/ regen（脱战回血）/ at_boost（反载具加成）/
## dog（军犬自动标记）/ spot_long / drone（侦察强化）
var passive: String = ""

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
var streak: int = 0                ## 当前连杀（阵亡清零），连杀奖励的门槛依据
var best_streak: int = 0           ## 本局最高连杀，结算页展示
# ---- 四维能力画像（结算页的金/银/铜标签用）----
var vehicle_damage: float = 0.0    ## 对载具造成的伤害 -> 载具能力
var infantry_damage: float = 0.0   ## 对步兵造成的伤害 -> 步战能力
var revives: int = 0               ## 救起人数 -> 救援能力

# ---------------------------------------------------------------- 视觉
var body: Sprite2D
var info: Node2D
var _spawn_point: Vector2 = Vector2.ZERO
var _pending_spawn: Vector2 = Vector2.ZERO
var _hit_flash: float = 0.0

# ---------------------------------------------------------------- 倒地与救援
## 倒地的单位仍然 alive，但不参与战斗、不占点、不进索敌结果 —— 见 TeamManager.alive_units
var downed: bool = false
var bleed_out: float = 0.0            ## 剩余流血时间，归零就真阵亡
var dragging_by: Soldier = null       ## 正在拖我的人
var drag_target: Soldier = null       ## 我正在拖的人
var revive_progress: float = 0.0      ## 救援进度（秒）

signal died(victim: Soldier, killer: Soldier, headshot: bool)

func _ready() -> void:
	body = $Body
	info = $Info
	_apply_operator()
	# 碰撞：与建筑和敌方单位碰撞，同队不互相推挤
	restore_physics()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	TeamManager.register_unit(self)
	info.draw.connect(_draw_info)
	EventBus.unit_spawned.emit(self)

## 回到物理世界：重生与"从载具下车"共用同一份碰撞配置。
## 只撞建筑/地形，不撞敌方身体 —— 20v20 前线若互推，人会在墙角原地打转卡死。
## 子弹命中仍走射线查 TEAM 层，不受这里影响。
func restore_physics() -> void:
	collision_layer = GameConfig.team_layer(team)
	collision_mask = GameConfig.Layer.WORLD
	velocity = Vector2.ZERO
	move_dir = Vector2.ZERO

## 退出物理世界：上车时调用。乘员不再参与碰撞与射线判定。
func park_for_vehicle() -> void:
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	move_dir = Vector2.ZERO
	sprinting = false

# ---------------------------------------------------------------- 初始化
## 由生成器调用：配置干员与身份。
## 传 op_id 就用指定干员；只传兵种则落到该兵种的默认干员 ——
## AI 编队按兵种出人，玩家按干员选人，两条路都走这一个入口
func setup(p_team: int, p_class: int, p_name: String, p_is_player: bool = false,
		p_op_id: String = "") -> void:
	team = p_team
	op_id = p_op_id if p_op_id != "" else GameConfig.op_id_for_class(p_class)
	op_class = int(GameConfig.op(op_id).get("class", p_class))
	unit_name = p_name
	is_player = p_is_player
	is_bot = not p_is_player
	_apply_operator()

func _apply_operator() -> void:
	var op: Dictionary = GameConfig.op(op_id)
	weapon_id = op["weapon"]
	weapon = GameConfig.WEAPONS[weapon_id]
	max_hp = op["hp"]
	if alive:
		hp = max_hp
	passive = op.get("passive", "")
	# 动力外骨骼：移速小幅常驻（主动加成由技能提供）
	speed_scale = op["speed"] * (1.06 if passive == "exo" else 1.0)
	ammo = weapon["mag"]
	reserve = weapon["reserve"]
	if body != null:
		var tex := AssetDB.operator_texture_for(op_id)
		if tex != null:
			body.texture = tex
			# 用补边前的逻辑宽度算缩放：AssetDB 给贴图补过描边留白，
			# 直接用 get_width 会把整个人算小一圈
			var k := AssetDB.OPERATOR_DRAW_WIDTH / AssetDB.logical_width(tex)
			body.scale = Vector2(k, k)
		body.modulate = _tint_for_team()
		if not AssetDB.OPERATOR_HAS_BAKED_OUTLINE:
			AssetDB.apply_outline(body)

## 阵营靠脚下的圆盘区分，不靠给整张立绘染色。
## 染色会把描边和素材本身的颜色一起洗掉，卡通风格最怕这个；
## 而俯视角下"脚下有个颜色圈"本来就是最有效率的敌我识别方式。
func _draw() -> void:
	if not alive:
		return
	var col := GameConfig.team_color(team)
	var r := 15.0
	draw_circle(Vector2(0, 4), r + 2.4, Palette.OUTLINE)
	draw_circle(Vector2(0, 4), r, Color(col.r, col.g, col.b, 0.92))
	draw_circle(Vector2(0, 4), r * 0.62, Color(col.r * 0.72, col.g * 0.72, col.b * 0.72, 0.95))

func _tint_for_team() -> Color:
	# 只留一点点阵营倾向；主要识别交给脚下的圆盘
	if team == GameConfig.Team.GTI:
		return Color(0.94, 0.98, 1.0)
	return Color(1.0, 0.96, 0.94)

# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if not alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_do_respawn()
		return

	# 倒地：只能爬，流血计时走完就真阵亡
	if downed:
		bleed_out -= delta
		_tick_rescue(delta)
		# _tick_rescue 可能在本帧里把人救起来（revive 会把 bleed_out 归零），
		# 所以这里必须重新确认一次状态。少了这行，被救起的那一帧会紧接着
		# 被下面的流血判定再判一次死 —— "救起来了但血是 0"就是这么来的
		if not downed:
			queue_redraw()
			info.queue_redraw()
			return
		velocity = move_dir * 62.0
		move_and_slide()
		if bleed_out <= 0.0:
			_die(null, false)
		queue_redraw()
		info.queue_redraw()
		return
	_tick_rescue(delta)

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

	_tick_passive(delta)

	_tick_reload(delta)
	# 移动由外部（玩家输入 / AI）写入 move_dir
	var spd := 200.0 * speed_scale
	if sprinting:
		spd *= 1.42
	if aiming_down_sight:
		spd *= 0.58
	# 拖着人跑不快。这个减速就是"拖拽救援"的代价：救人有风险，
	# 不是走过去点一下就把人拉回来的免费动作
	if drag_target != null:
		spd *= GameConfig.DRAG_SPEED_SCALE
	velocity = move_dir * spd
	move_and_slide()
	# 朝向只转贴图与枪口，根节点保持 0 —— 否则血条/名字跟着斜，卡住时还会原地疯转
	rotation = 0.0
	if aim_dir.length_squared() > 0.001:
		var ang := aim_dir.angle()
		if body != null:
			body.rotation = ang
		var muzzle_n := get_node_or_null("Muzzle") as Marker2D
		if muzzle_n != null:
			muzzle_n.position = aim_dir.normalized() * 24.0
	if info != null:
		info.rotation = 0.0
	info.queue_redraw()
	queue_redraw()

## 干员被动：脱战回血 / 军犬标记。
## 都做成"每秒算一次"的节流形式，不进每帧热路径
var _passive_t: float = 0.0
func _tick_passive(delta: float) -> void:
	if passive == "":
		return
	_passive_t += delta
	if _passive_t < 1.0:
		return
	_passive_t = 0.0
	if passive == "regen" and hp < max_hp and spawn_protection <= 0.0:
		# 脱战判定用"最近被命中"的时间，简化成"血不是满的但已经几秒没挨打"
		var hurt_recently := false
		for u in TeamManager.alive_units():
			if u.team == team:
				continue
			if u.global_position.distance_to(global_position) < 420.0 and u.has_method("try_fire"):
				hurt_recently = true
				break
		if not hurt_recently:
			hp = minf(max_hp, hp + 6.0)
	elif passive == "dog":
		for u in TeamManager.alive_units():
			if u.team == team:
				continue
			if global_position.distance_to(u.global_position) < 320.0:
				u.set_meta("spotted_until", Time.get_ticks_msec() / 1000.0 + 3.0)

## 侦察干员的标记时长与半径（露娜/银翼各自强化一项）
func spot_duration() -> float:
	if passive == "spot_long":
		return 12.0
	return 7.0

func spot_radius() -> float:
	if passive == "drone":
		return 1700.0
	return 1200.0

## 是否具备反载具加成（乌鲁鲁）
func has_at_boost() -> bool:
	return passive == "at_boost"

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
	# 把武器 id 一并交给子弹：空中目标要按武器类型算伤害
	# （普通枪械对空中目标大打折扣，狙击枪是例外）
	var w := weapon.duplicate()
	w["key"] = weapon_id
	b.setup(team, self, muzzle, dir, w)
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
	if not alive or spawn_protection > 0.0 or downed:
		return
	# 车内乘员只挨装甲的伤害：否则一颗落在车边的炮弹会隔着装甲打死驾驶员
	if in_vehicle != null:
		return
	hp -= amount
	_hit_flash = 1.0
	if attacker != null and attacker.team != team:
		attacker.damage_done += amount
		attacker.infantry_damage += amount
	if is_player:
		var dir := 0.0
		if attacker != null:
			dir = (attacker.global_position - global_position).angle()
		EventBus.player_hurt.emit(dir, clampf(amount / 60.0, 0.1, 1.0))
		AudioManager.play_ui("hurt", -8.0)
	EventBus.unit_damaged.emit(self, amount, attacker)
	if hp <= 0.0:
		# 打空血先进倒地。倒地期间不再吃伤害（已经失去战斗能力），
		# 真正的结算交给流血计时或者救人
		_go_down(attacker)

## 进入倒地状态
func _go_down(killer: Soldier) -> void:
	if downed:
		return
	downed = true
	hp = 0.0
	bleed_out = GameConfig.BLEED_OUT_TIME
	velocity = Vector2.ZERO
	move_dir = Vector2.ZERO
	sprinting = false
	aiming_down_sight = false
	# 倒地后退出碰撞层：不该再被子弹扫到，也不该挡住队友走位
	collision_layer = 0
	revive_progress = 0.0
	# 连杀在"被击倒"这一刻断，而不是等流血结束。
	# 倒地已经是失去战斗能力，还留着连杀数只会让玩家误判自己还在状态里
	if streak > 0:
		streak = 0
		if is_player:
			EventBus.player_streak_changed.emit(0)
	# 击杀的记账放在倒地这一刻，而不是真阵亡那一刻：
	# 加了对倒地的拖拽救援之后，"把对面打倒"才是玩家感知到的击杀，
	# 等流血结束再记账会让击杀数与连杀都慢半拍
	if killer != null and is_instance_valid(killer) and killer.team != team:
		killer.kills += 1
		killer.score += 100.0
		if killer.passive == "exo":
			killer.hp = minf(killer.max_hp, killer.hp + 14.0)
		if killer.is_player:
			EventBus.hitmarker.emit(false, true, 0.0)
	EventBus.unit_downed.emit(self, killer, bleed_out)
	EventBus.kill_feed.emit("%s 击倒 %s" % [
		"—" if killer == null else ("你" if killer.is_player else killer.unit_name),
		"你" if is_player else unit_name], Color("#ff9a3a"))
	if is_player:
		EventBus.toast.emit("你已倒地 · %.0fs 内等待救援，或自行流血至阵亡" % bleed_out,
			Palette.MARK_WARN)
	AudioManager.play_2d("hurt", global_position, -6.0)

## 被救起来：回到四成血
func _revive() -> void:
	if not downed:
		return
	downed = false
	hp = maxf(1.0, max_hp * GameConfig.REVIVE_HP_RATIO)
	bleed_out = 0.0
	revive_progress = 0.0
	dragging_by = null
	restore_physics()
	visible = true
	body.modulate = _tint_for_team()
	EventBus.unit_revived.emit(self)
	EventBus.kill_feed.emit("%s 被救起" % ("你" if is_player else unit_name), Color("#57e08a"))
	if is_player:
		EventBus.toast.emit("你已被救起 · 血量 %.0f" % hp, Color("#57e08a"))

## 开始拖拽救援。返回是否成功
func start_drag(target_node: Soldier) -> bool:
	if target_node == null or not is_instance_valid(target_node):
		return false
	if not target_node.downed or target_node.dragging_by != null:
		return false
	if global_position.distance_to(target_node.global_position) > GameConfig.REVIVE_RANGE:
		return false
	drag_target = target_node
	target_node.dragging_by = self
	EventBus.unit_drag_changed.emit(target_node, self)
	return true

func release_drag() -> void:
	if drag_target != null and is_instance_valid(drag_target):
		drag_target.dragging_by = null
		EventBus.unit_drag_changed.emit(drag_target, null)
	drag_target = null

## 救援进度推进（每秒调用）。拖拽状态下的队友会被带着走
func _tick_rescue(delta: float) -> void:
	if downed:
		# 被拖时跟着救援者走，否则只能原地爬
		if dragging_by != null and is_instance_valid(dragging_by):
			global_position = dragging_by.global_position + Vector2(0, 26).rotated(dragging_by.rotation)
			revive_progress += delta
			if revive_progress >= GameConfig.REVIVE_TIME:
				dragging_by.revives += 1
				_revive()
		return
	if drag_target == null:
		return
	if not is_instance_valid(drag_target) or not drag_target.downed:
		release_drag()
		return
	if global_position.distance_to(drag_target.global_position) > GameConfig.REVIVE_RANGE * 2.2:
		release_drag()
		return
	drag_target.global_position = global_position + Vector2(0, 26).rotated(rotation)
	EventBus.unit_reviving.emit(self, drag_target, drag_target.revive_progress)

func _die(killer: Soldier, headshot: bool) -> void:
	if downed:
		# 流血到点：这一下才是真阵亡，才扣兵力
		downed = false
		dragging_by = null
		EventBus.feed.emit("%s 流血过多阵亡" % ("你" if is_player else unit_name),
			Color("#ff9a3a"))
	alive = false
	deaths += 1
	hp = 0.0
	# 复活点与复活冷却都在阵亡这一刻定下来：
	# 「在小队长附近重部署 -5 秒」要在**落点**上判定才算数，
	# 等 20 秒过去再算的话，队长早就走了
	_pending_spawn = _pick_respawn_pos()
	respawn_timer = _compute_respawn_delay()
	velocity = Vector2.ZERO
	move_dir = Vector2.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	# 阵亡断连杀：这是连杀奖励体系里唯一的"清零"入口
	if streak > 0:
		streak = 0
		if is_player:
			EventBus.player_streak_changed.emit(0)
	# 阵线增援生效期间，攻方的重部署不扣兵力
	MatchState.spend_ticket(team, MatchState.redeploy_is_free(team))
	if killer != null and killer.team != team:
		killer.kills += 1
		killer.score += 100.0
		# 动力外骨骼：击杀回血，这是"突进收割"能滚起来的关键
		if killer.passive == "exo":
			killer.hp = minf(killer.max_hp, killer.hp + 14.0)
		if killer.is_player:
			EventBus.hitmarker.emit(headshot, true, 0.0)
		# 连杀计数不在这里加。是不是"算一次连杀"属于奖励规则，
		# 由 StreakManager 监听 unit_died 后判定（支援击杀不计入，见那边注释）。
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

## 挑一个复活点：优先当前开放区前线（胜者为王交战带），其次己方据点，最后基地
func _pick_respawn_pos() -> Vector2:
	var base: Vector2 = GameConfig.BASE_POS[team]
	var seg := clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
	var front: Array = []
	var owned: Array = []
	for c in GameConfig.CAPTURES:
		var pos: Vector2 = c["pos"]
		if int(c["seg"]) == seg:
			front.append(pos)
		if MatchState.captures[c["id"]]["owner"] == team:
			owned.append(pos)
	var pos: Vector2
	var roll := randf()
	if not front.is_empty() and roll < 0.78:
		var side := -1.0 if team == GameConfig.Team.GTI else 1.0
		pos = front[randi() % front.size()] + Vector2(side * randf_range(60, 200), randf_range(-140, 140))
	elif not owned.is_empty() and roll < 0.92:
		pos = owned[randi() % owned.size()] + Vector2(randf_range(-90, 90), randf_range(-90, 90))
	else:
		pos = base + Vector2(0, randf_range(-320, 320))
	pos = pos.clamp(Vector2(60, 60), GameConfig.WORLD_SIZE - Vector2(60, 60))
	var world := get_tree().get_first_node_in_group("world_map")
	return world.safe_spawn(pos) if world != null else pos

## 复活冷却：基础 20 秒，落点在小队长附近再减 5 秒
func _compute_respawn_delay() -> float:
	var d := MatchState.respawn_delay_for(team)
	var sq := TeamManager.squad_of(self)
	if sq != null:
		var ld: Soldier = sq.active_leader()
		if ld != null and ld != self and ld.global_position.distance_to(_pending_spawn) < 320.0:
			d = maxf(3.0, d - GameConfig.LEADER_RESPAWN_BONUS)
	return d

func _do_respawn() -> void:
	global_position = _pending_spawn
	alive = true
	hp = max_hp
	ammo = weapon["mag"]
	reserve = weapon["reserve"]
	is_reloading = false
	spawn_protection = 1.6
	visible = true
	downed = false
	bleed_out = 0.0
	dragging_by = null
	revive_progress = 0.0
	release_drag()
	restore_physics()
	body.modulate = _tint_for_team()
	if is_player:
		EventBus.player_respawned.emit(self)

# ---------------------------------------------------------------- 技能
func can_use_skill() -> bool:
	return alive and skill_cd <= 0.0

func start_skill_cd() -> void:
	skill_cd = GameConfig.op(op_id)["skill_cd"]

## 连杀 +1。这里只负责计数与上报，具体发什么奖励由 StreakManager 决定 ——
## 单位层不应该知道"多少杀给什么"这种规则。
func bump_streak() -> void:
	streak += 1
	if streak > best_streak:
		best_streak = streak
	if is_player:
		EventBus.player_streak_changed.emit(streak)
		AudioManager.play_ui("kill", -5.0)

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
