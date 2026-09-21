extends Node2D
## ============================================================================
## Main · 应用入口与流程编排
## ----------------------------------------------------------------------------
## 应用外壳（主菜单/设置/暂停）由 AppShell 负责，对局内部流程由这里编排：
##   BOOT -> MAIN_MENU -> ELECT -> DEPLOY -> FIGHT -> RESULT
## 两套状态分开：AppState 管"应用级"，MatchState.phase 管"对局级"。
## 这样暂停菜单能冻结对局，而主菜单背后的战场还能继续跑（attract mode）。
## ============================================================================

const WorldScene := preload("res://scenes/world/Jinqiu.tscn")
const SelftestScript := preload("res://scripts/systems/selftest.gd")
const AppShellScript := preload("res://scripts/ui/app_shell.gd")
const BattlefieldScript := preload("res://scripts/visuals/battlefield_view.gd")

var world: Node2D = null
var battle: BattleManager = null
var hud: HUD = null
var player_ctrl: PlayerController = null
var ui_root: Control = null
var ui_layer: CanvasLayer = null
var shell: CanvasLayer = null
var battlefield: BattlefieldView = null

var picked_op: String = "redwolf"
var picked_spawn: int = 1
var _demo_zoom: float = 0.0

func _ready() -> void:
	_enforce_window_size()
	print("[Main] 三角洲行动 · 全面战场 · 胜者为王 · 启动")
	_self_check()
	world = WorldScene.instantiate()
	add_child(world)
	battle = BattleManager.new()
	add_child(battle)
	battle.setup(world)
	world.visible = false
	battlefield = BattlefieldScript.new()
	add_child(battlefield)
	battlefield.setup(world)
	hud = HUD.new()
	add_child(hud)
	hud.battle = battle
	player_ctrl = PlayerController.new()
	add_child(player_ctrl)
	# 面板层必须压过 HUD（HUD 是 CanvasLayer 10）。
	# 结算页 / 部署页是半透明大面板，画在 HUD 下面会被血条、雷达、击杀播报穿透。
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 一份主题下发到整棵面板树：所有 Label / Button 自动拿到木牌金边与中文系统字体
	ui_root.theme = UiTheme.build()
	ui_layer.add_child(ui_root)
	shell = AppShellScript.new()          ## 脚本继承 CanvasLayer，直接 new 才能拿到正确类型
	add_child(shell)
	EventBus.match_ended.connect(_on_match_ended)
	_parse_shots()
	var args := OS.get_cmdline_user_args()
	# 命令行 `-- --selftest`：无头自检，逐条断言并返回退出码
	if args.has("--selftest"):
		var runner := Node.new()
		runner.set_script(SelftestScript)
		add_child(runner)
		runner.run(self)
		return
	# 命令行 `-- --scoreboard`：强制展开计分板（截图用）
	if args.has("--scoreboard"):
		hud.force_scoreboard = true
	# 命令行 `-- --offscreen`：把窗口挪到屏幕外再截屏。
	# 教练在打真游戏的时候，任何弹到前台来的窗口都会把他切出对局 ——
	# 挪到屏幕外既能正常渲染（截图不走样），又不会盖住他的画面
	if args.has("--offscreen"):
		DisplayServer.window_set_position(Vector2i(2600, 60))
	# 命令行 `-- --zoom=3`：把相机推近，用于逐像素检查单位与建筑的描边（美术走查用）
	for a in args:
		if a.begins_with("--zoom="):
			_demo_zoom = float(a.substr(7))
	# 命令行 `-- --demo`：定型演示场景（直接进战斗 + 上车 + 预置连杀），截图用
	if args.has("--demo"):
		_demo_setup()
		return
	# 命令行 `-- --auto` 跳过交互直接开打（用于自动化验证）
	if args.has("--auto") or OS.get_cmdline_args().has("--auto"):
		AppState.reset_to_boot()
		AppState.goto(AppState.State.PLAYING)
		_auto_start()
		return
	# 命令行 `-- --settings` / `-- --pause`：直接摆到对应界面（界面走查截图用）
	if args.has("--settings"):
		AppState.reset_to_boot()
		hud.visible = false
		player_ctrl.shell_mode = true
		AppState.goto(AppState.State.MAIN_MENU)
		AppState.goto(AppState.State.SETTINGS)
		return
	if args.has("--pause"):
		AppState.reset_to_boot()
		AppState.goto(AppState.State.PLAYING)
		_auto_start()
		await get_tree().create_timer(3.0).timeout
		AppState.goto(AppState.State.PAUSED)
		return
	# 默认路径：先进主菜单。战场已经装配好并在后台跑着，作为菜单的实时背景
	AppState.reset_to_boot()
	hud.visible = false
	player_ctrl.shell_mode = true
	AppState.goto(AppState.State.MAIN_MENU)

