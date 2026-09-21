extends Node
## ============================================================================
## StreakManager · 连杀奖励
## ----------------------------------------------------------------------------
## 只服务玩家：连续击杀累积到门槛就发奖励，阵亡清零。
## 奖励分两类 —— 即时生效的（UAV）与需要呼叫的（迫击炮 / 空中打击 / 载具增援）。
## 后者进"待呼叫槽"，按 X 在鼠标指向处释放。
##
## 为什么支援伤害不走 PlayerController、也不在 Soldier 里判定：
## 连杀规则必须只有一个决策点。这里用 _applying_support 标志回答一个关键问题——
## 「这一杀算不算连杀」。支援火力刷出来的击杀不计数，否则会自举：
## 5 杀拿迫击炮 -> 迫击炮炸死 3 个 -> 直接跳到 8 杀拿空袭 -> 空袭再炸出 12 杀……
## 一局只要开一次头，后面全靠支援自己喂自己，连杀体系就失去意义了。
## ============================================================================

const VehicleScript := preload("res://scripts/actors/vehicle.gd")
const VehicleBrainScript := preload("res://scripts/ai/vehicle_brain.gd")

## UAV 侦察时长
const UAV_TIME := 10.0

# ---------------------------------------------------------------- 状态
var streak: int = 0
var support_kind: String = ""          ## 待呼叫的支援，空串表示没有
var _clock: float = 0.0
var _queue: Array = []                 ## {"at","pos","radius","inf_dmg","veh_dmg","scale"}
var _applying_support: bool = false

func _ready() -> void:
	EventBus.unit_downed.connect(_on_unit_downed)
	EventBus.player_streak_changed.connect(_on_streak_changed)
	EventBus.match_started.connect(reset)

## 重开一局时清空
func reset() -> void:
	streak = 0
	support_kind = ""
	_queue.clear()
	_applying_support = false

# ============================================================ 计数
## 连杀按"击倒"计，不按"流血至死"计。加了拖拽救援之后这两件事会分开：
## 现在把敌人打倒是击杀，之后他被救起来还是流血死掉都不再重复计数
func _on_unit_downed(_victim: Node2D, killer: Node2D, _bleed_out: float) -> void:
	if _applying_support:
		return
	if killer == null or not is_instance_valid(killer) or not killer.is_player:
		return
	killer.bump_streak()

func _on_streak_changed(value: int) -> void:
	streak = value
	if value <= 0:
		return
	if not GameConfig.STREAK_REWARDS.has(value):
		return
	var reward: Dictionary = GameConfig.STREAK_REWARDS[value]
	_grant(reward)

func _grant(reward: Dictionary) -> void:
	var kind: String = reward["kind"]
	var text: String = reward["text"]
	EventBus.banner.emit("%d 连杀 · %s" % [streak, text], Color("#ffd24a"), 3.2)
	EventBus.feed.emit("【连杀奖励】" + text, Color("#ffd24a"))
	AudioManager.play_ui("announce", -3.0)
	if kind == "uav":
		# 即时生效，不占待呼叫槽
		EventBus.player_uav.emit(UAV_TIME)
		return
	support_kind = kind
	EventBus.support_ready.emit(kind)

## 下一档门槛（HUD 显示进度用）。已到顶返回 -1。
func next_threshold() -> int:
	for t in GameConfig.STREAK_REWARDS:
		if t > streak:
			return t
	return -1

func support_label() -> String:
	match support_kind:
		"mortar": return "迫击炮支援"
		"airstrike": return "空中打击"
		"tank": return "载具增援"
	return ""

## 还在空中、尚未落地的弹数（HUD 与自检用）
func pending_strikes() -> int:
	return _queue.size()

## 排队一发间瞄火力。连杀支援与指挥官的炮兵/导弹都走这里 ——
## 只有一条落弹链路，"支援击杀不计入连杀"这条规则才只需要维护一处
func queue_fire_mission(pos: Vector2, radius: float, inf_dmg: float, veh_dmg: float,
		scale: float, delay: float, owner: Soldier) -> void:
	_queue.append({"at": _clock + delay, "pos": pos, "radius": radius,
		"inf_dmg": inf_dmg, "veh_dmg": veh_dmg, "scale": scale, "owner": owner})

