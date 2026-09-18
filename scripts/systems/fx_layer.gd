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
## 描边材质不挂在这层：爆炸素材本身是平涂无边的，配上场景里的描边反而更脏

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
		var k: float = clampf(float(e["t"]) / maxf(float(e["life"]), 0.001), 0.0, 1.0)
		var tex: Texture2D = e["tex"]
		var frames: Array = e.get("frames", [])
		if not frames.is_empty():
			tex = frames[clampi(int(floor(k * float(frames.size()))), 0, frames.size() - 1)]
		if tex == null:
			continue
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
	_add_tex(AssetDB.fx(tex_name), pos, rot, scale, life, color, grow, spin)

## frames 非空时按进度逐帧播放（爆炸素材是 5 张静帧的序列）
func _add_tex(tex: Texture2D, pos: Vector2, rot: float, scale: float,
		life: float, color: Color, grow: float = 0.0, spin: float = 0.0,
		frames: Array = []) -> void:
	if tex == null and frames.is_empty():
		return
	if effects.size() >= MAX_EFFECTS:
		effects.pop_front()
	effects.append({
		"tex": tex, "pos": pos, "rot": rot, "scale": scale,
		"life": life, "t": 0.0, "color": color, "grow": grow, "spin": spin,
		"frames": frames,
	})

## 逐帧动画：一次爆炸是"火球 5 帧 + 烟 5 帧"两段序列叠起来的
func _blast_frames(smoke: bool) -> Array:
	var out: Array = []
	for i in 5:
		var t := AssetDB.kfx(("expsmoke_" if smoke else "exp_") + str(i + 1))
		if t != null:
			out.append(t)
	return out

# ============================================================ 事件入口
## kind: muzzle（炮口焰）/ boom（爆炸）/ smoke（烟柱）
func _on_explosion(pos: Vector2, scale: float, kind: String) -> void:
	match kind:
		"muzzle":
			## 枪口焰直接用素材包里的曳光贴片，比手搓的圆点更像火光
			_add("shot_large", pos, randf() * TAU, 0.9 * scale, 0.09,
				Color(2.6, 1.9, 0.9, 1.0))
			_add("shot_orange", pos, randf() * TAU, 1.1 * scale, 0.07,
				Color(2.2, 1.4, 0.6, 0.95))
		"smoke":
			_add("smoke", pos, randf() * TAU, 0.7 * scale, 0.85,
				Color(1.1, 1.05, 1.0, 0.5), 0.9, randf_range(-0.6, 0.6))
		_:
			## boom：火球序列 + 烟序列 + 一层焦痕。
			## 素材的 5 帧序列本身就是"炸开→扩散→消散"，比手绘的
			## 多层叠加强得多，所以这里不再自己搓火球
			var fire := _blast_frames(false)
			if not fire.is_empty():
				_add_tex(fire[0], pos, randf() * TAU, 1.15 * scale, 0.46,
					Color(2.0, 1.5, 0.9, 1.0), 0.5, 0.0, fire)
			else:
				_add("fire", pos, randf() * TAU, 0.85 * scale, 0.42,
					Color(2.4, 1.05, 0.32, 1.0), 0.55)
			_add("spark", pos, randf() * TAU, 1.5 * scale, 0.22,
				Color(2.8, 2.2, 1.2, 1.0), 1.1)
			var smk := _blast_frames(true)
			if not smk.is_empty():
				_add_tex(smk[0], pos + Vector2(0, -8.0), randf() * TAU, 1.3 * scale, 1.5,
					Color(1.0, 0.97, 0.92, 0.62), 0.7, 0.0, smk)
			_add("scorch", pos, randf() * TAU, 0.7 * scale, 1.1,
				Color(0.32, 0.26, 0.2, 0.7), 0.35)

## kind: flesh（血肉）/ metal（金属）/ sand（沙土）
func _on_impact(pos: Vector2, normal: Vector2, kind: String) -> void:
	## 弹着点沿法线往外挪一点，避免特效钻进墙里被建筑盖住
	var p := pos + normal * 4.0
	var rot := normal.angle()
	match kind:
		"flesh":
			_add("shot_red", p, rot, 0.45, 0.14, Color(2.2, 0.5, 0.42, 1.0), 0.7)
		"metal":
			_add("shot_thin", p, rot, 0.5, 0.16, Color(2.8, 2.3, 1.3, 1.0), 0.6)
			_add("smoke", p, randf() * TAU, 0.18, 0.30, Color(1.0, 0.95, 0.85, 0.4), 1.0)
		_:
			## sand：沙土弹着以扬尘为主，没有亮部
			_add("smoke_dark", p, randf() * TAU, 0.22, 0.38,
				Color(1.3, 1.15, 0.9, 0.55), 1.1, randf_range(-0.8, 0.8))
