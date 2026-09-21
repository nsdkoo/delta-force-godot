extends Node
class_name BattleManager
## ============================================================================
## BattleManager · 战场生成与编排
## ----------------------------------------------------------------------------
## 生成 6 个据点、20v20 干员、双方指挥官；把 Command 链、小队编制接起来。
## ============================================================================

const SoldierScene := preload("res://scenes/actors/Soldier.tscn")
const VehicleScript := preload("res://scripts/actors/vehicle.gd")
const CapturePointScript := preload("res://scripts/systems/capture_point.gd")
const BotBrainScript := preload("res://scripts/ai/bot_brain.gd")
const CommanderScript := preload("res://scripts/ai/commander.gd")
const VehicleBrainScript := preload("res://scripts/ai/vehicle_brain.gd")

const NAME_POOL := [
	"赤鸦", "苍狼", "雪狐", "铁锤", "夜枭", "疾风", "沙雀", "断刃", "玄铁", "长风",
	"孤鹰", "黑鸦", "白狼", "流火", "青隼", "云雀", "雷霆", "磐石", "寒鸦", "幽兰",
	"苍龙", "星屑", "旅人", "红隼", "影刃", "铜墙", "铁血", "孤星", "游隼", "风暴",
	"荒原", "岩浆", "静水", "执炬", "破晓", "寒霜", "岩隼", "裂空", "朔风", "燎原",
]
const CMD_NAMES := ["战术-灰隼", "战术-长风", "战术-铁砧", "战术-夜航", "战术-猎隼", "战术-磐石"]

# 小队编制：每个小队 4 人，兵种固定搭配
const SQUAD_PATTERN_GTI := [
	GameConfig.OpClass.ASSAULT, GameConfig.OpClass.ENGINEER,
	GameConfig.OpClass.SUPPORT, GameConfig.OpClass.RECON,
]
const SQUAD_PATTERN_HAVOC := [
	GameConfig.OpClass.SUPPORT, GameConfig.OpClass.ENGINEER,
	GameConfig.OpClass.ASSAULT, GameConfig.OpClass.RECON,
]

var world: Node2D = null
var player: Soldier = null
var capture_points: Array = []
var commanders: Array = []
var rng := RandomNumberGenerator.new()

func setup(p_world: Node2D) -> void:
	world = p_world
	rng.seed = 20260529
	TeamManager.reset()
	_spawn_captures()
	_spawn_forces()
	_spawn_vehicles()
	TeamManager.build_squads()
	_setup_commanders()

# ---------------------------------------------------------------- 据点
func _spawn_captures() -> void:
	capture_points.clear()
	for def in GameConfig.CAPTURES:
		var cp := Node2D.new()
		cp.set_script(CapturePointScript)
		world.add_child(cp)
		cp.setup(def)
		capture_points.append(cp)

# ---------------------------------------------------------------- 部队
func _spawn_forces() -> void:
	var used := {}
	# 当前开放区域的据点中心，用来把大部分兵力放到前线，而不是全挤在基地
	var front_caps: Array = []
	for c in GameConfig.CAPTURES:
		if int(c["seg"]) == MatchState.unlocked_segment:
			front_caps.append(c["pos"])
	if front_caps.is_empty():
		front_caps.append(GameConfig.CAPTURES[0]["pos"])
	for team in [GameConfig.Team.GTI, GameConfig.Team.HAVOC]:
		var pattern: Array = SQUAD_PATTERN_GTI if team == GameConfig.Team.GTI else SQUAD_PATTERN_HAVOC
		for i in GameConfig.TEAM_SIZE:
			var op_class: int = pattern[i % pattern.size()]
			var pool := GameConfig.op_ids_for_class(op_class)
			var op_id: String = pool[rng.randi() % pool.size()] if pool.size() > 0 else ""
			var nm := _unique_name(used)
			var s: Soldier = SoldierScene.instantiate()
			s.setup(team, op_class, nm, false, op_id)
			var base: Vector2 = GameConfig.BASE_POS[team]
			# 前 4 人（第一小队）留在基地附近作预备队；其余 16 人撒到当前开放据点周围
			# —— 这样开局就能看到 20v20 的前线对峙，而不是"地图空空只有自己"
			var pos: Vector2
			if i < GameConfig.SQUAD_SIZE:
				var off_x := rng.randf_range(0.0, 190.0) if team == GameConfig.Team.GTI else rng.randf_range(-190.0, 0.0)
				pos = base + Vector2(off_x, rng.randf_range(-520.0, 520.0))
			else:
				var cap: Vector2 = front_caps[i % front_caps.size()]
				# 攻方从据点西侧压上，守方贴在据点东/侧翼
				var side := -1.0 if team == GameConfig.Team.GTI else 1.0
				pos = cap + Vector2(side * rng.randf_range(80.0, 260.0), rng.randf_range(-220.0, 220.0))
			s.position = world.safe_spawn(pos.clamp(Vector2(70, 70), GameConfig.WORLD_SIZE - Vector2(70, 70)))
			world.units_root.add_child(s)
			var brain := Node.new()
			brain.set_script(BotBrainScript)
			s.add_child(brain)

