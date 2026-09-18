extends Node
## ============================================================================
## GameConfig · 全局配置
## ----------------------------------------------------------------------------
## 枚举 / 世界常量 / 数值表 / 输入映射。所有模块的单一事实来源。
## ============================================================================

# ---------------------------------------------------------------- 枚举
enum Team { GTI = 0, HAVOC = 1 }
enum OpClass { ASSAULT, SUPPORT, ENGINEER, RECON }
enum OrderKind { ATTACK, DEFEND, ADVANCE, WARN }
enum Phase { BOOT, ELECT, DEPLOY, FIGHT, RESULT }
enum VehKind { TANK, APC, AA, HELI, CAR }

# 物理层位（1 << (layer-1)）
enum Layer {
	WORLD = 1 << 0,
	TEAM_GTI = 1 << 1,
	TEAM_HAVOC = 1 << 2,
	PROJECTILE = 1 << 3,
	PICKUP = 1 << 4,
	VEHICLE = 1 << 5,
	VISION_BLOCKER = 1 << 6,
}

# ---------------------------------------------------------------- 战局
const TEAM_NAME := {Team.GTI: "GTI", Team.HAVOC: "哈夫克"}
const TEAM_ROLE := {Team.GTI: "进攻方", Team.HAVOC: "防守方"}
const TEAM_COLOR := {Team.GTI: Color("#4aa8ff"), Team.HAVOC: Color("#ff5b4a")}
const TEAM_COLOR_DIM := {Team.GTI: Color("#2f6ea8"), Team.HAVOC: Color("#a8342a")}

const WORLD_SIZE := Vector2(3800.0, 2600.0)
## 进攻方兵力。守方兵力无限 —— 这是胜者为王和普通攻防最大的结构差异：
## 守方的"血量"是时间，攻方的"血量"是兵力，双方不在同一个资源池里博弈。
const ATTACKER_TICKETS := 180
const MATCH_TIME := 900.0
const TEAM_SIZE := 20
const SQUAD_SIZE := 4
## 复活冷却。远长于普通攻防（6 秒），死亡代价高，这是"控点 > 杀人"这个
## 核心原则能成立的前提：死一次就是二十秒的空窗，光靠击杀换不来据点
const RESPAWN_DELAY := 20.0
## 在小队长附近重部署的冷却减免（秒）
const LEADER_RESPAWN_BONUS := 5.0
const CAP_TICKET_GAIN := 15
const CAP_TICKET_LOSS := 10
const SEGMENT_TICKET_BONUS := 80

# ---------------------------------------------------------------- 加时赛
## 攻方兵力耗尽但点内人数占优时触发。第一阶段只要点里还有攻方的人，
## 时间流速减半；撑过第一阶段进入第二阶段，时间恒定，占下即为胜。
const OVERTIME_PHASE1 := 90.0
const OVERTIME_PHASE2 := 30.0
const OVERTIME_TIME_SCALE := 0.5

# ---------------------------------------------------------------- 倒地与救援
## 打空血不是立刻阵亡，而是进入倒地状态：可以爬、可以被拖、可以救起来。
## 这一条把"死亡"从一个瞬间事件变成一段可以博弈的时间：救不救、拖不拖、
## 拖到哪，都是决策。倒地被拖时救援者会减速，所以拖人有真实的战术代价。
const BLEED_OUT_TIME := 25.0
const REVIVE_TIME := 4.0
const REVIVE_RANGE := 78.0
const REVIVE_HP_RATIO := 0.45
const DRAG_SPEED_SCALE := 0.62

# ---------------------------------------------------------------- 地图（烬区）
const SEGMENTS := [
	{"id": 0, "name": "A 岩下村", "x": 760.0, "w": 900.0},
	{"id": 1, "name": "B 临时营地 / 贫民窟", "x": 1750.0, "w": 880.0},
	{"id": 2, "name": "C 军需仓库 / 办公区", "x": 2720.0, "w": 900.0},
]

const CAPTURES := [
	{"id": "A1", "name": "岩下村", "pos": Vector2(960, 660), "seg": 0, "radius": 150.0},
	{"id": "A2", "name": "村外哨站", "pos": Vector2(960, 1940), "seg": 0, "radius": 150.0},
	{"id": "B1", "name": "临时营地", "pos": Vector2(1900, 620), "seg": 1, "radius": 155.0},
	{"id": "B2", "name": "贫民窟", "pos": Vector2(1900, 1980), "seg": 1, "radius": 155.0},
	{"id": "C1", "name": "军需仓库", "pos": Vector2(2900, 700), "seg": 2, "radius": 150.0},
	{"id": "C2", "name": "办公区", "pos": Vector2(2900, 1900), "seg": 2, "radius": 150.0},
]

