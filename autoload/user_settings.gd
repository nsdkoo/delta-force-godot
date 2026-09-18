extends Node
## ============================================================================
## UserSettings · 用户设置
## ----------------------------------------------------------------------------
## 音量、画质、手感开关，落盘到 user://settings.cfg。
##
## 为什么单独开一个 autoload 而不是塞进 GameConfig：
## GameConfig 是"设计数值"（武器伤害、干员血量），改了要重新跑自检；
## 这里是"玩家偏好"，运行时可改、必须持久化、且不影响平衡。
## 两者混在一起的话，调平衡时很容易误改到玩家设置。
##
## 所有开关都必须在"不重启"的前提下生效 —— 玩家在设置页拖一下滑块就要立刻看到
## 变化，这是产品的基本要求。所以 apply() 是唯一入口，改完立刻广播 changed。
## ============================================================================

signal changed()

const PATH := "user://settings.cfg"

## 音频
var master_volume: float = 0.8
var sfx_volume: float = 0.55
## 画面
var glow_enabled: bool = true
var show_fps: bool = false
## 手感（无障碍向：晕动症玩家需要能关掉震屏）
## 默认压得很低 —— 上一版 1.0 在 20v20 爆炸连发时会把镜头甩到无法瞄准
var shake_scale: float = 0.18
var hitstop_enabled: bool = false
const SETTINGS_VERSION := 2
var _settings_version: int = 0

func _ready() -> void:
	# 暂停时也要能改设置
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	_settings_version = int(cf.get_value("meta", "version", 0))
	master_volume = clampf(float(cf.get_value("audio", "master", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cf.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	glow_enabled = bool(cf.get_value("video", "glow", glow_enabled))
	show_fps = bool(cf.get_value("video", "show_fps", show_fps))
	shake_scale = clampf(float(cf.get_value("feel", "shake", shake_scale)), 0.0, 2.0)
	hitstop_enabled = bool(cf.get_value("feel", "hitstop", hitstop_enabled))
	# v2：旧档震屏默认太大，强制降到可瞄准的范围一次
	if _settings_version < SETTINGS_VERSION:
		shake_scale = minf(shake_scale, 0.22)
		hitstop_enabled = false
		_settings_version = SETTINGS_VERSION
		save_settings()

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", SETTINGS_VERSION)
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("video", "glow", glow_enabled)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("feel", "shake", shake_scale)
	cf.set_value("feel", "hitstop", hitstop_enabled)
	cf.save(PATH)

## 把当前设置推到实际系统上，并通知表现层
func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	changed.emit()

## 供设置页调用：改一项 -> 存盘 -> 立刻生效
func set_value(key: String, value) -> void:
	if not (key in self):
		push_warning("UserSettings: 未知设置项 " + key)
		return
	set(key, value)
	save_settings()
	apply()

func reset_defaults() -> void:
	master_volume = 0.8
	sfx_volume = 0.55
	glow_enabled = true
	show_fps = false
	shake_scale = 0.18
	hitstop_enabled = false
	_settings_version = SETTINGS_VERSION
	save_settings()
	apply()
