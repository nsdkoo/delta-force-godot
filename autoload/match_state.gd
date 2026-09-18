extends Node
## ============================================================================
## MatchState · 战局状态机
## ----------------------------------------------------------------------------
## 负责：阶段流转 / 票数 / 倒计时 / 据点归属 / 区域解锁 / 胜负判定
## 不负责：任何表现（由 EventBus 通知 UI）
## ============================================================================

var phase: int = GameConfig.Phase.BOOT
## 兵力。攻方有实数（180），守方无限用 -1 表示 —— 不要拿它直接做算术
var tickets: Array = [GameConfig.ATTACKER_TICKETS, -1]
var time_left: float = GameConfig.MATCH_TIME
var unlocked_segment: int = 0
var match_active: bool = false
var captures: Dictionary = {}          ## id -> {owner, progress, contested, attackers, defenders}
var commander_info: Array = []         ## [ {name, elected, is_player, votes}, ... ]
var player_is_commander: bool = false
## 各方指挥官是否由玩家担任。用数组而不是单变量是因为"我方"只是视角问题，
## 指挥部系统要能对任意一方问这个问题（弹劾、接管、AI 决策都用它）
var cmd_is_player: Array = [false, false]
var result: Dictionary = {}

# ---- 加时赛 ----
var overtime: bool = false
var overtime_phase: int = 0            ## 1 / 2，0 表示未进入
var overtime_time: float = 0.0
var overtime_point: String = ""        ## 触发加时的那个据点：占下来就算赢
## 烬区彩蛋：C1 厂房挨两发制导导弹后坍塌，成为进攻方默认基地、防守方夺不回
var c1_missile_hits: int = 0
var c1_shattered: bool = false
## 攻方"首次重部署不扣兵力"的剩余时间（阵线增援技能开关）
var free_redeploy: float = 0.0
## 守方复活时间缩减的剩余时间（紧急增援技能开关）
var fast_respawn: float = 0.0

const TICKETS_INFINITE := -1

func _ready() -> void:
	reset()

# ---------------------------------------------------------------- 生命周期
func reset() -> void:
	tickets = [GameConfig.ATTACKER_TICKETS, TICKETS_INFINITE]
	time_left = GameConfig.MATCH_TIME
	unlocked_segment = 0
	match_active = false
	result = {}
	# 注意：这里不清 cmd_is_player。reset() 会被 start_match() 调用，
	# 而"玩家是不是指挥官"是开局选举产生的结果，发生在 start_match 之前 ——
	# 在这里清零的话，选举赢了指挥官、进战场的瞬间就被撤销了，AI 会重新接管。
	# 这一对标志由 battle_manager 建指挥官时初始化，之后只由选举/弹劾改写
	overtime = false
	overtime_phase = 0
	overtime_time = 0.0
	overtime_point = ""
	free_redeploy = 0.0
	fast_respawn = 0.0
	c1_missile_hits = 0
	c1_shattered = false
	captures.clear()
	for c in GameConfig.CAPTURES:
		captures[c["id"]] = {
			"owner": GameConfig.Team.HAVOC,
			"progress": 0.0,
			"contested": false,
			"attackers": 0,
			"defenders": 0,
		}

func set_phase(p: int) -> void:
	if phase == p:
		return
	phase = p
	EventBus.phase_changed.emit(p)

func start_match() -> void:
	reset()
	match_active = true
	set_phase(GameConfig.Phase.FIGHT)
	EventBus.match_started.emit()

func _process(delta: float) -> void:
	if not match_active:
		return
	if free_redeploy > 0.0:
		free_redeploy = maxf(0.0, free_redeploy - delta)
	if fast_respawn > 0.0:
		fast_respawn = maxf(0.0, fast_respawn - delta)
	if overtime:
		_tick_overtime(delta)
		return
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		end_match(GameConfig.Team.HAVOC, "时间耗尽",
			"时间用尽，GTI 未能完成全境控制，防守成功。")

