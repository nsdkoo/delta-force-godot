extends Node2D
class_name RenderRig
## ============================================================================
## RenderRig · 2D 高级渲染装置
## ----------------------------------------------------------------------------
## 把 Godot 4 的 2D 光照与后处理链路一次装配到位：
##
##   WorldEnvironment(HDR 2D + Glow + ACES)
##         └ CanvasModulate   环境天光（乘性，压在 bloom 之后 → 压暗画面但保留辉光）
##         └ DirectionalLight2D  太阳：方向光，低角度 + 长阴影
##         └ LightOccluder2D     建筑遮挡体，把影子投到地面和单位上
##
## Light Mask 分层约定（对应 GameConfig.LightLayer）：
##   layer 1 = 地面 —— 接收阳光与全部建筑阴影，是阴影的唯一落点
##   layer 2 = 单位 / 载具 —— 接收阳光与建筑阴影，但彼此之间不投影
##   建筑自身 light_mask = 0 —— 明暗由绘制层手工着色（受光面 / 背光面）。
##   若让建筑参与光照，它会被自己生成的遮挡体整块压黑，看起来像地上开了个洞。
##
## 为什么建筑只当遮挡体、不参与光照：
##   2D 光照的遮蔽没有任何法线信息，一个闭合多边形遮挡体会让它内部全黑。
##   所以「影子投在地上」交给光照系统，「建筑立面本身的明暗」交给绘制层。
## ============================================================================

const LAYER_GROUND := 0b0001
const LAYER_UNIT := 0b0010
const LIGHT_ALL := LAYER_GROUND | LAYER_UNIT

## 太阳：暖白斜射。
## 能量压得比较低是有原因的：地面现在是平涂色块（法线朝上），太阳的贡献是
## 一个常数叠加，给太强会变成"亮带 + 暗区"的强对比；给到 0.6 左右，
## 投影才只是把地面压暗一档，而不是切成昼夜两块
## （早期写实地表有法线起伏，能吃掉更强的光，那套参数放到平涂地面上就不适用了）
const SUN_COLOR := Color(1.0, 0.972, 0.905)
const SUN_ENERGY := 0.62
const SUN_ANGLE_DEG := -37.0
## 天光：环境漫射。卡通风格的天光要给足，暗部不能脏，
## 否则高饱和的色块会被压成一片黑褐色，整个画面就"糊"了
const AMBIENT := Color(0.945, 0.928, 0.882)
const AMBIENT_NIGHT := Color(0.60, 0.63, 0.72)

var world_env: WorldEnvironment
var ambient: CanvasModulate
var sun: DirectionalLight2D
var occluders: Node2D
var _env: Environment

func _ready() -> void:
	name = "RenderRig"
	z_index = -100
	_build_environment()
	_build_ambient()
	_build_sun()
	occluders = Node2D.new()
	occluders.name = "Occluders"
	occluders.z_index = -50
	add_child(occluders)

# ------------------------------------------------------------------ 后处理
func _build_environment() -> void:
	_env = Environment.new()
	# 2D 场景必须用 Canvas 背景模式，否则发光不会作用在画布上
	_env.background_mode = Environment.BG_CANVAS
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.80, 0.79, 0.76)
	_env.ambient_light_energy = 1.0
	# 辉光：阈值压到 0.82，让超过 1.0 的 HDR 像素（枪焰、爆炸、曳光）真正烧起来
	_env.glow_enabled = true
	_env.glow_normalized = true
	_env.glow_intensity = 0.62
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.10
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_MIX
	_env.glow_mix = 0.16
	_env.glow_hdr_threshold = 0.82
	_env.glow_hdr_scale = 2.0
	_env.set("glow_levels/1", 0.0)
	_env.set("glow_levels/2", 0.4)
	_env.set("glow_levels/3", 1.0)
	_env.set("glow_levels/4", 0.7)
	_env.set("glow_levels/5", 0.35)
	_env.set("glow_levels/6", 0.0)
	_env.set("glow_levels/7", 0.0)
	# 色调映射：ACES 给高光更好的滚降，暗部保留细节
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 4.0
	# 分级：抬对比、提饱和。卡通风格靠高饱和的平涂色块撑画面，
	# 之前 0.96 的降饱和会把新调色板拉回写实灰
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.02
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.24
	# 辉光只作用到世界层，HUD 所在 CanvasLayer（layer >= 1）不受影响
	_env.background_canvas_max_layer = 0

	# 辉光是画质开关里最重的一项（HDR + 多级模糊），设置页里必须能关。
	# 关掉之后枪焰与爆炸不再有光晕，但帧率在中低端机器上会明显好转
	_env.glow_enabled = _env.glow_enabled and UserSettings.glow_enabled
	UserSettings.changed.connect(func():
		_env.glow_enabled = UserSettings.glow_enabled
		world_env.environment = _env)

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = _env
	add_child(world_env)