# ============================================================ 呼叫
func _process(delta: float) -> void:
	_clock += delta
	_tick_queue()
	if not MatchState.match_active:
		return
	if Input.is_action_just_pressed("support"):
		call_support()

## 按 X：在当前瞄准位置释放已解锁的支援
## target 显式传入时按传入点释放（留口子给以后的 AI 指挥官 / 自动化自检）
func call_support(target: Vector2 = Vector2.INF) -> bool:
	var p: Soldier = TeamManager.player
	if support_kind == "":
		EventBus.toast.emit("暂无可用支援 · 连杀 3/5/8/12 解锁", Color("#7f97a8"))
		return false
	if p == null or not is_instance_valid(p) or not p.alive:
		EventBus.toast.emit("阵亡状态无法呼叫支援", Color("#7f97a8"))
		return false
	if target == Vector2.INF:
		var view := get_tree().get_first_node_in_group("battlefield_view")
		target = view.mouse_world() if view != null else p.get_global_mouse_position()
	# 屏幕外/极限位置兜一下，避免打到世界之外
	target = target.clamp(Vector2(80, 80), GameConfig.WORLD_SIZE - Vector2(80, 80))
	match support_kind:
		"mortar": _call_mortar(p, target)
		"airstrike": _call_airstrike(p, target)
		"tank": _call_tank(p, target)
	var kind := support_kind
	support_kind = ""
	EventBus.support_used.emit(kind, target)
	return true

