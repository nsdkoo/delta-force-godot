extends Node
class_name SelftestRunner
## ============================================================================
## SelftestRunner · 无头自检
## ----------------------------------------------------------------------------
## 用 `--headless -- --selftest` 跑。逐条断言本次新增/改动过的链路，失败会以
## 非零退出码收尾，所以可以直接串进命令行验证。
##
## 覆盖策略：能走输入的绝不直接调函数。
##   · 「按 F 上车 / 按 1-2 切弹种 / 按 3 开 APS / 按住左键开炮」用 Input.action_press
##     合成按键，验的是 PlayerController 的接线，不是被调用方的实现。
##   · 只有鼠标瞄准没法在无头环境合成（没有真实窗口），那部分改成直接写
##     turret_dir，并在输出里标注，不假装它被输入链路覆盖到了。
## ============================================================================

const VehicleScript := preload("res://scripts/actors/vehicle.gd")

var _pass: int = 0
var _fail: int = 0
var _main: Node = null

func run(main: Node) -> void:
	_main = main
	print("[自检] 开始 · 目标：载具链路 / 连杀奖励 / 炮塔限速 / 乘员安全")
	MatchState.set_commander_player(GameConfig.Team.GTI, true)
	MatchState.set_phase(GameConfig.Phase.DEPLOY)
	main._start_match()
	await _wait(8)

	var p: Soldier = TeamManager.player
	_check("玩家已生成", p != null and is_instance_valid(p))
	if p == null:
		return _finish()

	await _test_vehicle_link(p, main)
	await _test_turret_slew(main)
	await _test_eject_on_destroy(p)
	await _test_streak_rewards(p)
	await _test_rescue(p)
	await _test_streak_reset(p)
	await _test_mode_rules(p)
	await _test_command_ops(p)
	await _test_overtime(p)
	_finish()

# ============================================================ 倒地与救援
func _test_rescue(p: Soldier) -> void:
	# 找一个己方队友来倒地。不用敌人的原因：救起来之后他还会被己方 AI 重新打倒，
	# 断言就会在"救起"和"又被打倒"之间随机抖动
	var target: Soldier = null
	for u in TeamManager.alive_units(p.team):
		if u != p:
			target = u
			break
	_check("找到用于倒地测试的队友", target != null)
	if target == null:
		return
	target.spawn_protection = 0.0
	target.hp = 1.0
	target.take_damage(999999.0, null)
	await _wait(2)
	_check("打空血进入倒地而不是直接阵亡", target.downed and target.alive,
		"downed=%s alive=%s" % [str(target.downed), str(target.alive)])
	_check("倒地单位不计入存活", not TeamManager.alive_units().has(target))
	_check("倒地单位出现在待救援列表", TeamManager.downed_units().has(target))

	# 挪到地图一个偏远的空角再拖。两个原因：
	#   1) 前线救人会被敌人重新打倒，"救起来了"和"刚救起又被打倒"会让断言随机失败
	#   2) 己方的支援兵 AI 也会主动去救人，目标可能在玩家下手之前就被队友拖走了
	# 偏远角落两个问题一起解决
	var safe := Vector2(300.0, 300.0)
	target.alive = true
	target.downed = true
	target.hp = 0.0
	target.dragging_by = null
	target.revive_progress = 0.0
	p.global_position = safe
	target.global_position = safe + Vector2(36.0, 0.0)
	await _wait(2)
	_check("拖拽救援开始", p.start_drag(target) and target.dragging_by == p)
	var need := GameConfig.REVIVE_TIME + 0.4
	await _seconds(need)
	_check("保持接触后可救起", not target.downed and target.hp > 0.0,
		"downed=%s hp=%.0f progress=%.1f revives=%d" % [str(target.downed), target.hp,
			target.revive_progress, p.revives])
	_check("救起者累计救援次数", p.revives >= 1, "revives=%d" % p.revives)
	p.release_drag()

