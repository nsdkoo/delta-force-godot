extends Node2D
## ============================================================================
## Main · 应用入口与流程编排
## ----------------------------------------------------------------------------
## ELECT（指挥官选举）-> DEPLOY（干员与部署点）-> FIGHT -> RESULT
## 每个阶段由一段独立的 UI 负责，Main 只做切换。
## ============================================================================

const WorldScene := preload("res://scenes/world/Jinqiu.tscn")

var world: Node2D = null
var battle: BattleManager = null
var hud: HUD = null
var player_ctrl: PlayerController = null
var ui_root: Control = null

var picked_class: int = GameConfig.OpClass.ASSAULT
var picked_spawn: int = 1

func _ready() -> void:
	print("[Main] 三角洲行动 · 全面战场 · 胜者为王 · 启动")
	_self_check()
	world = WorldScene.instantiate()
	add_child(world)
	battle = BattleManager.new()
	add_child(battle)
	battle.setup(world)
	hud = HUD.new()
	add_child(hud)
	hud.battle = battle
	player_ctrl = PlayerController.new()
	add_child(player_ctrl)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui_root)
	EventBus.match_ended.connect(_on_match_ended)
	_parse_shots()
	# 命令行 `-- --auto` 跳过交互直接开打（用于自动化验证）
	var auto := OS.get_cmdline_user_args().has("--auto") or OS.get_cmdline_args().has("--auto")
	if auto:
		_auto_start()
	else:
		_run_elect()

# ---------------------------------------------------------------- 截图开关
## 命令行 `-- --shot=6,14,26`：在指定秒数抓取渲染结果，全部抓完自动退出。
## 直接读 viewport 纹理，不经过桌面截屏，所以不受窗口遮挡与缩放影响，
## 拿到的是逐像素的真实画面，用来做美术比对。
var _shot_times: Array = []
var _shot_idx: int = 0
var _shot_elapsed: float = 0.0

func _parse_shots() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			for s in a.substr(7).split(","):
				_shot_times.append(float(s))
	if not _shot_times.is_empty():
		_shot_times.sort()

func _process(delta: float) -> void:
	if _shot_times.is_empty() or _shot_idx >= _shot_times.size():
		return
	_shot_elapsed += delta
	if _shot_elapsed >= float(_shot_times[_shot_idx]):
		_shot_idx += 1
		_capture_shot(_shot_idx)

