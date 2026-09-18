extends Node
## ============================================================================
## AppState · 应用外壳状态机
## ----------------------------------------------------------------------------
## 一个产品和一个测试场景的区别，很大一部分在于"有没有外壳"：
## 主菜单 → 设置 → 战前简报 → 对局 → 暂停 → 结算 → 回主菜单。
## 没有这层状态机，项目就是"按 F5 直接进战场"。
##
## 为什么状态放在 autoload 而不是 main.gd 的变量里：
## 主菜单、设置页、暂停页、HUD 都要知道自己现在该不该显示、该不该吃输入。
## 拆成一个全局的、可被订阅的状态，比在各处互相传引用干净得多。
##
## 注意：这里管的是"应用级"状态。对局内部的阶段（选举/部署/战斗/结算）
## 仍然归 MatchState.phase 管 —— 两者是包含关系，不要混。
## ============================================================================

enum State { BOOT, MAIN_MENU, SETTINGS, BRIEFING, PLAYING, PAUSED, RESULT }

## 版本号。主菜单与 HUD 角标都读它，改版本只改这一处
const VERSION := "0.4.0"
const BUILD_STAGE := "prototype"

## 从主菜单点"开始游戏"之后，把相机推近一档，看完战前简报再交给玩家
const PREFERRED_MENU_ZOOM := 1.15

var state: int = State.BOOT
var previous: int = State.BOOT

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.match_ended.connect(_on_match_ended)

func goto(next: int) -> void:
	if state == next:
		return
	var from := state
	previous = from
	state = next
	EventBus.app_state_changed.emit(state)
	# "什么时候该冻结世界"只在这里判一次。
	# 注意 SETTINGS 要看是从哪来的：从暂停页进设置必须继续冻结，
	# 从主菜单进设置则让战场继续跑（主菜单背后本来就是活的）
	var freeze := next == State.PAUSED or (next == State.SETTINGS and from == State.PAUSED)
	get_tree().paused = freeze

## 重载场景之后把状态拉回启动态。reload_current_scene 不会重置 autoload，
## 不硬复位的话 goto(MAIN_MENU) 会因为"状态没变"而提前返回，菜单就不显示了
func reset_to_boot() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	state = State.BOOT
	previous = State.BOOT

## 回到上一次的状态（设置页 / 暂停页的"返回"用）
func back() -> void:
	goto(previous if previous != State.BOOT else State.MAIN_MENU)

func is_playing() -> bool:
	return state == State.PLAYING

func is_menu_like() -> bool:
	return state == State.MAIN_MENU or state == State.SETTINGS or state == State.PAUSED

func state_name(s: int = -1) -> String:
	var v: int = state if s < 0 else s
	match v:
		State.BOOT: return "启动"
		State.MAIN_MENU: return "主菜单"
		State.SETTINGS: return "设置"
		State.BRIEFING: return "战前简报"
		State.PLAYING: return "对局中"
		State.PAUSED: return "已暂停"
		State.RESULT: return "结算"
	return "?"

func _on_match_ended(_w: int, _t: String, _s: String) -> void:
	goto(State.RESULT)