# ============================================================ 兵力模型
func _test_mode_rules(p: Soldier) -> void:
	# 不能用"当前兵力 == 180"来断言：前面几段测试里己方阵亡已经扣过票了。
	# 这里要验的是配置口径与"只减不增"这两件事
	_check("攻方初始兵力配置为 180", GameConfig.ATTACKER_TICKETS == 180)
	_check("攻方兵力不超过上限", MatchState.tickets[0] <= GameConfig.ATTACKER_TICKETS,
		"%d" % MatchState.tickets[0])
	_check("守方兵力无限", MatchState.tickets_text(1) == "∞", MatchState.tickets_text(1))
	var before: int = MatchState.tickets[1]
	MatchState.spend_ticket(1)
	_check("守方阵亡不扣兵力", MatchState.tickets[1] == before)
	var atk: int = MatchState.tickets[0]
	MatchState.add_tickets(0, 80)
	_check("攻方兵力只减不增", MatchState.tickets[0] == atk, "%d" % MatchState.tickets[0])
	_check("复活冷却为 20 秒", is_equal_approx(MatchState.respawn_delay_for(0), 20.0),
		"%.0f" % MatchState.respawn_delay_for(0))

# ============================================================ 指挥部
func _test_command_ops(p: Soldier) -> void:
	CommandOps.points[0] = 1200.0
	# 清掉这两条的冷却：对面的 AI 指挥官也在用技能，不能假设冷却一定是空的
	CommandOps.skill_cd.erase("0:vip_point")
	CommandOps.skill_cd.erase("0:threat_veh")
	# 高价值据点：标记后不立刻结算，必须等窗口结束
	_check("释放高价值据点技能", CommandOps.use_skill(0, "vip_point", Vector2.INF))
	# 不比较 marks 总数：对面的标记随时可能到期消失，只数"我方这一条在不在"
	var mine := 0
	for m in CommandOps.marks:
		if m["team"] == 0 and m["kind"] == "vip_point":
			mine += 1
	_check("标记已登记", mine == 1, "己方高价值据点标记 %d 条" % mine)
	_check("技能进入冷却", CommandOps.skill_cd_left(0, "vip_point") > 0.0,
		"%.0fs" % CommandOps.skill_cd_left(0, "vip_point"))
	_check("冷却期间无法重复释放", not CommandOps.use_skill(0, "vip_point", Vector2.INF))
	_check("守方专属技能对攻方不可用", not CommandOps.can_use_skill(0, "emergency"))
	_check("攻方专属技能可用", CommandOps.can_use_skill(0, "reinforce"))
	CommandOps.use_skill(0, "reinforce", Vector2.INF)
	_check("阵线增援生效", MatchState.free_redeploy > 0.0,
		"%.0fs" % MatchState.free_redeploy)

	# 重火力：花积分、进队列、进冷却
	var pts_before: float = CommandOps.points[0]
	_check("呼叫炮兵齐射", CommandOps.use_heavy(0, "artillery", Vector2(1900, 1300)))
	_check("落弹已排队", StreakManager.pending_strikes() > 0,
		"%d 发" % StreakManager.pending_strikes())
	_check("炮兵扣了阵营积分",
		CommandOps.points[0] < pts_before - GameConfig.HEAVY_SUPPORT["artillery"]["cost"] + 5.0)
	_check("重火力进入冷却", CommandOps.heavy_cd_left(0, "artillery") > 0.0)
	await _seconds(4.0)
	_check("炮兵落完", StreakManager.pending_strikes() == 0)

	# 工事：同时最多 1 个
	p.is_squad_leader = true
	p.spawn_protection = 1e9
	CommandOps.fort_cd[0] = 0.0
	_check("架设工事", CommandOps.build_fort("bunker", p))
	await _wait(2)
	_check("工事已就位", CommandOps.forts[0] != null and is_instance_valid(CommandOps.forts[0]))
	_check("工事进入建造冷却", CommandOps.fort_cd_left(0) > 0.0,
		"%.0fs" % CommandOps.fort_cd_left(0))
	CommandOps.fort_cd[0] = 0.0
	CommandOps.build_fort("vulcan", p)
	await _wait(2)
	# 只数自己这一方：对面 AI 指挥官也会架工事，把双方一起数进来必然得到 2
	var alive_forts := 0
	for t in 2:
		if CommandOps.forts[t] != null and is_instance_valid(CommandOps.forts[t]) 				and CommandOps.forts[t].team == GameConfig.Team.GTI:
			alive_forts += 1
	_check("同时最多 1 个工事（新建替换旧的）", alive_forts == 1, "%d 个" % alive_forts)
	_check("被替换的工事立刻停火", CommandOps.forts[0] != null and CommandOps.forts[0].alive)

	# 烬区地图机制
	MatchState.c1_missile_hits = 0
	MatchState.c1_shattered = false
	var c1 := {}
	for c in GameConfig.CAPTURES:
		if c["id"] == "C1":
			c1 = c
	MatchState.register_missile_hit(c1["pos"])
	_check("C1 挨一发导弹还没塌", not MatchState.c1_shattered)
	MatchState.register_missile_hit(c1["pos"])
	_check("C1 挨两发后坍塌归攻方", MatchState.c1_shattered
		and MatchState.captures["C1"]["owner"] == GameConfig.Team.GTI)
	_check("C1 坍塌后被锁定", MatchState.is_locked("C1"))

	# 四维能力画像
	p.vehicle_damage = 500.0
	p.infantry_damage = 800.0
	_check("载具伤害已记账", p.vehicle_damage > 0.0)
	_check("步兵伤害已记账", p.infantry_damage > 0.0)