# ---------------------------------------------------------------- 加时赛
## 只要还有攻方人员站在任意据点圈里，第一阶段的时间流速就减半。
## 这条规则把"最后一个点到底归谁"从"看读秒"变成了"看谁还站在圈里"
func _attacker_holds_any_point() -> bool:
	for c in GameConfig.CAPTURES:
		if TeamManager.count_in_radius(c["pos"], c["radius"], GameConfig.Team.GTI) > 0:
			return true
	return false

func _can_enter_overtime() -> bool:
	# 兵力耗尽的那一刻，必须还有人站在点上（处于拉旗状态）才给加时
	return _attacker_holds_any_point()

func _start_overtime() -> void:
	overtime = true
	overtime_phase = 1
	overtime_time = GameConfig.OVERTIME_PHASE1
	# 找出"还站在里面"的那个据点，它就是加时赛的胜负手
	overtime_point = ""
	for c in GameConfig.CAPTURES:
		if TeamManager.count_in_radius(c["pos"], c["radius"], GameConfig.Team.GTI) > 0:
			overtime_point = c["id"]
			break
	EventBus.banner.emit("加时赛 · %s（%.0fs）" % [overtime_point, GameConfig.OVERTIME_PHASE1],
		Color("#ffd24a"), 4.0)
	EventBus.feed.emit("攻方兵力耗尽，但点内仍有人 · 进入加时赛", Color("#ffd24a"))
	EventBus.overtime_started.emit(overtime_phase, overtime_point)
	AudioManager.play_ui("announce", 0.0)

func _tick_overtime(delta: float) -> void:
	var scale := 1.0
	if overtime_phase == 1 and _attacker_holds_any_point():
		scale = GameConfig.OVERTIME_TIME_SCALE
	overtime_time -= delta * scale
	if overtime_time > 0.0:
		return
	if overtime_phase == 1:
		overtime_phase = 2
		overtime_time = GameConfig.OVERTIME_PHASE2
		EventBus.banner.emit("加时赛 第二阶段 · %.0fs" % GameConfig.OVERTIME_PHASE2,
			Color("#ff5b4a"), 3.6)
		EventBus.feed.emit("加时赛进入第二阶段 · 时间不再放缓", Color("#ff9a3a"))
		EventBus.overtime_started.emit(overtime_phase, overtime_point)
		return
	end_match(GameConfig.Team.HAVOC, "加时赛结束",
		"攻方未能在加时赛内拿下据点，哈夫克守住了烬区。")

func overtime_label() -> String:
	if not overtime:
		return ""
	return "加时 %s %.0fs" % ["一阶段" if overtime_phase == 1 else "二阶段", maxf(0.0, overtime_time)]

# ---------------------------------------------------------------- 票数
func tickets_text(team: int) -> String:
	return "∞" if tickets[team] == TICKETS_INFINITE else str(tickets[team])

## 显示用的条形比例。守方无限时恒为满格
func ticket_ratio(team: int) -> float:
	if tickets[team] == TICKETS_INFINITE:
		return 1.0
	return clampf(float(tickets[team]) / float(GameConfig.ATTACKER_TICKETS), 0.0, 1.0)

## 增援。注意攻方兵力只有"被消耗"这一条路，没有回复：
## 攻方手里唯一的资源就是那 180 点，占点与突破的奖励一律折算成阵营积分
## （见 CommandOps）。否则打得越好兵力越涨，"兵力"就不再是压力了
func add_tickets(team: int, amount: int) -> void:
	if tickets[team] == TICKETS_INFINITE or amount > 0:
		return
	tickets[team] = maxi(0, tickets[team] + amount)
	EventBus.ticket_changed.emit(team, tickets[team], amount)