# ------------------------------------------------------------------ 环境光
func _build_ambient() -> void:
	ambient = CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = AMBIENT
	add_child(ambient)

# ------------------------------------------------------------------ 太阳
func _build_sun() -> void:
	sun = DirectionalLight2D.new()
	sun.name = "Sun"
	sun.color = SUN_COLOR
	sun.energy = SUN_ENERGY
	sun.blend_mode = Light2D.BLEND_MODE_ADD
	# height 决定法线贴图的立体强度：0 时光线平行于表面，法线几乎不起作用
	sun.height = 0.72
	sun.rotation = deg_to_rad(SUN_ANGLE_DEG)
	sun.shadow_enabled = true
	# 影子：比原来浅、边缘更硬。卡通风格的投影是"一块明确的暗色块"，
	# 不是柔和渐隐的写实阴影
	sun.shadow_color = Color(0.20, 0.17, 0.24, 0.44)
	sun.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	sun.shadow_filter_smooth = 0.6
	sun.shadow_item_cull_mask = LIGHT_ALL
	# 只照地面与单位；建筑自身 light_mask = 0，不进这条链路
	sun.range_item_cull_mask = LIGHT_ALL
	# 阴影只在镜头附近计算，远处裁掉换取帧率
	sun.max_distance = 2600.0
	add_child(sun)

# ------------------------------------------------------------------ 遮挡体
## 为建筑登记一块遮挡多边形。传入的是世界坐标下的矩形。
func add_occluder(rect: Rect2, shrink: float = 0.0) -> void:
	if rect.size.x <= 2.0 or rect.size.y <= 2.0:
		return
	var r := rect.grow(-shrink) if shrink > 0.0 else rect
	var poly := OccluderPolygon2D.new()
	poly.closed = true
	poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	poly.polygon = PackedVector2Array([
		r.position,
		Vector2(r.position.x + r.size.x, r.position.y),
		r.position + r.size,
		Vector2(r.position.x, r.position.y + r.size.y),
	])
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	occ.occluder_light_mask = LIGHT_ALL
	occluders.add_child(occ)

# ------------------------------------------------------------------ 动态光源
## 枪口焰 / 爆炸闪光：短促的点光源。归到 LIGHT_ALL，建筑会挡住它照向地面的光
func flash(pos: Vector2, radius: float, color: Color, life: float) -> void:
	var l := PointLight2D.new()
	l.texture = _radial_texture()
	l.color = color
	l.energy = 3.4
	l.texture_scale = radius / 128.0
	l.height = 0.55
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.range_item_cull_mask = LIGHT_ALL
	l.shadow_enabled = false
	l.position = pos
	l.z_index = -40
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)

static var _radial_tex: GradientTexture2D
## 生成一张径向衰减的灯光贴图，避免依赖外部资源
static func _radial_texture() -> GradientTexture2D:
	if _radial_tex != null:
		return _radial_tex
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.32, Color(1, 1, 1, 0.62))
	g.add_point(0.66, Color(1, 1, 1, 0.20))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_radial_tex = t
	return t