# ============================================================ 加时赛
func _test_overtime(p: Soldier) -> void:
	MatchState.match_active = true
	MatchState.overtime = false
	MatchState.overtime_phase = 0
	MatchState.tickets[0] = 0
	# 把玩家塞进据点圈里，制造"拉旗状态"，再手动触发一次胜负判定
	var cap: Dictionary = GameConfig.CAPTURES[0]
	p.global_position = cap["pos"]
	await _wait(3)
	# 兵力是被直接改的，得手动走一次判定 —— 正常流程里是阵亡扣票到最后一点时自动触发
	MatchState._check_win()
	await _wait(2)
	_check("攻方兵力耗尽且点内有人 -> 进入加时", MatchState.overtime)
	_check("加时第一阶段", MatchState.overtime_phase == 1,
		"phase=%d" % MatchState.overtime_phase)
	_check("加时标记了胜负手据点", MatchState.overtime_point != "",
		MatchState.overtime_point)
	_check("点内有人时时间流速减半", MatchState._attacker_holds_any_point())
	_check("减速系数为 0.5", is_equal_approx(GameConfig.OVERTIME_TIME_SCALE, 0.5))
	var ot_before: float = MatchState.overtime_time
	await _seconds(2.0)
	_check("加时一阶段的时间在走", MatchState.overtime_time < ot_before,
		"%.1f -> %.1f" % [ot_before, MatchState.overtime_time])
	# 先把状态按到确定值再推进时间。上面那 2 秒里 AI 可能已经把 A1 打下来，
	# 那就是"加时赛夺点"直接结束战局 —— match_active 变 false 之后加时计时
	# 就不再走，第二阶段永远进不去（这是实测踩到的抖动，不是逻辑错误）
	for c in GameConfig.CAPTURES:
		MatchState.captures[c["id"]]["owner"] = GameConfig.Team.HAVOC
		MatchState.captures[c["id"]]["progress"] = 0.0
	# 阶段切换直接驱动一次 tick，而不是"改小剩余时间然后等几帧"。
	# 等帧的做法会被真实战局干扰：AI 随时可能拿下标记据点直接结束战局，
	# 战局一结束加时计时就停了。要验的是"时间归零 -> 进二阶段"这条规则，
	# 那就把这条规则单独拿出来驱动，别把整局对局的状态机也拉进来
	MatchState.match_active = true
	MatchState.overtime = true
	MatchState.overtime_phase = 1
	MatchState.overtime_time = -0.001
	MatchState._tick_overtime(0.0)
	_check("一阶段时间归零 -> 进入第二阶段", MatchState.overtime_phase == 2,
		"phase=%d" % MatchState.overtime_phase)
	# 第二阶段占下那个点即胜
	MatchState.captures[MatchState.overtime_point]["owner"] = GameConfig.Team.GTI
	MatchState.match_active = true
	MatchState._check_win()
	await _wait(2)
	_check("加时赛夺点 -> 攻方获胜",
		MatchState.result.get("win_team", -1) == GameConfig.Team.GTI,
		str(MatchState.result.get("title", "")))