func _capture_shot(idx: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists("_shots"):
		dir.make_dir("_shots")
	var path := "res://_shots/s_%02d.png" % idx
	var err := img.save_png(path)
	print("[Shot] %d/%d → %s %s err=%d" % [idx, _shot_times.size(), path, str(img.get_size()), err])
	if _shot_idx >= _shot_times.size():
		await get_tree().create_timer(0.4).timeout
		get_tree().quit()

func _auto_start() -> void:
	MatchState.player_is_commander = true
	MatchState.set_phase(GameConfig.Phase.DEPLOY)
	await get_tree().create_timer(0.15).timeout
	_start_match()
	# 每 10 秒输出一次战局快照，便于无头验证
	while true:
		await get_tree().create_timer(10.0).timeout
		if not MatchState.match_active:
			break
		var seg := clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
		var caps := ""
		for c in GameConfig.CAPTURES:
			caps += "%s:%d/%.0f " % [c["id"], MatchState.captures[c["id"]]["owner"],
				MatchState.captures[c["id"]]["progress"]]
		print("[快照] t=%.0fs 票 %d:%d 存活 %d:%d 击杀 %d 区域 %s | %s" % [
			MatchState.time_left, MatchState.tickets[0], MatchState.tickets[1],
			TeamManager.alive_count(0), TeamManager.alive_count(1),
			_total_kills(), GameConfig.SEGMENTS[seg]["name"], caps])

func _total_kills() -> int:
	var n := 0
	for u in TeamManager.units:
		if is_instance_valid(u):
			n += u.kills
	return n

func _self_check() -> void:
	print("  ├ 单例: EventBus/GameConfig/AssetDB/MatchState/TeamManager/AudioManager 全部就绪")
	print("  ├ 素材 %d 张 · 音效 %d 条" % [AssetDB.tex.size(), AudioManager.streams.size()])
	print("  └ 干员 %d / 武器 %d / 载具 %d / 据点 %d"
		% [GameConfig.OPERATORS.size(), GameConfig.WEAPONS.size(),
			GameConfig.VEHICLES.size(), GameConfig.CAPTURES.size()])

# ============================================================ 选举
func _run_elect() -> void:
	MatchState.set_phase(GameConfig.Phase.ELECT)
	var cands: Array = []
	var pool: Array = BattleManager.CMD_NAMES.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 3:
		var nm: String = pool.pop_at(rng.randi() % pool.size())
		cands.append({"name": nm, "votes": rng.randi_range(4, 14),
			"win": rng.randf_range(0.4, 0.75), "matches": rng.randi_range(40, 180)})
	# 简化的选举面板
	var panel := _make_panel("指挥官选举", "票选指挥官 · 得票最高者指挥全阵营作战", 520.0, 400.0)
	var list := VBoxContainer.new()
	list.position = Vector2(30, 110)
	list.size = Vector2(460, 200)
	list.add_theme_constant_override("separation", 8)
	panel.add_child(list)
	var joined := [false]
	for c in cands:
		var row := Button.new()
		row.text = "%s     胜率 %d%%     对局 %d     得票 %d" % [
			c["name"], int(c["win"] * 100.0), c["matches"], c["votes"]]
		row.custom_minimum_size = Vector2(460, 40)
		row.pressed.connect(func():
			c["votes"] += 3
			EventBus.toast.emit("已投票给 " + c["name"], Color("#ffd24a")))
		list.add_child(row)
	var join_btn := Button.new()
	join_btn.text = "参 与 竞 选"
	join_btn.custom_minimum_size = Vector2(460, 44)
	join_btn.position = Vector2(30, 320)
	join_btn.pressed.connect(func():
		if joined[0]:
			return
		joined[0] = true
		join_btn.disabled = true
		cands.append({"name": "你（自荐）", "votes": 9, "win": 0.62, "matches": 96, "is_player": true})
		EventBus.toast.emit("你已加入竞选，等待团队投票…", Color("#8fc4ff")))
	panel.add_child(join_btn)
	# 倒计时后出结果
	await get_tree().create_timer(5.2).timeout
	var winner: Dictionary = cands[0]
	for c in cands:
		if c["votes"] > winner["votes"]:
			winner = c
	MatchState.player_is_commander = winner.get("is_player", false)
	panel.queue_free()
	EventBus.banner.emit("指挥官：%s（%d 票）" % [winner["name"], winner["votes"]],
		GameConfig.TEAM_COLOR[0], 3.0)
	EventBus.feed.emit("指挥官选举结束 · GTI 指挥官：%s" % winner["name"], Color("#ffd24a"))
	_build_deploy_ui()

# ============================================================ 部署
func _build_deploy_ui() -> void:
	MatchState.set_phase(GameConfig.Phase.DEPLOY)
	var panel := _make_panel("部署", "选择干员与部署点后进入战场", 560.0, 520.0)
	var role := Label.new()
	role.text = "你已被票选为 GTI 指挥官 · 按 M 打开战术地图下达指令" if MatchState.player_is_commander \
		else "你是 GTI 小队队员 · 按指挥官的战术标记行动"
	role.position = Vector2(30, 96)
	role.add_theme_font_size_override("font_size", 14)
	role.add_theme_color_override("font_color", Color("#8fc4ff"))
	panel.add_child(role)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(30, 130)
	grid.size = Vector2(500, 220)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	var buttons: Array = []
	for cls in [GameConfig.OpClass.ASSAULT, GameConfig.OpClass.SUPPORT,
			GameConfig.OpClass.ENGINEER, GameConfig.OpClass.RECON]:
		var op: Dictionary = GameConfig.OPERATORS[cls]
		var b := Button.new()
		b.custom_minimum_size = Vector2(245, 100)
		b.text = "%s  ·  %s\n武器 %s\n大招 %s\nHP %d  机动 %d%%" % [
			op["name"], op["role"], GameConfig.WEAPONS[op["weapon"]]["name"],
			op["skill"], int(op["hp"]), int(op["speed"] * 100.0)]
		b.pressed.connect(func():
			picked_class = cls
			for x in buttons:
				x.modulate = Color(1, 1, 1))
		buttons.append(b)
		grid.add_child(b)

	var spawn_label := Label.new()
	spawn_label.text = "部署点"
	spawn_label.position = Vector2(30, 366)
	spawn_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(spawn_label)
	var spawn_box := HBoxContainer.new()
	spawn_box.position = Vector2(30, 392)
	spawn_box.add_theme_constant_override("separation", 10)
	panel.add_child(spawn_box)
	var opts := ["GTI 前沿基地", "前线集结点"]
	var spawn_btns: Array = []
	for i in opts.size():
		var sb := Button.new()
		sb.text = opts[i]
		sb.custom_minimum_size = Vector2(170, 42)
		var idx := i
		sb.pressed.connect(func(): picked_spawn = idx)
		spawn_box.add_child(sb)
		spawn_btns.append(sb)

	var go := Button.new()
	go.text = "进 入 战 场"
	go.custom_minimum_size = Vector2(500, 54)
	go.position = Vector2(30, 450)
	go.pressed.connect(func():
		panel.queue_free()
		_start_match())
	panel.add_child(go)

func _start_match() -> void:
	MatchState.start_match()
	var pos: Vector2
	if picked_spawn == 0:
		pos = GameConfig.BASE_POS[GameConfig.Team.GTI]
	else:
		var seg: int = clampi(MatchState.unlocked_segment, 0, GameConfig.SEGMENTS.size() - 1)
		pos = Vector2(GameConfig.SEGMENTS[seg]["x"] - 330.0, GameConfig.BASE_POS[GameConfig.Team.GTI].y)
	var p: Soldier = battle.spawn_player(picked_class, pos)
	player_ctrl.attach(p, world.camera)
	world.camera.limit_left = 0
	world.camera.limit_top = 0
	world.camera.limit_right = int(GameConfig.WORLD_SIZE.x)
	world.camera.limit_bottom = int(GameConfig.WORLD_SIZE.y)
	world.camera.make_current()
	EventBus.banner.emit("战斗开始 · 推进 " + GameConfig.CAPTURES[0]["name"], GameConfig.TEAM_COLOR[0], 3.6)
	EventBus.feed.emit("战斗开始 · 20 v 20 指挥官模式 · 无 AI 机器人可刷分", Color("#ffd24a"))
	print("[Main] 战斗开始 · 玩家兵种 %d · 出生 %s" % [picked_class, pos])

# ============================================================ 结算
func _on_match_ended(win_team: int, title: String, subtitle: String) -> void:
	print("[Main] 战局结束 → %s / %s" % [title, subtitle])
	var p: Soldier = TeamManager.player
	var win: bool = p != null and p.team == win_team
	var panel := _make_panel("胜者为王" if win else "战败",
		title + " · " + subtitle, 520.0, 420.0)
	var stats := Label.new()
	var kills: int = p.kills if p != null else 0
	var deaths: int = p.deaths if p != null else 0
	var dmg: int = int(p.damage_done) if p != null else 0
	var owned: int = MatchState.owned_count(GameConfig.Team.GTI)
	stats.text = "击杀  %d        死亡  %d\n总伤害  %d\n据点控制  %d / %d\n最终票数  %d : %d" % [
		kills, deaths, dmg, owned, GameConfig.CAPTURES.size(),
		MatchState.tickets[0], MatchState.tickets[1]]
	stats.position = Vector2(40, 150)
	stats.add_theme_font_size_override("font_size", 20)
	panel.add_child(stats)
	var again := Button.new()
	again.text = "再 战 一 局"
	again.custom_minimum_size = Vector2(440, 54)
	again.position = Vector2(40, 330)
	again.pressed.connect(func():
		panel.queue_free()
		_restart())
	panel.add_child(again)

func _restart() -> void:
	get_tree().reload_current_scene()

# ============================================================ UI 工具
func _make_panel(title: String, subtitle: String, w: float, h: float) -> PanelContainer:
	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.position = (vp - Vector2(w, h)) * 0.5
	panel.size = Vector2(w, h)
	panel.custom_minimum_size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.94)
	sb.border_color = Color(0.47, 0.71, 0.86, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(panel)
	var t := Label.new()
	t.text = title
	t.position = Vector2(30, 30)
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98))
	panel.add_child(t)
	var s := Label.new()
	s.text = subtitle
	s.position = Vector2(32, 68)
	s.add_theme_font_size_override("font_size", 14)
	s.add_theme_color_override("font_color", Color(0.5, 0.59, 0.66))
	panel.add_child(s)
	return panel