const BASE_POS := {Team.GTI: Vector2(250, 1300), Team.HAVOC: Vector2(3550, 1300)}

# ---------------------------------------------------------------- 武器
const WEAPONS := {
	"ar": {
		"name": "M4A1 突击步枪", "damage": 17.0, "rpm": 740.0, "spread_deg": 2.4,
		"speed": 1500.0, "mag": 30, "reserve": 240, "auto": true, "reload": 2.1,
		"range": 900.0, "recoil": 0.085,
	},
	"lmg": {
		"name": "M250 轻机枪", "damage": 15.0, "rpm": 640.0, "spread_deg": 3.4,
		"speed": 1400.0, "mag": 100, "reserve": 300, "auto": true, "reload": 4.4,
		"range": 1000.0, "recoil": 0.10,
	},
	"smg": {
		"name": "MP5 冲锋枪", "damage": 12.0, "rpm": 900.0, "spread_deg": 3.0,
		"speed": 1300.0, "mag": 40, "reserve": 240, "auto": true, "reload": 2.0,
		"range": 600.0, "recoil": 0.075,
	},
	"sniper": {
		"name": "M700 狙击枪", "damage": 92.0, "rpm": 48.0, "spread_deg": 0.5,
		"speed": 2600.0, "mag": 5, "reserve": 40, "auto": false, "reload": 3.0,
		"range": 2200.0, "recoil": 0.32,
	},
	"pistol": {
		"name": "G17 手枪", "damage": 14.0, "rpm": 420.0, "spread_deg": 2.6,
		"speed": 1250.0, "mag": 17, "reserve": 102, "auto": false, "reload": 1.5,
		"range": 500.0, "recoil": 0.07,
	},
}