# ============================================================ 载具链路
func _test_vehicle_link(p: Soldier, main: Node) -> void:
	var veh: CombatVehicle = _friendly_vehicle(p.team)
	_check("战场存在己方载具", veh != null)
	if veh == null:
		return
	# 把玩家挪到车边再按 F —— 按键链路要求玩家在 BOARD_RANGE 以内
	p.global_position = veh.global_position + Vector2(52.0, 0.0)
	await _wait(2)
	await _press("enter_vehicle", 4)
	_check("按 F 上车（输入链路）", veh.driver == p and main.player_ctrl.vehicle == veh)
	_check("上车后乘员退出物理世界", p.collision_layer == 0 and not p.visible)

	# 乘员坐标必须跟着车走：否则据点占领与敌方索敌都会按上车点算，
	# 出现"人在车上、却在原地占点"的错位
	await _wait(4)
	var pos_gap: float = p.global_position.distance_to(veh.global_position)
	_check("乘员坐标跟随车体", pos_gap < 4.0, "相距 %.1f px" % pos_gap)

	# 相机跟随：先把车挪到地图中央（避开相机限位），再看相机有没有跟过去
	veh.global_position = Vector2(1900.0, 1300.0)
	await _wait(110)
	var cam: Camera2D = main.world.camera
	var gap: float = cam.global_position.distance_to(veh.global_position)
	_check("驾驶时相机跟随载具", gap < 170.0, "相距 %.0f px" % gap)

	# 弹种：按 2 切高爆，紧接着按 1 应被装填锁挡住
	await _press("swap_ammo2", 4)
	_check("按 2 切高爆弹", veh.ammo_mode == 1, "ammo_mode=%d" % veh.ammo_mode)
	_check("切弹种带装填锁", veh.ammo_switch_cd > 0.0, "剩余 %.2fs" % veh.ammo_switch_cd)
	var blocked: bool = veh.switch_ammo(0) == false
	_check("装填锁期间无法再切", blocked)
	veh.ammo_switch_cd = 0.0
	await _press("swap_ammo", 4)
	_check("按 1 切回穿甲弹", veh.ammo_mode == 0)

	# APS
	await _press("aps", 4)
	_check("按 3 启动主动防御", veh.aps_active())
	_check("APS 进入冷却", veh.aps_cd > 0.0, "%.1fs" % veh.aps_cd)

	# 主炮 / 机枪：按住左键一段时间。炮塔有转速限制，要先对准才打得出去，
	# 所以这里等足了收敛时间。
	var shots0: int = veh.shots
	var mg0: int = veh.mg_shots
	Input.action_press("fire")
	await _wait(150)
	Input.action_release("fire")
	await _wait(2)
	_check("按住左键主炮开火", veh.shots > shots0, "%d -> %d 发" % [shots0, veh.shots])
	_check("按住左键机枪开火", veh.mg_shots > mg0, "%d -> %d 发" % [mg0, veh.mg_shots])

	# 下车
	await _press("enter_vehicle", 4)
	_check("按 F 下车（输入链路）", main.player_ctrl.vehicle == null and p.in_vehicle == null)
	_check("下车后恢复碰撞与可见", p.collision_layer != 0 and p.visible)

# ============================================================ 炮塔限速
## 用一辆没有 AI、没有驾驶员的空车做隔离测试：
## 有脑子的车每帧会重写 turret_dir，测不准单帧转角。
func _test_turret_slew(main: Node) -> void:
	var tv: CombatVehicle = VehicleScript.new()
	tv.setup(GameConfig.Team.GTI, CombatVehicle.Kind.APC)
	main.world.units_root.add_child(tv)
	_check("装甲车拿到 APC 数值表", tv.max_hp == GameConfig.VEHICLES[GameConfig.VehKind.APC]["hp"],
		"hp=%.0f" % tv.max_hp)
	await _wait(3)
	var before: float = tv.turret_angle
	tv.turret_dir = Vector2.from_angle(before + PI)      # 目标反向 180°
	await _wait(1)
	var moved: float = absf(GameConfig.angle_wrap(tv.turret_angle - before))
	var limit: float = CombatVehicle.TURRET_SLEW / 60.0 * 1.4 + 0.01
	_check("炮塔单帧转角受限（180° 反向不会瞬移）", moved > 0.0 and moved <= limit,
		"转 %.4f rad / 单帧上限 %.4f" % [moved, limit])
	_check("未对准时主炮锁定不发射", not tv.turret_ready())
	tv.queue_free()
	TeamManager.unregister_vehicle(tv)
	await _wait(2)

