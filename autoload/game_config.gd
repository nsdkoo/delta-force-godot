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
enum VehKind { TANK, APC }

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
const TICKET_MAX := [320, 260]
const MATCH_TIME := 900.0
const TEAM_SIZE := 20
const SQUAD_SIZE := 4
const RESPAWN_DELAY := 6.0
const CAP_TICKET_GAIN := 15
const CAP_TICKET_LOSS := 10
const SEGMENT_TICKET_BONUS := 80

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
const OPERATORS := {
	OpClass.ASSAULT: {
		"name": "红狼", "role": "突击兵", "weapon": "ar", "sprite": "soldier_rifle",
		"skill": "动能手雷", "skill_cd": 14.0, "hp": 110.0, "speed": 1.06,
		"color": Color("#ff6b57"), "desc": "动能手雷可弹墙投掷，爆炸范围大。巷战清点首选。",
	},
	OpClass.SUPPORT: {
		"name": "蜂医", "role": "支援兵", "weapon": "lmg", "sprite": "soldier_lmg",
		"skill": "医疗包", "skill_cd": 16.0, "hp": 130.0, "speed": 0.94,
		"color": Color("#57e08a"), "desc": "投放医疗包持续治疗范围内友军。机枪压制力最强，机动差。",
	},
	OpClass.ENGINEER: {
		"name": "乌鲁鲁", "role": "工程兵（反载具 T0）", "weapon": "smg", "sprite": "operator_blue",
		"skill": "巡飞弹", "skill_cd": 20.0, "hp": 110.0, "speed": 1.0,
		"color": Color("#ffc24a"), "desc": "大招巡飞弹可侦查、追踪、补刀、防空。多人集火可秒杀满血主战坦克。",
	},
	OpClass.RECON: {
		"name": "露娜", "role": "侦察兵", "weapon": "sniper", "sprite": "operator_agent",
		"skill": "声波探测", "skill_cd": 18.0, "hp": 100.0, "speed": 1.02,
		"color": Color("#8fc4ff"), "desc": "声波探测脉冲标记范围内敌人，全队共享视野。远端点名与反狙击。",
	},
}

const CLASS_NAME_CN := {
	OpClass.ASSAULT: "突击兵", OpClass.SUPPORT: "支援兵",
	OpClass.ENGINEER: "工程兵", OpClass.RECON: "侦察兵",
}

# ---------------------------------------------------------------- 载具
const VEHICLES := {
	VehKind.TANK: {
		"name": "主战坦克", "hp": 3200.0, "speed": 92.0, "radius": 40.0,
		"mg_damage": 12.0, "cannon_damage": 900.0, "cannon_infantry": 150.0,
		"splash": 150.0, "reload": 6.5,
	},
	VehKind.APC: {
		"name": "装甲车", "hp": 1600.0, "speed": 165.0, "radius": 32.0,
		"mg_damage": 11.0, "cannon_damage": 120.0, "cannon_infantry": 80.0,
		"splash": 110.0, "reload": 3.2,
	},
}
const APS_RANGE := 280.0
const APS_DURATION := 6.0
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

# ---------------------------------------------------------------- 输入动作名
const ACTIONS := {
	"move_up": [KEY_W], "move_down": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"sprint": [KEY_SHIFT], "reload": [KEY_R], "skill": [KEY_Q], "field_med": [KEY_E],
	"enter_vehicle": [KEY_F], "support": [KEY_X], "toggle_map": [KEY_M],
	"scoreboard": [KEY_TAB], "cancel": [KEY_ESCAPE], "swap_ammo": [KEY_1], "swap_ammo2": [KEY_2],
	"aps": [KEY_3], "mute": [KEY_N], "debug_toggle": [KEY_F3],
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
