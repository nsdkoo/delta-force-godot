extends Node
## ============================================================================
## ImpactFx · 打击感
## ----------------------------------------------------------------------------
## 两件事：镜头震屏、命中顿帧。都是"不改变任何规则、只改变观感"的东西，
## 但它们是"操作像在拖纸片"和"打起来有反馈"的分界线。
##
## 震屏做成"请求 + 衰减"而不是"每次爆炸直接改相机位置"：
##   同一帧里可能有十几次爆炸，逐个直接叠加位移会把镜头甩飞；
##   汇成一个 shaking 强度再按帧衰减，画面才是"抖一下"而不是"乱跳"。
##
## 顿帧用 Engine.time_scale 而不是暂停场景树：
##   time_scale 会影响所有 delta，包括物理与 AI，等于"整局慢一帧"，
##   这正是我们要的顿挫感；暂停场景树会连输入一起冻住，手感就断了。
##
## 两个开关都读 UserSettings：晕动症玩家必须能关掉震屏，这不是可选项。
## ============================================================================

const MAX_SHAKE := 10.0

var shake: float = 0.0
var _hitstop_left: float = 0.0
var _hitstop_restore: float = 1.0

func _ready() -> void:
	# 顿帧的恢复必须走真实时间，暂停期间也不能停，否则 time_scale 会卡住
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.explosion.connect(_on_explosion)
	EventBus.hitmarker.connect(_on_hitmarker)
	EventBus.heavy_support_used.connect(_on_heavy)
	EventBus.player_hurt.connect(_on_player_hurt)

## 请求一次震屏。amount 是像素量级的强度，内部会夹在 MAX_SHAKE 内
func kick(amount: float) -> void:
	if UserSettings.shake_scale <= 0.001:
		return
	shake = minf(MAX_SHAKE, shake + amount * UserSettings.shake_scale)

## 请求一次顿帧（秒）。重复请求取较长的一次，不叠加
func hitstop(seconds: float) -> void:
	if not UserSettings.hitstop_enabled:
		return
	_hitstop_left = maxf(_hitstop_left, seconds)

func _process(delta: float) -> void:
	# 衰减用真实时间：顿帧期间 time_scale 被压低，若跟着缩放走会拖很久
	var raw := delta / maxf(Engine.time_scale, 0.001)
	shake = maxf(0.0, shake - raw * (48.0 + shake * 5.0))
	if _hitstop_left > 0.0:
		_hitstop_left -= raw
		if _hitstop_left <= 0.0:
			Engine.time_scale = 1.0
		else:
			Engine.time_scale = _hitstop_restore

## 相机每帧取一次偏移。用正弦叠轻微随机，避免噪点感
func offset() -> Vector2:
	if shake <= 0.01:
		return Vector2.ZERO
	var t := Time.get_ticks_msec() / 1000.0
	var a := sin(t * 52.0) * 0.55 + randf_range(-0.2, 0.2)
	var b := cos(t * 41.0) * 0.55 + randf_range(-0.2, 0.2)
	return Vector2(a, b) * shake

# ---------------------------------------------------------------- 事件接线
func _on_explosion(_pos: Vector2, scale: float, _kind: String) -> void:
	kick(1.4 * maxf(0.6, scale))

func _on_hitmarker(_head: bool, lethal: bool, _dmg: float) -> void:
	# 命中几乎不震 —— 20v20 每秒十几次，再大就瞄不准
	kick(0.25 if not lethal else 0.7)
	if lethal:
		hitstop(0.03)

func _on_heavy(_team: int, kind: String, _pos: Vector2) -> void:
	kick(3.5 if kind == "missile" else 2.4)
	hitstop(0.05)

## 玩家挨打：轻震即可，重震会让倒地/连挨打时完全没法操作
func _on_player_hurt(_direction: float, intensity: float) -> void:
	kick(1.1 + clampf(intensity, 0.0, 1.0) * 1.6)
	hitstop(0.02)