# ============================================================ 外壳回调
## 主菜单点"开始游戏"
func begin_new_match() -> void:
	shell.clear()
	hud.visible = true
	player_ctrl.shell_mode = false
	# 相机交还给玩法：先推回正常缩放，否则菜单的 attract 缩放会留到开局
	player_ctrl.zoom_override = _demo_zoom
	AppState.goto(AppState.State.BRIEFING)
	_run_elect()

## 暂停页点"返回主菜单"：直接重载场景。
## 对局里改过的东西太多（单位、载具、工事、指挥部状态），逐个回滚一定漏；
## 重载场景是唯一能保证"干净回到主菜单"的做法
func back_to_menu() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

## Esc：对局中开暂停菜单。主菜单/设置页不响应（那两个页面有自己的返回按钮）
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if AppState.state == AppState.State.PLAYING:
		AppState.goto(AppState.State.PAUSED)
		get_viewport().set_input_as_handled()

## 演示场景：把玩家放进载具并推到"8 连杀 · 空袭待呼叫"，
## 这样一张截图里同时能看到载具面板、连杀条与支援提示。
## 只用于截图与人工走查，不参与正常流程。
func _demo_setup() -> void:
	print("[Demo] 视口 %s · 窗口 %s" % [
		str(get_viewport().get_visible_rect().size), str(DisplayServer.window_get_size())])
	MatchState.set_commander_player(GameConfig.Team.GTI, true)
	MatchState.set_phase(GameConfig.Phase.DEPLOY)
	await get_tree().create_timer(0.2).timeout
	_start_match()
	await get_tree().create_timer(0.4).timeout
	var p: Soldier = TeamManager.player
	if p != null and is_instance_valid(p):
		var v: CombatVehicle = TeamManager.nearest_friendly_vehicle(p.global_position, p.team, 4000.0)
		if v != null:
			p.global_position = v.global_position + Vector2(52.0, 0.0)
			await get_tree().create_timer(0.15).timeout
			if v.enter(p):
				player_ctrl.vehicle = v
				v.manual_gun = true
		# 触发第 8 档奖励：连杀条会显示"空袭待呼叫"
		p.streak = 8
		EventBus.player_streak_changed.emit(8)

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
	MatchState.set_commander_player(GameConfig.Team.GTI, true)
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

## project.godot 里的 display/window/size/window_width_override=700 在 Godot 4.7.2 上
## 不生效：实测启动出来的窗口是 1600x394（宽度覆盖被忽略、只吃到了高度覆盖），
## 逻辑视口被 aspect=expand 拉成 3654x900，画面成了 4:1 的超宽条。
## 这里在启动时显式设一次。目标尺寸 700x394 与 1600x900 同比例，
## 逻辑分辨率仍然是 1600x900，UI 布局与坐标计算完全不受影响。
const BROKEN_DEFAULT_WINDOW := Vector2i(1600, 394)
const INTENDED_WINDOW := Vector2i(700, 394)

func _enforce_window_size() -> void:
	if OS.has_feature("headless"):
		return
	# 只纠正这一个特征值：宽度 1600 来自 viewport_width、高度 394 来自 height_override，
	# 正是"宽度覆盖没生效"的指纹。命令行 --resolution 给的任何其它尺寸都不会被动到，
	# 截图与美术比对仍然可以自由指定分辨率。
	if DisplayServer.window_get_size() != BROKEN_DEFAULT_WINDOW:
		return
	print("[Main] 窗口尺寸校正 %s -> %s" % [str(BROKEN_DEFAULT_WINDOW), str(INTENDED_WINDOW)])
	DisplayServer.window_set_size(INTENDED_WINDOW)

func _self_check() -> void:
	print("  ├ 单例: EventBus/GameConfig/AssetDB/MatchState/TeamManager/AudioManager/StreakManager 全部就绪")
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
	MatchState.set_commander_player(GameConfig.Team.GTI, winner.get("is_player", false))
	panel.queue_free()
	EventBus.banner.emit("指挥官：%s（%d 票）" % [winner["name"], winner["votes"]],
		GameConfig.TEAM_COLOR[0], 3.0)
	EventBus.feed.emit("指挥官选举结束 · GTI 指挥官：%s" % winner["name"], Color("#ffd24a"))
	_build_deploy_ui()

