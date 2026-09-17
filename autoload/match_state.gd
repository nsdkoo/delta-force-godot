extends Node
## ============================================================================
## MatchState · 战局状态机
## ----------------------------------------------------------------------------
## 负责：阶段流转 / 票数 / 倒计时 / 据点归属 / 区域解锁 / 胜负判定
## 不负责：任何表现（由 EventBus 通知 UI）
## ============================================================================

var phase: int = GameConfig.Phase.BOOT
var tickets: Array = [320, 260]
var time_left: float = GameConfig.MATCH_TIME
var unlocked_segment: int = 0
var match_active: bool = false
var captures: Dictionary = {}          ## id -> {owner, progress, contested, attackers, defenders}
var commander_info: Array = []         ## [ {name, elected, is_player, votes}, ... ]
var player_is_commander: bool = false
var result: Dictionary = {}

func _ready() -> void:
	reset()

# ---------------------------------------------------------------- 生命周期
func reset() -> void:
	tickets = [GameConfig.TICKET_MAX[0], GameConfig.TICKET_MAX[1]]
	time_left = GameConfig.MATCH_TIME
	unlocked_segment = 0
	match_active = false
	result = {}
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
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		end_match(GameConfig.Team.HAVOC, "时间耗尽", "时间用尽，GTI 未能完成全境控制，防守成功。")

# ---------------------------------------------------------------- 票数
func add_tickets(team: int, amount: int) -> void:
	tickets[team] = clampi(tickets[team] + amount, 0, 999)
	EventBus.ticket_changed.emit(team, tickets[team], amount)

func spend_ticket(team: int) -> void:
	if not match_active:
		return
	tickets[team] = maxi(0, tickets[team] - 1)
	EventBus.ticket_changed.emit(team, tickets[team], -1)

# ---------------------------------------------------------------- 据点
func apply_capture(id: String, owner: int, progress: float, contested: bool,
		attackers: int, defenders: int) -> void:
	if not captures.has(id):
		return
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
		add_tickets(GameConfig.Team.GTI, GameConfig.CAP_TICKET_GAIN)
		add_tickets(GameConfig.Team.HAVOC, -GameConfig.CAP_TICKET_LOSS)
		EventBus.feed.emit("『%s』已被 GTI 占领（GTI +%d 票 / 哈夫克 -%d 票）"
			% [nm, GameConfig.CAP_TICKET_GAIN, GameConfig.CAP_TICKET_LOSS], Color("#4aa8ff"))
	else:
		EventBus.feed.emit("『%s』已被哈夫克夺回" % nm, Color("#ff9a8a"))
	try_advance_segment()
	_check_win()

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
	add_tickets(GameConfig.Team.GTI, GameConfig.SEGMENT_TICKET_BONUS)
	var seg_name: String = GameConfig.SEGMENTS[seg_index]["name"]
	var next_name: String = GameConfig.SEGMENTS[unlocked_segment]["name"]
	EventBus.segment_unlocked.emit(seg_index, seg_name)
	EventBus.feed.emit("区域突破！%s 全境控制 · 解锁 %s（+%d 票）"
		% [seg_name, next_name, GameConfig.SEGMENT_TICKET_BONUS], Color("#ffd24a"))
	EventBus.objective_changed.emit("当前目标区域：" + next_name)

func current_segment_name() -> String:
	var i := clampi(unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
	return GameConfig.SEGMENTS[i]["name"]

# ---------------------------------------------------------------- 胜负
func _check_win() -> void:
	if not match_active:
		return
	if tickets[GameConfig.Team.GTI] <= 0:
		end_match(GameConfig.Team.HAVOC, "攻方票数耗尽", "GTI 有生力量被消耗殆尽，哈夫克守住了烬区。")
	elif tickets[GameConfig.Team.HAVOC] <= 0:
		end_match(GameConfig.Team.GTI, "守方票数耗尽", "哈夫克防线全面崩溃，GTI 完成全境控制。")
	elif owned_count(GameConfig.Team.GTI) == GameConfig.CAPTURES.size():
		end_match(GameConfig.Team.GTI, "全据点占领", "GTI 速通占领全部据点，进攻方获胜。")

func end_match(win_team: int, title: String, subtitle: String) -> void:
	match_active = false
	result = {"win_team": win_team, "title": title, "subtitle": subtitle}
	set_phase(GameConfig.Phase.RESULT)
	EventBus.match_ended.emit(win_team, title, subtitle)

func time_string() -> String:
	var t := int(ceil(time_left))
	return "%02d:%02d" % [t / 60, t % 60]