# ---------------------------------------------------------------- 三种支援
## 迫击炮：目标点周围散布 8 发，逐发落下。
##
## 散布半径与杀伤半径是配套调的：散布 ±210、杀伤 100 时，单发对某个具体目标的
## 覆盖概率只有约 18%，8 发下来仍然大概率一个都炸不死 —— 那不叫支援，叫放烟花。
## 收窄到 ±120 并让杀伤半径略大于散布步长，才有"覆盖"的意思。
func _call_mortar(p: Soldier, target: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 8:
		var off := Vector2(rng.randf_range(-120.0, 120.0), rng.randf_range(-120.0, 120.0))
		_queue.append({"at": _clock + 0.6 + float(i) * 0.30, "pos": target + off,
			"radius": 130.0, "inf_dmg": 220.0, "veh_dmg": 90.0, "scale": 1.9, "owner": p})
	EventBus.banner.emit("迫击炮支援 · 弹着点已标定", Color("#ff9a3a"), 2.4)
	EventBus.feed.emit("已呼叫迫击炮支援 · 8 发覆盖", Color("#ff9a3a"))
	AudioManager.play_ui("alarm", -4.0)

## 空中打击：沿瞄准方向拉一条弹幕线，逐发命中。
## 弹着间距 128 < 杀伤半径 140，相邻炸点必须重叠 —— 否则地面会漏出一条走位通道，
## 玩家直接从缝里走过去，空袭就成了摆设。
func _call_airstrike(p: Soldier, target: Vector2) -> void:
	var dir: Vector2 = p.aim_dir
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var start: Vector2 = target - dir * 700.0
	for i in 12:
		var pos: Vector2 = start + dir * (float(i) * 128.0)
		pos = pos.clamp(Vector2(60, 60), GameConfig.WORLD_SIZE - Vector2(60, 60))
		_queue.append({"at": _clock + 0.8 + float(i) * 0.10, "pos": pos,
			"radius": 140.0, "inf_dmg": 240.0, "veh_dmg": 150.0, "scale": 2.4, "owner": p})
	EventBus.banner.emit("空中打击 · 轰炸航线已确认", Color("#ff5b4a"), 2.4)
	EventBus.feed.emit("已呼叫空中打击 · 12 发弹幕", Color("#ff5b4a"))
	AudioManager.play_ui("alarm", -3.0)

## 载具增援：在自己后方空投一辆己方装甲车
func _call_tank(p: Soldier, target: Vector2) -> void:
	var map := get_tree().get_first_node_in_group("world_map")
	if map == null or not ("units_root" in map):
		EventBus.toast.emit("战场未就绪，载具增援失败", Color("#7f97a8"))
		return
	var spawn := _find_open_spot(map, target)
	var v: CombatVehicle = VehicleScript.new()
	# 先 setup 再入树：_ready 里要按 kind 选数值表与贴图，顺序反了会拿到默认的坦克数据
	v.setup(p.team, CombatVehicle.Kind.APC)
	map.units_root.add_child(v)
	v.global_position = spawn
	var brain := Node.new()
	brain.set_script(VehicleBrainScript)
	v.add_child(brain)
	EventBus.explosion.emit(spawn, 2.2, "boom")
	EventBus.banner.emit("载具增援已抵达", Color("#57e08a"), 2.4)
	EventBus.feed.emit("载具增援 · 一辆装甲车已投入战场", Color("#57e08a"))

## 空投点：从目标点往外找第一个能站人的位置，找不到就退回目标点
func _find_open_spot(map: Node, target: Vector2) -> Vector2:
	if map.has_method("is_walkable") and map.is_walkable(target):
		return target
	for i in 24:
		var a := float(i) * TAU / 24.0
		var cand: Vector2 = target + Vector2(cos(a), sin(a)) * 140.0
		if cand.x < 60.0 or cand.y < 60.0 or cand.x > GameConfig.WORLD_SIZE.x - 60.0 or cand.y > GameConfig.WORLD_SIZE.y - 60.0:
			continue
		if map.has_method("is_walkable") and not map.is_walkable(cand):
			continue
		return cand
	return target

# ---------------------------------------------------------------- 落弹
func _tick_queue() -> void:
	if _queue.is_empty():
		return
	var due: Array = []
	var rest: Array = []
	for e in _queue:
		if float(e["at"]) <= _clock:
			due.append(e)
		else:
			rest.append(e)
	_queue = rest
	for e in due:
		_detonate(e)

func _detonate(e: Dictionary) -> void:
	var pos: Vector2 = e["pos"]
	var radius: float = e["radius"]
	var owner: Soldier = e["owner"]
	EventBus.explosion.emit(pos, float(e["scale"]), "boom")
	AudioManager.play_2d("boom_big", pos, AudioManager.volume_for(pos, _listener(), 500.0, 3400.0))
	_applying_support = true
	for u in TeamManager.alive_units():
		if owner != null and is_instance_valid(owner) and u.team == owner.team:
			continue
		var d := pos.distance_to(u.global_position)
		if d > radius:
			continue
		u.take_damage(float(e["inf_dmg"]) * (1.0 - d / radius), owner)
	for v in TeamManager.vehicles:
		if not is_instance_valid(v) or not v.alive:
			continue
		if owner != null and is_instance_valid(owner) and v.team == owner.team:
			continue
		var d := pos.distance_to(v.global_position)
		if d <= radius + 40.0:
			v.take_damage(float(e["veh_dmg"]) * (1.0 - d / (radius + 40.0)), owner)
	# 工事也该能吃间瞄火力，否则指挥官的重火力对"架好的阵地"完全无效
	for t in 2:
		var f = CommandOps.forts[t]
		if f == null or not is_instance_valid(f) or not f.alive:
			continue
		if owner != null and is_instance_valid(owner) and f.team == owner.team:
			continue
		var df := pos.distance_to(f.global_position)
		if df <= radius + 30.0:
			f.take_damage(float(e["veh_dmg"]) * 2.0 * (1.0 - df / (radius + 30.0)), owner)
	_applying_support = false

func _listener() -> Vector2:
	if TeamManager.player != null and is_instance_valid(TeamManager.player):
		return TeamManager.player.global_position
	return Vector2.ZERO