# ============================================================ 部署
func _build_deploy_ui() -> void:
	MatchState.set_phase(GameConfig.Phase.DEPLOY)
	# 面板高度必须够装下九宫格 + 出生点 + 进场按钮。
	# 九宫格 3 行 x 128 + 2 x 8 间距 = 400，从 y=126 开始到 y=526 才结束，
	# 所以出生点那一组只能排在 540 之后 —— 之前把它写死在 486，
	# 直接压在了第三排（露娜/银翼/麦小文）上
	var panel := _make_panel("部署", "选择干员与部署点后进入战场", 880.0, 716.0)
	var role := Label.new()
	role.text = "你已被票选为 GTI 指挥官 · 按 5/6 放技能、7/8 呼叫重火力、B 架设工事" 		if MatchState.player_is_commander 		else "你是 GTI 小队队员 · 按指挥官的战术标记行动"
	role.position = Vector2(30, 96)
	role.add_theme_font_size_override("font_size", 14)
	role.add_theme_color_override("font_color", Palette.UI_GOLD_LIGHT)
	panel.add_child(role)

	# 九名干员按职业分三列排开。文档的推荐阵容是 8 突击 / 6 支援 / 3 工程 / 3 侦察，
	# 所以同一兵种下必须真的有得选，"职业搭配"才不是一句空话
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(30, 126)
	grid.size = Vector2(820, 400)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(grid)
	var buttons: Array = []
	for cls in [GameConfig.OpClass.ASSAULT, GameConfig.OpClass.SUPPORT,
			GameConfig.OpClass.ENGINEER, GameConfig.OpClass.RECON]:
		for id in GameConfig.op_ids_for_class(cls):
			var op: Dictionary = GameConfig.op(id)
			var b := Button.new()
			b.custom_minimum_size = Vector2(268, 128)
			b.text = "%s · %s
武器 %s
技能 %s
HP %d  机动 %d%%" % [
				op["name"], GameConfig.CLASS_NAME_CN[cls], GameConfig.WEAPONS[op["weapon"]]["name"],
				op["skill"], int(op["hp"]), int(op["speed"] * 100.0)]
			b.tooltip_text = op["desc"]
			var oid: String = id
			b.pressed.connect(func():
				picked_op = oid
				for x in buttons:
					x.modulate = Color(1, 1, 1)
				b.modulate = Color(1.25, 1.12, 0.72))
			buttons.append(b)
			grid.add_child(b)
	buttons[0].modulate = Color(1.25, 1.12, 0.72)

	var spawn_label := Label.new()
	spawn_label.text = "部署点"
	spawn_label.position = Vector2(30, 546)
	spawn_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(spawn_label)
	var spawn_box := HBoxContainer.new()
	spawn_box.position = Vector2(30, 572)
	spawn_box.add_theme_constant_override("separation", 10)
	panel.add_child(spawn_box)
	var opts := ["GTI 前沿基地", "前线集结点"]
	for i in opts.size():
		var sb := Button.new()
		sb.text = opts[i]
		sb.custom_minimum_size = Vector2(170, 42)
		var idx := i
		sb.pressed.connect(func(): picked_spawn = idx)
		spawn_box.add_child(sb)

	var go := Button.new()
	go.text = "进 入 战 场"
	go.custom_minimum_size = Vector2(820, 54)
	go.position = Vector2(30, 632)
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
		var front: Vector2 = GameConfig.CAPTURES[seg * 2]["pos"]
		pos = world.safe_spawn(front + Vector2(-260, 130))
	var p: Soldier = battle.spawn_player(picked_op, pos)
	# `-- --artview`：把玩家挪到城堡/村落前，方便截王国保卫战风建筑对照
	if OS.get_cmdline_user_args().has("--artview"):
		p.global_position = Vector2(2050.0, 1280.0)
		pos = p.global_position
	player_ctrl.attach(p, world.camera)
	# 美术走查用的镜头推近，对所有启动模式都生效（--auto 也能放大看单位）
	player_ctrl.zoom_override = _demo_zoom
	world.camera.limit_left = 0
	world.camera.limit_top = 0
	world.camera.limit_right = int(GameConfig.WORLD_SIZE.x)
	world.camera.limit_bottom = int(GameConfig.WORLD_SIZE.y)
	world.camera.make_current()
	EventBus.banner.emit("战斗开始 · 推进 " + GameConfig.CAPTURES[0]["name"], GameConfig.TEAM_COLOR[0], 3.6)
	EventBus.feed.emit("战斗开始 · 20 v 20 离线演练 · 其余队员由 AI 控制", Color("#ffd24a"))
	var vk := {}
	for v in TeamManager.vehicles:
		if is_instance_valid(v):
			vk[v.display_name()] = int(vk.get(v.display_name(), 0)) + 1
	print("[Main] 战斗开始 · 干员 %s · 出生 %s · 载具 %s" % [
		GameConfig.op(picked_op)["name"], pos, str(vk)])
	AppState.goto(AppState.State.PLAYING)

