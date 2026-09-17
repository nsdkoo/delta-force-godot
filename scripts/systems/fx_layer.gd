extends Node2D
class_name FxLayer
## ============================================================================
## FxLayer · 战斗特效层
## ----------------------------------------------------------------------------
## 监听 EventBus 的 explosion / impact，把事件翻译成一段短生命周期的画面。
##
## 为什么用「一个节点 + _draw」而不是「每次爆炸 new 一个 Sprite2D」：
## 四十个单位交火时每秒会产生上百个弹着点，逐事件建节点会让场景树在几秒内
## 肿胀到几千个对象，随之而来的 set_global_position / queue_free 开销比绘制本身
## 还大。这里把特效压成一条纯数据记录，统一在 _draw 里一次性画完，
## 节点数恒定为 1，且没有对象池要维护。
##
## 辉光靠 HDR：颜色分量给到 1.0 以上（如 2.4），引擎的 HDR 2D + Glow 会把
## 超亮部分晕开。这样不需要混合模式（Godot 4 已移除 draw_set_blend_mode），
## 也不额外引入材质与 ShaderMaterial。
## ============================================================================

## 特效总量上限。超出后丢弃最旧的一条 —— 战场上宁可漏掉一个远处的枪口焰，
## 也不能让绘制阵列在混战里无限增长。
const MAX_EFFECTS := 320

## 一条特效记录：
##   tex  贴图      pos 世界坐标   rot 朝向       scale 起始缩放
##   life 存活秒数  t   已存活时间  grow 每秒额外膨胀比例
##   color 调制色（可超过 1.0 触发辉光）  spin 每秒自转弧度
var effects: Array = []

func _ready() -> void:
	## 退出光照链路：特效需要保持高亮，被环境天光压暗反而会丢掉辉光。
	light_mask = 0
	EventBus.explosion.connect(_on_explosion)
	EventBus.impact.connect(_on_impact)

func _process(delta: float) -> void:
	if effects.is_empty():
		return
	for i in range(effects.size() - 1, -1, -1):
		var e: Dictionary = effects[i]
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) >= float(e["life"]):
			effects.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for e in effects:
		var tex: Texture2D = e["tex"]
		if tex == null:
			continue
		var k: float = clampf(float(e["t"]) / maxf(float(e["life"]), 0.001), 0.0, 1.0)
		## 生命末期线性淡出；膨胀让火焰与烟有"扩散"感，而不是原地闪烁
		var s: float = float(e["scale"]) * (1.0 + float(e["grow"]) * k)
		var col: Color = e["color"]
		col.a *= (1.0 - k)
		draw_set_transform(e["pos"], float(e["rot"]) + float(e["spin"]) * float(e["t"]),
			Vector2(s, s))
		draw_texture(tex, -tex.get_size() * 0.5, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ============================================================ 记录
func _add(tex_name: String, pos: Vector2, rot: float, scale: float,
		life: float, color: Color, grow: float = 0.0, spin: float = 0.0) -> void:
	var tex := AssetDB.fx(tex_name)
	if tex == null:
		return
	if effects.size() >= MAX_EFFECTS:
		effects.pop_front()
	effects.append({
		"tex": tex, "pos": pos, "rot": rot, "scale": scale,
		"life": life, "t": 0.0, "color": color, "grow": grow, "spin": spin,
	})

# ============================================================ 事件入口
## kind: muzzle（炮口焰）/ boom（爆炸）/ smoke（烟柱）
func _on_explosion(pos: Vector2, scale: float, kind: String) -> void:
	match kind:
		"muzzle":
			## 极短的一帧亮斑。炮口焰比枪口焰大一号，用两个角度错开叠出十字星芒
			_add("muzzle_2", pos, randf() * TAU, 0.55 * scale, 0.075,
				Color(2.6, 1.9, 0.9, 1.0))
			_add("muzzle", pos, randf() * TAU, 0.75 * scale, 0.06,
				Color(2.2, 1.3, 0.5, 0.9))
		"smoke":
			_add("smoke", pos, randf() * TAU, 0.7 * scale, 0.85,
				Color(1.1, 1.05, 1.0, 0.5), 0.9, randf_range(-0.6, 0.6))
		_:
			## boom：火球 + 火星 + 烟柱三层。火球寿命最短、最亮，烟最长、最暗，
			## 三者错开之后爆炸才有"炸开再散掉"的层次，否则只是一团光闪一下
			_add("fire", pos, randf() * TAU, 0.85 * scale, 0.42,
				Color(2.4, 1.05, 0.32, 1.0), 0.55, randf_range(-1.2, 1.2))
			_add("flame", pos, randf() * TAU, 0.6 * scale, 0.30,
				Color(2.0, 1.5, 0.6, 0.95), 0.8)
			_add("spark", pos, randf() * TAU, 1.5 * scale, 0.22,
				Color(2.8, 2.2, 1.2, 1.0), 1.1)
			_add("smoke", pos + Vector2(0, -6.0), randf() * TAU, 0.9 * scale, 1.35,
				Color(0.9, 0.86, 0.8, 0.55), 0.85, randf_range(-0.5, 0.5))
			_add("scorch", pos, randf() * TAU, 0.7 * scale, 1.1,
				Color(0.32, 0.26, 0.2, 0.8), 0.35)

## kind: flesh（血肉）/ metal（金属）/ sand（沙土）
func _on_impact(pos: Vector2, normal: Vector2, kind: String) -> void:
	## 弹着点沿法线往外挪一点，避免特效钻进墙里被建筑盖住
	var p := pos + normal * 4.0
	var rot := normal.angle()
	match kind:
		"flesh":
			_add("spark", p, rot, 0.30, 0.13, Color(2.2, 0.5, 0.42, 1.0), 0.7)
		"metal":
			_add("spark", p, rot, 0.36, 0.15, Color(2.8, 2.3, 1.3, 1.0), 0.6)
			_add("smoke", p, randf() * TAU, 0.18, 0.30, Color(1.0, 0.95, 0.85, 0.4), 1.0)
		_:
			## sand：沙土弹着以扬尘为主，没有亮部
			_add("smoke_dark", p, randf() * TAU, 0.22, 0.38,
				Color(1.3, 1.15, 0.9, 0.55), 1.1, randf_range(-0.8, 0.8))