# ---------------------------------------------------------------- 载具
## 双方的载具编成不同：攻方多一台突击车用于快速运兵，
## 守方多一台武直用于反装甲 —— 这和文档里"守方靠载具优势换时间"的思路一致
const VEH_LOADOUT_GTI := [
	[CombatVehicle.Kind.TANK, Vector2(60.0, -260.0)],
	[CombatVehicle.Kind.APC, Vector2(30.0, 260.0)],
	[CombatVehicle.Kind.AA, Vector2(110.0, 40.0)],
	[CombatVehicle.Kind.CAR, Vector2(90.0, -80.0)],
]
const VEH_LOADOUT_HAVOC := [
	[CombatVehicle.Kind.TANK, Vector2(-60.0, -260.0)],
	[CombatVehicle.Kind.APC, Vector2(-30.0, 260.0)],
	[CombatVehicle.Kind.AA, Vector2(-110.0, 40.0)],
	[CombatVehicle.Kind.HELI, Vector2(-120.0, -180.0)],
]

func _spawn_vehicles() -> void:
	for team in [GameConfig.Team.GTI, GameConfig.Team.HAVOC]:
		var base: Vector2 = GameConfig.BASE_POS[team]
		var loadout: Array = VEH_LOADOUT_GTI if team == GameConfig.Team.GTI else VEH_LOADOUT_HAVOC
		for entry in loadout:
			var v := VehicleScript.new()
			# setup 必须在入树之前：_ready 会按 kind 取数值表与贴图，
			# 反过来写的话所有车都会拿到默认的坦克数据
			v.setup(team, entry[0])
			world.units_root.add_child(v)
			v.global_position = base + entry[1]
			var brain := Node.new()
			brain.set_script(VehicleBrainScript)
			v.add_child(brain)

func _unique_name(used: Dictionary) -> String:
	for attempt in 40:
		var nm: String = NAME_POOL[rng.randi() % NAME_POOL.size()] + "-" + str(rng.randi_range(10, 99))
		if not used.has(nm):
			used[nm] = true
			return nm
	return "干员-" + str(rng.randi_range(100, 999))

# ---------------------------------------------------------------- 指挥链
func _setup_commanders() -> void:
	for team in [GameConfig.Team.GTI, GameConfig.Team.HAVOC]:
		var ai := Node.new()
		ai.set_script(CommanderScript)
		var nm: String = CMD_NAMES[rng.randi() % CMD_NAMES.size()]
		var is_player: bool = team == GameConfig.Team.GTI and MatchState.player_is_commander
		# 把"这一方是不是玩家指挥"同步进 MatchState：指挥部系统与 AI 决策
		# 都按 MatchState 判定，只在 AI 内部留一个 setup 时的快照会出现两边不一致
		MatchState.set_commander_player(team, is_player)
		ai.setup(team, nm, is_player)
		add_child(ai)
		commanders.append(ai)
		MatchState.commander_info.append({"name": nm, "is_player": is_player, "team": team})
		EventBus.commander_elected.emit(team, nm, is_player, 0)

# ---------------------------------------------------------------- 玩家
func spawn_player(op_id: String, spawn_pos: Vector2) -> Soldier:
	var s: Soldier = SoldierScene.instantiate()
	s.setup(GameConfig.Team.GTI, int(GameConfig.op(op_id).get("class", 0)), "你", true, op_id)
	s.position = spawn_pos
	world.units_root.add_child(s)
	s.is_commander = MatchState.player_is_commander
	player = s
	TeamManager.player = s
	# 玩家占用 GTI 第一个小队的队长位
	var sq: Squad = TeamManager.squads_of_team(GameConfig.Team.GTI)[0] if TeamManager.squads_of_team(GameConfig.Team.GTI).size() > 0 else null
	if sq != null:
		s.squad_id = sq.id
		if s not in sq.members:
			sq.members.append(s)
		s.is_squad_leader = true
	EventBus.player_respawned.emit(s)
	return s

func get_squads_info(team: int) -> Array:
	var out: Array = []
	for sq in TeamManager.squads_of_team(team):
		var members: Array = []
		for m in sq.members:
			if is_instance_valid(m):
				members.append({"name": m.unit_name, "hp": m.hp, "max_hp": m.max_hp,
					"cls": m.op_class, "alive": m.alive, "is_player": m.is_player})
		out.append({"id": sq.id, "order": sq.order_kind, "label": sq.order_label, "members": members})
	return out

func reset() -> void:
	for cp in capture_points:
		if is_instance_valid(cp):
			cp.queue_free()
	for c in commanders:
		if is_instance_valid(c):
			c.queue_free()
	capture_points.clear()
	commanders.clear()
	MatchState.commander_info.clear()