# ============================================================ 结算
## 结算详情页：个人战绩 + 双方对比。
## 之前这里只有五行数字，看不出"我打得怎么样" —— 尤其看不到连杀与队伍层面
## 的差距，所以这一版把个人生涯项和两支队伍的六项指标并排摆出来。
func _on_match_ended(win_team: int, title: String, subtitle: String) -> void:
	print("[Main] 战局结束 → %s / %s" % [title, subtitle])
	var p: Soldier = TeamManager.player
	var win: bool = p != null and p.team == win_team
	var panel := _make_panel("胜者为王" if win else "战败", title + " · " + subtitle, 980.0, 620.0)

	# ---- 左栏：个人战绩 ----
	_add_section(panel, "个人战绩", 40.0, 122.0)
	var kills: int = p.kills if p != null else 0
	var deaths: int = p.deaths if p != null else 0
	var dmg: int = int(p.damage_done) if p != null else 0
	var score: int = int(p.score) if p != null else 0
	var best: int = p.best_streak if p != null else 0
	var cls_name: String = GameConfig.CLASS_NAME_CN[p.op_class] if p != null else "—"
	var kd: String = "—" if deaths == 0 else "%.2f" % (float(kills) / float(deaths))
	var rows := [
		["干员", cls_name, Color(0.84, 0.9, 0.94)],
		["击杀", str(kills), Color("#ffd24a")],
		["死亡", str(deaths), Color(0.72, 0.8, 0.86)],
		["K / D", kd, Color("#8fc4ff")],
		["总伤害", str(dmg), Color(0.72, 0.8, 0.86)],
		["得分", str(score), Color("#57e08a")],
		["最高连杀", "%d 连杀" % best, Color("#ff9a3a")],
	]
	var ry := 158.0
	for r in rows:
		_add_row(panel, 48.0, ry, r[0], r[1], r[2])
		ry += 34.0

	# ---- 右栏：双方对比 ----
	_add_section(panel, "双方对比", 520.0, 122.0)
	var gti_kills := _team_total_kills(GameConfig.Team.GTI)
	var havoc_kills := _team_total_kills(GameConfig.Team.HAVOC)
	var elapsed := int(GameConfig.MATCH_TIME - MatchState.time_left)
	var compare := [
		["兵力", "%s  :  %s" % [MatchState.tickets_text(0), MatchState.tickets_text(1)], Color(0.84, 0.9, 0.94)],
		["据点控制", "%d / %d" % [MatchState.owned_count(GameConfig.Team.GTI), GameConfig.CAPTURES.size()], Color("#8fc4ff")],
		["区域推进", MatchState.current_segment_name(), Color("#ffd24a")],
		["总击杀", "%d  :  %d" % [gti_kills, havoc_kills], Color(0.84, 0.9, 0.94)],
		["存活人数", "%d  :  %d" % [TeamManager.alive_count(0), TeamManager.alive_count(1)], Color(0.72, 0.8, 0.86)],
		["在场载具", "%d  :  %d" % [TeamManager.alive_vehicle_count(0), TeamManager.alive_vehicle_count(1)], Color(0.72, 0.8, 0.86)],
		["战局时长", "%02d:%02d" % [elapsed / 60, elapsed % 60], Color(0.5, 0.59, 0.66)],
	]
	ry = 158.0
	for r in compare:
		_add_row(panel, 528.0, ry, r[0], r[1], r[2])
		ry += 34.0

	# ---- 四维能力标签 ----
	# 官方按对局表现结算「指挥 / 载具 / 步战 / 救援」四个维度并给金/银/铜。
	# 这里用同一套口径：每个维度只有一个可累加的可观测量，不做复合加权 ——
	# 复合加权看着精细，实际上玩家永远不知道自己为什么只拿了铜
	_add_section(panel, "能力标签", 520.0, 402.0)
	var pv: Soldier = p
	var tags := [
		["指挥能力", GameConfig.Team.GTI, _tag(float(CommandOps.marks_done[GameConfig.Team.GTI]) * 300.0
			+ CommandOps.points[GameConfig.Team.GTI] * 0.1, 600.0, 300.0)],
		["载具能力", 0, _tag(pv.vehicle_damage if pv != null else 0.0, 2500.0, 1000.0)],
		["步战能力", 1, _tag((pv.infantry_damage if pv != null else 0.0) * 0.4, 1200.0, 500.0)],
		["救援能力", 2, _tag(float(pv.revives if pv != null else 0) * 400.0, 800.0, 400.0)],
	]
	var tx := 528.0
	for t in tags:
		_add_row(panel, tx, ry, t[0], t[2], _tag_color(t[2]))
		tx += 152.0
	ry += 34.0

	# ---- 结论 ----
	var verdict := Label.new()
	verdict.text = ("GTI 达成战役目标 · " if win_team == GameConfig.Team.GTI else "哈夫克守住烬区 · ") + title
	verdict.position = Vector2(48, 424)
	verdict.add_theme_font_size_override("font_size", 17)
	verdict.add_theme_color_override("font_color",
		GameConfig.TEAM_COLOR[win_team])
	panel.add_child(verdict)
	var hint := Label.new()
	hint.text = "按 Tab 在对局中可随时查看完整计分板"
	hint.position = Vector2(48, 452)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.5, 0.59, 0.66))
	panel.add_child(hint)

	var again := Button.new()
	again.text = "再 战 一 局"
	again.custom_minimum_size = Vector2(900, 56)
	again.position = Vector2(40, 510)
	again.pressed.connect(func():
		panel.queue_free()
		_restart())
	panel.add_child(again)

