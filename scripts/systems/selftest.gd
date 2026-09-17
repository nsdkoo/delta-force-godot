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
	MatchState.player_is_commander = true
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
	await _test_streak_reset(p)
	_finish()

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
	_check("阵亡后连杀清零", p.streak == 0 and StreakManager.streak == 0,
		"streak=%d" % p.streak)
	_check("最高连杀被保留", p.best_streak >= 12, "best=%d" % p.best_streak)

# ============================================================ 工具
func _friendly_vehicle(team: int) -> CombatVehicle:
	for v in TeamManager.vehicles:
		if is_instance_valid(v) and v.alive and v.team == team and v.driver == null:
			return v
	return null

## 让玩家的真实击杀数 +n：走 take_damage -> _die -> EventBus.unit_died -> StreakManager
func _kill_enemies(p: Soldier, n: int) -> void:
	var done := 0
	for u in TeamManager.alive_units():
		if done >= n:
			break
		if u.team == p.team:
			continue
		u.spawn_protection = 0.0
		u.take_damage(999999.0, p)
		await _wait(1)
		done += 1
	_check("制造 %d 次击杀" % n, done == n, "实际 %d" % done)

## 把敌人堆到一点，用来验证范围支援的杀伤。
## 目标间距压到 35 以内，是为了让"8 发覆盖弹幕"这件事有确定的答案 ——
## 散得太开时，炸不炸得死取决于随机数，测不出实现对不对。
func _gather_enemies(p: Soldier, n: int, at: Vector2) -> int:
	var moved := 0
	for u in TeamManager.alive_units():
		if moved >= n:
			break
		if u.team == p.team:
			continue
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