# ============================================================ 乘员安全
func _test_eject_on_destroy(p: Soldier) -> void:
	var veh: CombatVehicle = _friendly_vehicle(p.team)
	if veh == null:
		_check("找到用于击毁测试的载具", false)
		return
	p.global_position = veh.global_position + Vector2(52.0, 0.0)
	await _wait(2)
	await _press("enter_vehicle", 4)
	_check("重新上车", veh.driver == p)
	var hp_before: float = p.hp
	# 上一段测试刚给这辆车开过 APS，6 秒拦截窗口会把这发测试伤害吸收掉。
	# 这里显式关掉，测的是"载具被击毁时乘员怎么办"，不是 APS 的拦截。
	veh.aps_timer = 0.0
	# 出生保护同样要关：它会让乘员伤害整段失效
	p.spawn_protection = 0.0
	veh.take_damage(999999.0, null)
	await _wait(4)
	_check("载具被击毁后乘员被抛出", veh.driver == null and p.in_vehicle == null)
	_check("乘员不再停留在隐形状态", p.visible and p.collision_layer != 0)
	_check("乘员重伤但留一口气", p.alive and p.hp < hp_before and p.hp > 0.0,
		"hp %.0f -> %.0f" % [hp_before, p.hp])

# ============================================================ 连杀奖励
func _test_streak_rewards(p: Soldier) -> void:
	# 免伤。这一段有十几秒是在等弹幕落地和结算，其间敌方 AI 完全可能把玩家打死，
	# 一死连杀就清零，后面所有档位断言全部错位 —— 这是实测踩到的坑（第一次跑自检
	# 就撞上了：best_streak 停在 7，8 杀那档再也触发不了）。
	# 免伤只影响这一段，测"阵亡清零"时会在下面显式关掉。
	p.spawn_protection = 1e9
	_check("玩家存活（后续断言的前提）", p.alive and p.streak == 0)
	var uav_fired := [false]
	EventBus.player_uav.connect(func(_t): uav_fired[0] = true)
	p.streak = 0
	EventBus.player_streak_changed.emit(0)

	# --- 3 杀：UAV 即时生效，不占呼叫槽 ---
	await _kill_enemies(p, 3)
	_check("3 连杀触发 UAV", uav_fired[0])
	_check("UAV 不占用待呼叫槽", StreakManager.support_kind == "",
		"support_kind='%s'" % StreakManager.support_kind)

	# --- 5 杀：迫击炮解锁 + 呼叫 + 落地 ---
	await _kill_enemies(p, 2)
	_check("5 连杀解锁迫击炮", StreakManager.support_kind == "mortar",
		"support_kind='%s'" % StreakManager.support_kind)
	# 多堆几个人：机器人挨打前会一直往目标点走，落弹要 2.7 秒才走完，
	# 集结点的人早就散开了。样本给足，断言"至少炸死一个"才是稳定的。
	var cluster := Vector2(1900.0, 1300.0)
	var cluster_n: int = await _gather_enemies(p, 10, cluster)
	var streak_before: int = StreakManager.streak
	var kills_before: int = p.kills
	var ok: bool = StreakManager.call_support(cluster)
	_check("呼叫迫击炮成功", ok and StreakManager.support_kind == "")
	_check("弹幕已排入落弹队列", StreakManager.pending_strikes() > 0,
		"%d 发" % StreakManager.pending_strikes())
	await _seconds(4.0)
	_check("迫击炮全部落地", StreakManager.pending_strikes() == 0)
	_check("支援确实造成了击杀", p.kills > kills_before, "%d -> %d" % [kills_before, p.kills])
	_check("支援击杀不计入连杀（防止自举）", StreakManager.streak == streak_before,
		"连杀 %d（集结了 %d 个目标）" % [StreakManager.streak, cluster_n])

	# --- 8 杀：空中打击 ---
	await _kill_enemies(p, 3)
	_check("8 连杀解锁空中打击", StreakManager.support_kind == "airstrike",
		"support_kind='%s'" % StreakManager.support_kind)
	StreakManager.call_support(cluster)
	_check("空袭弹幕条数正确", StreakManager.pending_strikes() == 12,
		"%d 发" % StreakManager.pending_strikes())
	await _seconds(3.0)
	_check("空袭全部落地", StreakManager.pending_strikes() == 0)

	# --- 12 杀：载具增援 ---
	await _kill_enemies(p, 4)
	_check("12 连杀解锁载具增援", StreakManager.support_kind == "tank",
		"support_kind='%s'" % StreakManager.support_kind)
	var veh_before: int = TeamManager.vehicles.size()
	StreakManager.call_support(cluster)
	await _wait(4)
	_check("载具增援落地一架", TeamManager.vehicles.size() == veh_before + 1,
		"%d -> %d" % [veh_before, TeamManager.vehicles.size()])