# ---------------------------------------------------------------- 干员
## 每个干员是一个独立 id，而不是"一个兵种一个干员"。
## 文档里的阵容推荐（8 突击 + 6 支援 + 3 工程 + 3 侦察）要求同一兵种下有多个
## 可选干员，否则"职业搭配"根本无从谈起。
##
## passive 只实现了几条能直接改变手感的：exo（动力外骨骼）/ regen（脱战回血）/
## at_boost（反载具加成）/ dog（军犬自动标记）。其余留给文案与后续扩展。
const OPERATORS := {
	# ---- 突击 ----
	"redwolf": {
		"name": "红狼", "role": "突击兵", "class": OpClass.ASSAULT,
		"weapon": "ar", "sprite": "soldier_rifle",
		"skill": "动力外骨骼", "skill_cd": 14.0, "hp": 110.0, "speed": 1.06,
		"color": Color("#ff6b57"), "passive": "exo",
		"desc": "外骨骼激活后提升移速与射速，击杀回血。突进收割首选。",
	},
	"weilong": {
		"name": "威龙", "role": "突击兵", "class": OpClass.ASSAULT,
		"weapon": "ar", "sprite": "soldier_reload",
		"skill": "C4 破障", "skill_cd": 16.0, "hp": 120.0, "speed": 1.0,
		"color": Color("#ff9a3a"), "passive": "",
		"desc": "C4 爆破掩体配虎蹲炮压制，攻坚破点的第一选择。",
	},
	# ---- 支援 ----
	"bee": {
		"name": "蜂医", "role": "支援兵", "class": OpClass.SUPPORT,
		"weapon": "lmg", "sprite": "soldier_lmg",
		"skill": "医疗包", "skill_cd": 16.0, "hp": 130.0, "speed": 0.94,
		"color": Color("#57e08a"), "passive": "",
		"desc": "治疗烟加激素枪，团队核心续航。机枪压制力最强、机动最差。",
	},
	"raincoat": {
		"name": "风衣", "role": "支援兵", "class": OpClass.SUPPORT,
		"weapon": "ar", "sprite": "operator_survivor",
		"skill": "战地恢复", "skill_cd": 13.0, "hp": 125.0, "speed": 0.98,
		"color": Color("#8fd9a8"), "passive": "regen",
		"desc": "自带强力恢复，烟雾弹储量高，可携带弹药箱。新手最稳的支援。",
	},
	"traveler": {
		"name": "旅人", "role": "支援兵", "class": OpClass.SUPPORT,
		"weapon": "smg", "sprite": "operator_green",
		"skill": "气雾针剂", "skill_cd": 15.0, "hp": 115.0, "speed": 1.02,
		"color": Color("#b6e06a"), "passive": "dog",
		"desc": "军犬协同：自动标记附近敌人。刺激性烟雾逼出敌人位置，气雾针剂友方治疗、敌方削弱。",
	},
	# ---- 工程 ----
	"uluru": {
		"name": "乌鲁鲁", "role": "工程兵（反载具 T0）", "class": OpClass.ENGINEER,
		"weapon": "smg", "sprite": "operator_blue",
		"skill": "巡飞弹", "skill_cd": 20.0, "hp": 110.0, "speed": 1.0,
		"color": Color("#ffc24a"), "passive": "at_boost",
		"desc": "巡飞弹可侦查、追踪、补刀、防空。声波震慑在防守与反载具场景压制力极强。",
	},
	# ---- 侦察 ----
	"luna": {
		"name": "露娜", "role": "侦察兵", "class": OpClass.RECON,
		"weapon": "sniper", "sprite": "operator_agent",
		"skill": "声波探测", "skill_cd": 18.0, "hp": 100.0, "speed": 1.02,
		"color": Color("#8fc4ff"), "passive": "spot_long",
		"desc": "探测剑大范围标记敌人，全队共享视野。远端点名与反狙击。",
	},
	"silverwing": {
		"name": "银翼", "role": "侦察兵", "class": OpClass.RECON,
		"weapon": "sniper", "sprite": "operator_blue",
		"skill": "无人机侦察", "skill_cd": 18.0, "hp": 100.0, "speed": 1.04,
		"color": Color("#a9d4ff"), "passive": "drone",
		"desc": "无人机持续侦察，提前探明敌方载具与伏兵位置。",
	},
	"xiaowen": {
		"name": "麦小文", "role": "侦察兵", "class": OpClass.RECON,
		"weapon": "smg", "sprite": "operator_survivor",
		"skill": "飞刀渗透", "skill_cd": 12.0, "hp": 95.0, "speed": 1.08,
		"color": Color("#c9a9ff"), "passive": "",
		"desc": "飞刀静默渗透，插重生信标缩短全队推进距离。",
	},
}

## 兵种的默认干员（AI 编队与旧调用方用）
const CLASS_DEFAULT := {
	OpClass.ASSAULT: "redwolf",
	OpClass.SUPPORT: "bee",
	OpClass.ENGINEER: "uluru",
	OpClass.RECON: "luna",
}

## 取干员数据。id 不存在时退回突击兵，任何情况下都返回有效字典
static func op(id: String) -> Dictionary:
	return OPERATORS.get(id, OPERATORS["redwolf"])

static func op_id_for_class(cls: int) -> String:
	return CLASS_DEFAULT.get(cls, "redwolf")

static func op_ids_for_class(cls: int) -> Array:
	var out: Array = []
	for id in OPERATORS:
		if int(OPERATORS[id]["class"]) == cls:
			out.append(id)
	return out

const CLASS_NAME_CN := {
	OpClass.ASSAULT: "突击兵", OpClass.SUPPORT: "支援兵",
	OpClass.ENGINEER: "工程兵", OpClass.RECON: "侦察兵",
}