## 阵亡扣兵力。守方无限，所以这里对守方是空操作 ——
## 守方唯一的损失是"丢掉据点"，而不是"死人扣资源"
func spend_ticket(team: int, free: bool = false) -> void:
	if not match_active or free:
		return
	if tickets[team] == TICKETS_INFINITE:
		return
	tickets[team] = maxi(0, tickets[team] - 1)
	EventBus.ticket_changed.emit(team, tickets[team], -1)
	if tickets[team] <= 0:
		_check_win()

## 该阵营本次重部署是否免扣兵力（阵线增援技能）
func redeploy_is_free(team: int) -> bool:
	return team == GameConfig.Team.GTI and free_redeploy > 0.0

## 该阵营的复活冷却（秒）。守方在紧急增援期间大幅缩短
func respawn_delay_for(team: int) -> float:
	var d := GameConfig.RESPAWN_DELAY
	if team == GameConfig.Team.HAVOC and fast_respawn > 0.0:
		d *= 0.4
	return d

# ---------------------------------------------------------------- 据点
func apply_capture(id: String, owner: int, progress: float, contested: bool,
		attackers: int, defenders: int) -> void:
	if not captures.has(id):
		return
	# 锁定点强制归攻方，占领进度不再被战场人数改写
	if is_locked(id):
		owner = GameConfig.Team.GTI
		progress = 100.0
	var st: Dictionary = captures[id]
	var prev_owner: int = st["owner"]
	var prev_prog: float = st["progress"]
	st["owner"] = owner
	st["progress"] = progress
	st["contested"] = contested
	st["attackers"] = attackers
	st["defenders"] = defenders
	if prev_owner != owner or absf(prev_prog - progress) > 0.01:
		EventBus.capture_state_changed.emit(id, owner, progress, contested)
	if prev_owner != owner:
		_on_capture_flipped(id, prev_owner, owner)

func _on_capture_flipped(id: String, from_team: int, to_team: int) -> void:
	var cap := _cap_def(id)
	var nm: String = cap.get("name", id)
	if to_team == GameConfig.Team.GTI:
		# 守方没有兵力池，所以"攻方占点"的收益必须落在别的地方：
		# 一部分进阵营积分（指挥官能换技能），一部分是推进本身
		CommandOps.add_points(GameConfig.Team.GTI, 20.0, "占领 " + nm)
		EventBus.feed.emit("『%s』已被 GTI 占领（阵营积分 +20）" % nm, Color("#4aa8ff"))
	else:
		EventBus.feed.emit("『%s』已被哈夫克夺回" % nm, Color("#ff9a8a"))
	try_advance_segment()
	_check_win()

## C1 被两发制导导弹炸塌之后锁定在攻方手里。
## 这条是烬区这张图的彩蛋：地图机制一旦触发就改变"哪些点还需要争"，
## 比单纯加数值有意思得多
func is_locked(id: String) -> bool:
	return id == "C1" and c1_shattered

func register_missile_hit(pos: Vector2) -> void:
	if c1_shattered:
		return
	var c1 := _cap_def("C1")
	if c1.is_empty() or pos.distance_to(c1["pos"]) > 300.0:
		return
	c1_missile_hits += 1
	EventBus.feed.emit("C1 厂房承受制导导弹轰炸 %d / 2" % c1_missile_hits, Palette.MARK_WARN)
	if c1_missile_hits < 2:
		return
	c1_shattered = true
	EventBus.banner.emit("C1 厂房坍塌 · 成为进攻方基地", Palette.MARK_ATTACK, 4.0)
	EventBus.feed.emit("C1 厂房被两发导弹击穿，坍塌后转为进攻方默认基地，防守方无法夺回",
		Palette.MARK_ATTACK)
	if captures.has("C1"):
		var prev: int = captures["C1"]["owner"]
		captures["C1"]["owner"] = GameConfig.Team.GTI
		captures["C1"]["progress"] = 100.0
		if prev != GameConfig.Team.GTI:
			_on_capture_flipped("C1", prev, GameConfig.Team.GTI)