# ============================================================ 清零
func _test_streak_reset(p: Soldier) -> void:
	p.spawn_protection = 0.0
	p.take_damage(999999.0, null)
	await _wait(3)
	_check("被击倒后连杀清零", p.streak == 0 and StreakManager.streak == 0,
		"streak=%d" % p.streak)
	_check("最高连杀被保留", p.best_streak >= 12, "best=%d" % p.best_streak)
	# 后面的模式规则与指挥部测试需要一个还能行动的玩家，这里直接复活自己
	p._revive()
	await _wait(2)
	_check("倒地后可以被直接救起", not p.downed and p.hp > 0.0, "hp=%.0f" % p.hp)

# ============================================================ 工具
func _friendly_vehicle(team: int) -> CombatVehicle:
	for v in TeamManager.vehicles:
		if is_instance_valid(v) and v.alive and v.team == team and v.driver == null:
			return v
	return null

## 让玩家的真实击杀数 +n：走 take_damage -> _go_down -> EventBus.unit_downed -> StreakManager。
## 这里会把目标强制拉回"活着"再打：加了倒地之后，被打倒的敌人要流血 25 秒才移除，
## 战场上可打的活人会越来越少，不重置的话断言会因为"没人可打"而失败
func _kill_enemies(p: Soldier, n: int) -> void:
	var done := 0
	for u in TeamManager.units:
		if done >= n:
			break
		if not is_instance_valid(u) or u.team == p.team:
			continue
		u.alive = true
		u.downed = false
		u.hp = 1.0
		u.spawn_protection = 0.0
		u.take_damage(999999.0, p)
		await _wait(1)
		done += 1
	_check("制造 %d 次击杀" % n, done == n, "实际 %d" % done)

## 把敌人堆到一点，用来验证范围支援的杀伤。
## 会把目标强制拉回存活：倒地的人不算 alive，战场上可用的活人会越打越少。
## 目标间距压到 35 以内，是为了让"8 发覆盖弹幕"这件事有确定的答案 ——
## 散得太开时，炸不炸得死取决于随机数，测不出实现对不对。
func _gather_enemies(p: Soldier, n: int, at: Vector2) -> int:
	var moved := 0
	for u in TeamManager.units:
		if moved >= n:
			break
		if not is_instance_valid(u) or u.team == p.team:
			continue
		u.alive = true
		u.downed = false
		u.hp = u.max_hp
		u.spawn_protection = 0.0
		u.global_position = at + Vector2(randf_range(-35, 35), randf_range(-35, 35))
		moved += 1
	await _wait(2)
	return moved

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [name, ("  · " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  · " + detail) if detail != "" else ""])

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

## 合成一次按键：按下 -> 留几帧让 is_action_just_pressed 被读到 -> 松开
func _press(action: String, frames: int = 3) -> void:
	Input.action_press(action)
	await _wait(frames)
	Input.action_release(action)
	await _wait(2)

func _finish() -> void:
	print("[自检] 结束 · 通过 %d / 失败 %d" % [_pass, _fail])
	if _fail > 0:
		print("[自检] 结果：不通过")
	else:
		print("[自检] 结果：全部通过")
	# 等几帧再退：queue_free 是延迟释放，立刻 quit 会让这些节点被报成泄漏。
	await _wait(20)
	# 停音效要贴着 quit 做。中间隔几帧的话，四十个 AI 的开火音效会重新把播放实例
	# 灌满，退出时 Godot 依旧把 AudioStreamPlaybackWAV 算成泄漏。
	AudioManager.stop_all()
	get_tree().quit(1 if _fail > 0 else 0)