# ---------------------------------------------------------------- 载具
## is_air：空中单位，无视建筑碰撞、也只能被防空火力高效击落
## can_hit_air：具备对空能力（防空车 / 武直自身）
const VEHICLES := {
	VehKind.TANK: {
		"name": "主战坦克", "key": "tank", "hp": 3200.0, "speed": 92.0, "radius": 40.0,
		"mg_damage": 12.0, "cannon_damage": 900.0, "cannon_infantry": 150.0,
		"splash": 150.0, "reload": 6.5, "is_air": false, "can_hit_air": false,
	},
	VehKind.APC: {
		"name": "装甲车", "key": "apc", "hp": 1600.0, "speed": 165.0, "radius": 32.0,
		"mg_damage": 11.0, "cannon_damage": 120.0, "cannon_infantry": 80.0,
		"splash": 110.0, "reload": 3.2, "is_air": false, "can_hit_air": false,
	},
	VehKind.AA: {
		"name": "防空车", "key": "apc", "hp": 1400.0, "speed": 150.0, "radius": 30.0,
		"mg_damage": 10.0, "cannon_damage": 90.0, "cannon_infantry": 70.0,
		"splash": 100.0, "reload": 2.6, "is_air": false, "can_hit_air": true,
		# 对空专精：打空中目标时伤害翻数倍，这是防空车存在的唯一理由
		"aa_damage": 420.0, "aa_range": 1150.0,
	},
	VehKind.HELI: {
		"name": "突击直升机", "key": "apc", "hp": 1250.0, "speed": 210.0, "radius": 36.0,
		"mg_damage": 14.0, "cannon_damage": 420.0, "cannon_infantry": 190.0,
		"splash": 130.0, "reload": 3.4, "is_air": true, "can_hit_air": true,
		"aa_damage": 200.0, "aa_range": 900.0,
	},
	VehKind.CAR: {
		"name": "突击车", "key": "apc", "hp": 700.0, "speed": 245.0, "radius": 24.0,
		"mg_damage": 9.0, "cannon_damage": 60.0, "cannon_infantry": 45.0,
		"splash": 80.0, "reload": 2.2, "is_air": false, "can_hit_air": false,
	},
}
## 主动防御（ADS）拦截窗口与冷却。文档口径：开启时呈绿光，持续 7 秒后进入红光冷却期
const APS_RANGE := 280.0
const APS_DURATION := 7.0
const APS_COOLDOWN := 32.0

# ---------------------------------------------------------------- 指令
const ORDER_INFO := {
	OrderKind.ATTACK: {"name": "进攻", "color": Color("#ff5b4a")},
	OrderKind.DEFEND: {"name": "防守", "color": Color("#4aa8ff")},
	OrderKind.ADVANCE: {"name": "前进", "color": Color("#ffd24a")},
	OrderKind.WARN: {"name": "警示", "color": Color("#ff9a3a")},
}

# ---------------------------------------------------------------- 连杀奖励
const STREAK_REWARDS := {
	3: {"kind": "uav", "text": "无人机侦察已启动（敌方位置暴露 10s）"},
	5: {"kind": "mortar", "text": "迫击炮支援就绪 · 按 X 呼叫"},
	8: {"kind": "airstrike", "text": "空中打击就绪 · 按 X 呼叫"},
	12: {"kind": "tank", "text": "载具增援就绪 · 按 X 呼叫"},
}

# ---------------------------------------------------------------- 指挥官专属技能
## side: any=双方通用 / attack=进攻方专属 / defend=防守方专属
## window: 效果或标记的有效时长（秒）
const CMD_SKILLS := {
	"vip_point": {
		"name": "高价值据点", "cost": 100.0, "cd": 210.0, "side": "any",
		"window": 180.0, "reward": 150.0,
		"desc": "标记目标据点，限时内占领或守住可得高额阵营积分",
	},
	"threat_veh": {
		"name": "高威胁载具", "cost": 100.0, "cd": 240.0, "side": "any",
		"window": 100.0, "reward": 120.0,
		"desc": "标记敌方载具，全阵营可见 100 秒，摧毁后重奖",
	},
	"emergency": {
		"name": "紧急增援", "cost": 100.0, "cd": 300.0, "side": "defend",
		"window": 45.0,
		"desc": "45 秒内己方重新部署时间大幅降低，配合点内信标快速补员",
	},
	"reinforce": {
		"name": "阵线增援", "cost": 100.0, "cd": 240.0, "side": "attack",
		"window": 45.0,
		"desc": "45 秒内攻方重部署不扣兵力，用于一波流冲点",
	},
}

# ---------------------------------------------------------------- 重火力支援
## 用阵营积分兑换。走的是和连杀支援同一套落弹调度
const HEAVY_SUPPORT := {
	"artillery": {
		"name": "炮兵齐射", "cost": 240.0, "cd": 120.0,
		"shots": 10, "radius": 150.0, "inf": 200.0, "veh": 110.0,
	},
	"missile": {
		"name": "制导导弹", "cost": 320.0, "cd": 150.0,
		"shots": 1, "radius": 320.0, "inf": 380.0, "veh": 260.0,
	},
}