## 单维度评级。金 / 银 / 铜 三档，取不到银线就是铜
func _tag(value: float, gold: float, silver: float) -> String:
	if value >= gold:
		return "金"
	if value >= silver:
		return "银"
	return "铜"

func _tag_color(tag: String) -> Color:
	match tag:
		"金": return Color("#ffc42e")
		"银": return Color("#cfd8e0")
	return Color("#c98a4b")

func _team_total_kills(team: int) -> int:
	var n := 0
	for u in TeamManager.all_units(team):
		n += u.kills
	return n

func _add_section(panel: Control, text: String, x: float, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Palette.UI_GOLD_LIGHT)
	panel.add_child(l)
	var line := ColorRect.new()
	line.color = Color(Palette.UI_GOLD.r, Palette.UI_GOLD.g, Palette.UI_GOLD.b, 0.45)
	line.position = Vector2(x, y + 24)
	line.size = Vector2(420, 2)
	panel.add_child(line)

func _add_row(panel: Control, x: float, y: float, label: String, value: String, col: Color) -> void:
	var l := Label.new()
	l.text = label
	l.position = Vector2(x, y)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	panel.add_child(l)
	var v := Label.new()
	v.text = value
	v.position = Vector2(x + 118, y)
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", col)
	panel.add_child(v)

func _restart() -> void:
	get_tree().reload_current_scene()

# ============================================================ UI 工具
## 造一块面板。
##
## 这里必须是 Panel 而不是 PanelContainer：PanelContainer 是容器，它在布局时会
## 把每一个直接子节点都 fit 进自己的内容矩形，于是调用方写下的
## `label.position = Vector2(30, 30)`、`box.position = Vector2(30, 110)` 全部作废 ——
## 选举面板里标题、候选人列表、参选按钮会被压到同一个位置上。
## 这些面板要的是"绝对定位 + 一个边框底"，用 Panel 就对了。
func _make_panel(title: String, subtitle: String, w: float, h: float) -> Panel:
	var vp := get_viewport().get_visible_rect().size
	var panel := Panel.new()
	panel.position = (vp - Vector2(w, h)) * 0.5
	panel.size = Vector2(w, h)
	panel.custom_minimum_size = Vector2(w, h)
	var sb := Palette.panel_style(0.96, 3.0)
	panel.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(panel)
	var t := Label.new()
	t.text = title
	t.position = Vector2(30, 30)
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Palette.UI_TEXT)
	panel.add_child(t)
	var s := Label.new()
	s.text = subtitle
	s.position = Vector2(32, 68)
	s.add_theme_font_size_override("font_size", 14)
	s.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	panel.add_child(s)
	return panel