func _cap_def(id: String) -> Dictionary:
	for c in GameConfig.CAPTURES:
		if c["id"] == id:
			return c
	return {}

func owned_count(team: int) -> int:
	var n := 0
	for id in captures:
		if captures[id]["owner"] == team:
			n += 1
	return n

func progress_of(id: String) -> float:
	return captures.get(id, {}).get("progress", 0.0)

func is_contested(id: String) -> bool:
	return captures.get(id, {}).get("contested", false)

## 区域推进：当前解锁区全占 -> 解锁下一段并奖励票数
func try_advance_segment() -> void:
	if unlocked_segment >= GameConfig.SEGMENTS.size() - 1:
		return
	var seg_index := unlocked_segment
	var all_owned := true
	for c in GameConfig.CAPTURES:
		if c["seg"] == seg_index and captures[c["id"]]["owner"] != GameConfig.Team.GTI:
			all_owned = false
			break
	if not all_owned:
		return
	unlocked_segment += 1
	CommandOps.add_points(GameConfig.Team.GTI, float(GameConfig.SEGMENT_TICKET_BONUS), "区域突破")
	var seg_name: String = GameConfig.SEGMENTS[seg_index]["name"]
	var next_name: String = GameConfig.SEGMENTS[unlocked_segment]["name"]
	EventBus.segment_unlocked.emit(seg_index, seg_name)
	EventBus.feed.emit("区域突破！%s 全境控制 · 解锁 %s（阵营积分 +%d）"
		% [seg_name, next_name, GameConfig.SEGMENT_TICKET_BONUS], Color("#ffd24a"))
	EventBus.objective_changed.emit("当前目标区域：" + next_name)

func current_segment_name() -> String:
	var i := clampi(unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
	return GameConfig.SEGMENTS[i]["name"]

# ---------------------------------------------------------------- 胜负
func _check_win() -> void:
	if not match_active:
		return
	# 加时赛的唯一胜负手：把触发加时的那个据点拿下来。放在最前面判，
	# 因为它优先于"兵力归零"这条常规判负
	if overtime and overtime_point != "" and captures.has(overtime_point) \
			and captures[overtime_point]["owner"] == GameConfig.Team.GTI:
		end_match(GameConfig.Team.GTI, "加时赛夺点",
			"加时赛内拿下 %s，进攻方翻盘。" % overtime_point)
		return
	if owned_count(GameConfig.Team.GTI) == GameConfig.CAPTURES.size():
		end_match(GameConfig.Team.GTI, "全据点占领", "GTI 拿下全部据点，进攻方获胜。")
		return
	if tickets[GameConfig.Team.GTI] <= 0:
		# 已经在加时里就不再重复触发，否则每次有人阵亡都会重开一次加时
		if overtime:
			return
		if _can_enter_overtime():
			_start_overtime()
		else:
			end_match(GameConfig.Team.HAVOC, "攻方兵力耗尽",
				"GTI 有生力量被消耗殆尽，哈夫克守住了烬区。")

func end_match(win_team: int, title: String, subtitle: String) -> void:
	match_active = false
	result = {"win_team": win_team, "title": title, "subtitle": subtitle}
	set_phase(GameConfig.Phase.RESULT)
	EventBus.match_ended.emit(win_team, title, subtitle)

func time_string() -> String:
	var t := int(ceil(time_left))
	return "%02d:%02d" % [t / 60, t % 60]

# ---------------------------------------------------------------- 指挥权
func commander_is_player(team: int) -> bool:
	return cmd_is_player[team]

## 更替某一方的指挥权。GTI 那一格同时同步旧字段 player_is_commander，
## 让还没迁过来的调用方保持正确
func set_commander_player(team: int, value: bool) -> void:
	cmd_is_player[team] = value
	if team == GameConfig.Team.GTI:
		player_is_commander = value
	var p: Soldier = TeamManager.player
	if p != null and is_instance_valid(p) and p.team == team:
		p.is_commander = value