# ---------------------------------------------------------------- 工事
## 小队长可建，双方同时最多 1 个，新建替换旧的。
## 冷却按文档：攻方 80 秒、守方 130 秒 —— 守方能先架好阵地，但换位代价更高
const FORTIFICATIONS := {
	"coastal": {
		"name": "岸防炮", "cd_atk": 80.0, "cd_def": 130.0,
		"hp": 900.0, "range": 950.0, "rate": 2.4, "damage": 180.0, "splash": 70.0, "anti": "ground",
	},
	"aa": {
		"name": "防空炮", "cd_atk": 80.0, "cd_def": 130.0,
		"hp": 700.0, "range": 1050.0, "rate": 1.1, "damage": 220.0, "splash": 90.0, "anti": "air",
	},
	"bunker": {
		"name": "机枪碉堡", "cd_atk": 80.0, "cd_def": 130.0,
		"hp": 1100.0, "range": 720.0, "rate": 0.11, "damage": 13.0, "splash": 0.0, "anti": "ground",
	},
	"vulcan": {
		"name": "火神炮", "cd_atk": 80.0, "cd_def": 130.0,
		"hp": 800.0, "range": 640.0, "rate": 0.07, "damage": 9.0, "splash": 0.0, "anti": "ground",
	},
}


# ---------------------------------------------------------------- 地图
## 四张地图，各自带一个"打出来才生效"的机制。
## 这些机制是胜者为王最有辨识度的部分：地图不是固定棋盘，
## 会被炮火和玩家的操作改写 —— 攻防路线会变，据点数量会变
const MAPS := {
	"jinqu": {
		"name": "烬区", "mechanic": "c1_missile",
		"desc": "C1 厂房挨两发制导导弹后坍塌，转为进攻方默认基地，防守方无法夺回",
	},
	"linjiedian": {
		"name": "临界点", "mechanic": "c1_neutral",
		"desc": "C1 被两发导弹摧毁退出争夺；攻方兵力跌破 75 时，C2 正门旁炸开新路，提前解锁下一区域",
	},
	"panxue": {
		"name": "攀升", "mechanic": "tower_collapse",
		"desc": "D 区尖塔挨三轮轰炸后塌陷，开启地下据点 D2，攻方兵力转为无限",
	},
	"yuzhen": {
		"name": "余震", "mechanic": "quake",
		"desc": "B 点三次地震后大楼坍塌开出新路线；指挥官可拉闸人为提前触发",
	},
}

static func map_name(id: String) -> String:
	return MAPS.get(id, {}).get("name", id)

# ---------------------------------------------------------------- 输入动作名
const ACTIONS := {
	"move_up": [KEY_W], "move_down": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"sprint": [KEY_SHIFT], "reload": [KEY_R], "skill": [KEY_Q], "field_med": [KEY_E],
	"enter_vehicle": [KEY_F], "support": [KEY_X], "toggle_map": [KEY_M],
	"scoreboard": [KEY_TAB], "cancel": [KEY_ESCAPE], "swap_ammo": [KEY_1], "swap_ammo2": [KEY_2],
	"aps": [KEY_3], "mute": [KEY_N], "debug_toggle": [KEY_F3],
	# 指挥部
	"cmd_skill_1": [KEY_5], "cmd_skill_2": [KEY_6],
	"heavy_1": [KEY_7], "heavy_2": [KEY_8],
	"build_fort": [KEY_B],
	# 倒地救援
	"rescue": [KEY_G],
}

func _ready() -> void:
	_setup_input()

func _setup_input() -> void:
	for action in ACTIONS:
		var keys: Array = ACTIONS[action]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_add_mouse("aim", MOUSE_BUTTON_RIGHT)

func _add_mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

# ---------------------------------------------------------------- 工具
## 敌对关系：同一队伍为友军
static func is_enemy(a: int, b: int) -> bool:
	return a != b

## 把角度差规约到 [-PI, PI]
static func angle_wrap(a: float) -> float:
	return wrapf(a, -PI, PI)

## 朝目标角度做最短路径插值
static func angle_lerp(from: float, to: float, weight: float) -> float:
	return from + angle_wrap(to - from) * clampf(weight, 0.0, 1.0)

## 队伍编号 -> 物理层掩码
static func team_layer(team: int) -> int:
	return Layer.TEAM_GTI if team == Team.GTI else Layer.TEAM_HAVOC

static func team_color(team: int) -> Color:
	return TEAM_COLOR.get(team, Color.WHITE)
