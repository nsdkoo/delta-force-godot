extends Node2D
## ============================================================================
## JinqiuMap · 烬区战场
## ----------------------------------------------------------------------------
## 结构：Ground(TileMapLayer) / Roads / Decor / Buildings / Props / Obstacles
##      / NavGrid(AStarGrid2D) / UnitsRoot / FxLayer / Camera
##
## 地图设计还原腾讯《三角洲行动》全面战场「烬区」：
##   西部外围荒地（高地）→ A 岩下村（低洼村落）→ B 临时营地 + 贫民窟
##   → C 军需仓库 + 办公区（城区）→ 东部守方基地
## ============================================================================

const TILE := 64
const CELL := 64.0

# ---- 节点 ----
var rig: RenderRig
var ground: Sprite2D
var obstacles: StaticBody2D
var units_root: Node2D
var props_root: Node2D
var projectiles_root: Node2D
var fx_layer: Node2D
var camera: Camera2D

# ---- 数据 ----
var buildings: Array = []          ## {"rect": Rect2, "height": float, "type": String}
var props: Array = []              ## {"kind": String, "pos": Vector2, "rot": float, "size": float}
var tracks: Array = []             ## {"from": Vector2, "to": Vector2}
var stains: Array = []             ## {"kind": String, "pos": Vector2, "rot": float, "size": float}
var nav_grid: AStarGrid2D
var rng := RandomNumberGenerator.new()
## 卡通地景（纯装饰，不参与碰撞/导航/视线）
var _fields: Array = []            ## {"pts","color"} 地形色块
var _gtile_cache: Dictionary = {}  ## 地形砖缓存
var terrain: Node2D = null         ## 地面绘制层（承接建筑投影）
var _tufts: Array = []             ## {"pos","size","color"} 草丛
var _rocks: Array = []             ## {"pos","size"} 石堆

const MissileScript := preload("res://scripts/projectiles/missile.gd")
const GrenadeScript := preload("res://scripts/projectiles/grenade.gd")
const MedkitScript := preload("res://scripts/systems/medkit.gd")
const FxLayerScript := preload("res://scripts/systems/fx_layer.gd")

## 是否使用旧的照片级烘焙地表。默认关闭：它和"平涂 + 描边"的卡通风格拼在
## 一起会有强烈的两个世界感（照片质感的地面 vs 色块化的建筑）。
## 需要写实风时打开这个开关即可，法线与光照链路都还在
const USE_BAKED_GROUND := false

func _ready() -> void:
	add_to_group("world_map")
	rng.seed = 20260529
	_create_layers()
	_bake_ground()
	_generate_buildings()
	_register_occluders()
	_generate_props()
	_build_prop_nodes()
	_build_obstacles()
	_build_nav_grid()
	# 地景装饰要等建筑与碰撞都建好之后再撒，否则会撒进墙里
	_generate_terrain_fields()
	for t in ["ground_grass", "ground_grass_b", "ground_grass_c", "ground_dirt",
			"ground_dirt_b", "ground_dirt_c", "ground_sand", "ground_sand_b",
			"ground_stone", "ground_stone_b", "ground_stone_c"]:
		var tex := AssetDB.gtile(t)
		if tex != null:
			_gtile_cache[t] = tex
	_generate_cartoon_decor()
	print("[Jinqiu] 建筑 %d / 地物 %d(节点 %d) / 遮挡体 %d / 导航格 %d x %d / 可通行 %d"
		% [buildings.size(), props.size(), props_root.get_child_count(),
			rig.occluders.get_child_count(),
			nav_grid.region.size.x, nav_grid.region.size.y, _open_cell_count()])
	queue_redraw()
	# 离线烘焙专用：-- --dump-map 时把地图数据导出后交给 Python 处理
	if OS.get_cmdline_user_args().has("--dump-map"):
		_dump_map()

## 给建筑登记遮挡体。矮物件（沙袋、木箱）不登记：
## 它们的影子会把地面切得零碎，反而显得脏。
func _register_occluders() -> void:
	for b in buildings:
		if float(b["height"]) < 3.0:
			continue
		rig.add_occluder(b["rect"])

# ============================================================ 地图数据导出
## 把程序化生成的地图数据落盘成 JSON，供离线烘焙脚本消费。
## 地表贴图必须与实际建筑位置逐像素对齐，所以让生成端把结果导出来，
## 而不是在 Python 里重算一遍地形规则。
func _dump_map() -> void:
	var d := {
		"world": [GameConfig.WORLD_SIZE.x, GameConfig.WORLD_SIZE.y],
		"roads": _road_rects(),
		"buildings": [],
		"props": [],
		"tracks": [],
		"stains": [],
	}
	for b in buildings:
		var r: Rect2 = b["rect"]
		d["buildings"].append({
			"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y,
			"type": String(b["type"]), "height": float(b["height"])})
	for p in props:
		d["props"].append({
			"kind": String(p["kind"]), "x": p["pos"].x, "y": p["pos"].y,
			"rot": float(p["rot"]), "size": float(p["size"])})
	for t in tracks:
		d["tracks"].append({
			"x0": t["from"].x, "y0": t["from"].y, "x1": t["to"].x, "y1": t["to"].y})
	for s in stains:
		d["stains"].append({
			"kind": String(s["kind"]), "x": s["pos"].x, "y": s["pos"].y,
			"rot": float(s["rot"]), "size": float(s["size"])})
	var f := FileAccess.open("res://_map_dump.json", FileAccess.WRITE)
	if f == null:
		push_error("[Jinqiu] 地图导出失败：无法写入 _map_dump.json")
		return
	f.store_string(JSON.stringify(d))
	f.close()
	print("[Jinqiu] 地图数据已导出 → _map_dump.json（建筑 %d / 地物 %d / 履带 %d / 污渍 %d）"
		% [buildings.size(), props.size(), tracks.size(), stains.size()])

## 道路矩形（与 _draw_roads 保持同一份定义）
func _road_rects() -> Array:
	var out: Array = [{"x": 0.0, "y": 1230.0, "w": GameConfig.WORLD_SIZE.x, "h": 150.0}]
	for cx in [960.0, 1900.0, 2900.0]:
		out.append({"x": cx - 75.0, "y": 0.0, "w": 150.0, "h": GameConfig.WORLD_SIZE.y})
	return out

# ---------------------------------------------------------------- 技能生成
func spawn_missile(shooter: Soldier, target_pos: Vector2, target: Node2D) -> void:
	var m := Node2D.new()
	m.set_script(MissileScript)
	projectiles_root.add_child(m)
	m.setup(shooter.team, shooter, shooter.global_position + shooter.aim_dir * 26.0, target, target_pos)
	AudioManager.play_2d("alarm", shooter.global_position, -8.0)

func spawn_grenade(shooter: Soldier, to: Vector2) -> void:
	var g := Node2D.new()
	g.set_script(GrenadeScript)
	projectiles_root.add_child(g)
	g.setup(shooter.team, shooter, shooter.global_position + shooter.aim_dir * 24.0, to)

func spawn_medkit(shooter: Soldier) -> void:
	var k := Node2D.new()
	k.set_script(MedkitScript)
	add_child(k)
	k.setup(shooter.team, shooter.global_position)

func _open_cell_count() -> int:
	var n := 0
	for x in nav_grid.region.size.x:
		for y in nav_grid.region.size.y:
			if not nav_grid.is_point_solid(Vector2i(x, y)):
				n += 1
	return n

# ============================================================ 图层
func _create_layers() -> void:
	# 渲染装置：世界环境（HDR2D + Glow + ACES）/ 天光 / 太阳 / 建筑遮挡体
	rig = RenderRig.new()
	add_child(rig)

	# 地面在 _bake_ground 里创建（带法线贴图的世界级 Sprite）

	# 本节点画的全是矗立在地面上的立体物（建筑 / 地物），整体退出光照链路：
	# 它们的受光面与背光面由 _draw_one_building 手工着色，
	# 「影子投在地上」交给 RenderRig 的遮挡体。若让它们参与光照，
	# 遮挡体会把自己整块压黑，看起来像地上开了一个洞。
	light_mask = 0

	# 静态碰撞：所有建筑合并到一个 StaticBody2D，减少节点数
	obstacles = StaticBody2D.new()
	obstacles.name = "Obstacles"
	obstacles.collision_layer = GameConfig.Layer.WORLD
	obstacles.collision_mask = 0
	add_child(obstacles)

	units_root = Node2D.new()
	units_root.name = "Units"
	units_root.y_sort_enabled = true
	units_root.z_index = 2
	add_child(units_root)

	projectiles_root = Node2D.new()
	projectiles_root.name = "Projectiles"
	projectiles_root.z_index = 5
	projectiles_root.add_to_group("projectiles_root")
	add_child(projectiles_root)

	fx_layer = Node2D.new()
	fx_layer.name = "Fx"
	fx_layer.z_index = 8
	fx_layer.set_script(FxLayerScript)
	add_child(fx_layer)

	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)

## 绘制入口：道路与地物贴地，建筑最后画压在最上层。
## 本节点 light_mask = 0（见 _create_layers），受光的地表是独立的地面 Sprite。
func _draw() -> void:
	_draw_roads()
	_draw_cartoon_decor()
	_draw_decor()
	_draw_prop_shadows()
	_draw_buildings()

# ============================================================ 地面
## 载入离线烘焙的世界级地表贴图（Color + Normal）。
##
## 这张图由 _bake_terrain.py 生成：把 ambientCG 的真实 PBR 材质按地图数据混成
## 一张 2048x1400 的地表，并同步产出配套法线图。法线图交给 DirectionalLight2D
## 打出真实的受光面与背光面 —— 这是 2D 场景让地面「有质感」的关键，
## 单纯平铺贴图做不到这一点，因为光照在平面上没有任何起伏可依。
##
## 贴图缺失时退化为纯色沙地，保证项目在任何情况下都能起来。
func _bake_ground() -> void:
	var cpath := "res://assets/terrain/ground_color.jpg"
	if USE_BAKED_GROUND and ResourceLoader.exists(cpath):
		_build_baked_ground(cpath)
	else:
		_build_flat_ground()
	_build_ground_base()
	# 地面绘制节点：地形色块画在这一层，light_mask 指到地面层，
	# 这样建筑的投影才会落在色块上（画在 map 自己的 _draw 里就收不到阴影）
	terrain = Node2D.new()
	terrain.name = "Terrain"
	terrain.z_index = -35
	terrain.light_mask = RenderRig.LAYER_GROUND
	terrain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	terrain.draw.connect(_draw_terrain_fields)
	add_child(terrain)

## 平涂地表：一张 2x2 的纯色 + 一张平法线。
## 平法线是必须的 —— 没有法线贴图的画布项在 DirectionalLight2D(ADD) 下会被
## 整块加亮到过曝；给一张 (128,128,255) 的法线之后 N·L 是常数，
## 地面只是均匀受光，而建筑遮挡体投下的阴影照常生效
func _build_flat_ground() -> void:
	var im := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	im.fill(Palette.SAND)
	var nm := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	nm.fill(Color(0.5, 0.5, 1.0))
	var tex := CanvasTexture.new()
	tex.diffuse_texture = ImageTexture.create_from_image(im)
	tex.normal_texture = ImageTexture.create_from_image(nm)
	ground = Sprite2D.new()
	ground.name = "Ground"
	ground.z_index = -30
	ground.centered = false
	ground.light_mask = RenderRig.LAYER_GROUND
	ground.texture = tex
	ground.scale = Vector2(GameConfig.WORLD_SIZE.x / 2.0, GameConfig.WORLD_SIZE.y / 2.0)
	add_child(ground)

## 旧的烘焙写实地表。保留实现但默认关闭：它和"平涂 + 描边"的卡通风格
## 拼在一起会有强烈的两个世界感（照片质感的地面 vs 色块化的建筑），
## 需要写实风时把 USE_BAKED_GROUND 打开即可，法线与光照链路都还在
func _build_baked_ground(cpath: String) -> void:
	var npath := "res://assets/terrain/ground_normal.jpg"
	var tex := CanvasTexture.new()
	tex.diffuse_texture = load(cpath)
	if ResourceLoader.exists(npath):
		tex.normal_texture = load(npath)
	ground = Sprite2D.new()
	ground.name = "Ground"
	ground.z_index = -30
	ground.centered = false
	ground.light_mask = RenderRig.LAYER_GROUND
	ground.texture = tex
	var d: Texture2D = tex.diffuse_texture
	ground.scale = Vector2(GameConfig.WORLD_SIZE.x / float(d.get_width()),
		GameConfig.WORLD_SIZE.y / float(d.get_height()))
	add_child(ground)

## 兜底底色：所有其他图层之下先垫一层平涂沙色
func _build_ground_base() -> void:
	var im := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	im.fill(Palette.SAND)
	var base := Sprite2D.new()
	base.name = "GroundBase"
	base.z_index = -40
	base.centered = false
	base.light_mask = RenderRig.LAYER_GROUND
	base.texture = ImageTexture.create_from_image(im)
	base.scale = Vector2(GameConfig.WORLD_SIZE.x / 2.0, GameConfig.WORLD_SIZE.y / 2.0)
	add_child(base)

# ============================================================ 地形
## 按区域决定这一格是什么地貌：西侧外围荒地是草，A 村是土，B 段是沙，
## C 城区是石板，东侧守方基地回到土。分区和 README 里的地图结构一一对应
func _terrain_of(cx: float, cy: float) -> Color:
	if cy < 300.0 or cy > GameConfig.WORLD_SIZE.y - 300.0:
		return Palette.GRASS_DARK
	if cx < 620.0:
		return Palette.GRASS_DARK if rng.randf() < 0.62 else Palette.GRASS
	if cx < 1460.0:
		return Palette.DIRT
	if cx < 2360.0:
		return Palette.SAND_DARK
	if cx < 3200.0:
		return Palette.ROCK
	return Palette.DIRT

## 地形色块：按格铺，每格边缘做抖动，形成"手绘分区"的边界。
## 关键是不重叠 —— 早先用一堆大半径半透明椭圆乱叠，颜色互相乘算，
## 最后整张地表是发暗的泥色。分区铺满、每格只有一层，颜色才是干净的
func _generate_terrain_fields() -> void:
	_fields.clear()
	var cell := 190.0
	var cols := int(ceil(GameConfig.WORLD_SIZE.x / cell))
	var rows := int(ceil(GameConfig.WORLD_SIZE.y / cell))
	for gy in rows:
		for gx in cols:
			var cx := (float(gx) + 0.5) * cell
			var cy := (float(gy) + 0.5) * cell
			var col := _terrain_of(cx, cy)
			# 同色格之间做极轻的明度抖动，避免整片死板
			var j := rng.randf_range(-0.045, 0.045)
			col = Color(clampf(col.r + j, 0, 1), clampf(col.g + j, 0, 1), clampf(col.b + j, 0, 1))
			var pts := PackedVector2Array()
			var x0 := float(gx) * cell
			var y0 := float(gy) * cell
			# 四角各抖一点，格子之间仍严丝合缝（共用角点抖动值）
			var jt := cell * 0.16
			pts.append(Vector2(x0 + rng.randf_range(-jt, jt), y0 + rng.randf_range(-jt, jt)))
			pts.append(Vector2(x0 + cell + rng.randf_range(-jt, jt), y0 + rng.randf_range(-jt, jt)))
			pts.append(Vector2(x0 + cell + rng.randf_range(-jt, jt), y0 + cell + rng.randf_range(-jt, jt)))
			pts.append(Vector2(x0 + rng.randf_range(-jt, jt), y0 + cell + rng.randf_range(-jt, jt)))
			_fields.append({"pts": pts, "color": col})

## 按区域平铺真地形砖。平铺顺序很重要：先铺整幅草地，再叠各功能区，
## 最后用草地条盖住南北两条边 —— 和早先的分区逻辑一致，只是从
## "多边形填色"换成了"贴图平铺"，地面从色块变成了有纹理的手绘砖
func _draw_terrain_fields() -> void:
	var W := GameConfig.WORLD_SIZE.x
	var H := GameConfig.WORLD_SIZE.y
	_tile_region(Rect2(0, 0, W, H), ["ground_grass", "ground_grass_b", "ground_grass_c"], 64.0)
	_tile_region(Rect2(620, 300, 840, H - 600), ["ground_dirt", "ground_dirt_b", "ground_dirt_c"], 64.0)
	_tile_region(Rect2(1460, 300, 900, H - 600), ["ground_sand", "ground_sand_b"], 64.0)
	_tile_region(Rect2(2360, 300, 840, H - 600), ["ground_stone", "ground_stone_b", "ground_stone_c"], 64.0)
	_tile_region(Rect2(3200, 300, W - 3200, H - 600), ["ground_dirt", "ground_dirt_b"], 64.0)
	# 南北两条草地边最后盖上去，把功能区的直边藏掉
	_tile_region(Rect2(0, 0, W, 300), ["ground_grass", "ground_grass_b"], 64.0)
	_tile_region(Rect2(0, H - 300, W, 300), ["ground_grass", "ground_grass_c"], 64.0)

## 用几款同族地砖随机混铺一块矩形区域。
## 同一款砖平铺一大片会看出明显重复，混 2~3 款 + 随机镜像就看不出来了
func _tile_region(rect: Rect2, tiles: Array, cell: float) -> void:
	var pool: Array = []
	for t in tiles:
		if _gtile_cache.has(t):
			pool.append(_gtile_cache[t])
	var cols := int(ceil(rect.size.x / cell))
	var rows := int(ceil(rect.size.y / cell))
	for iy in rows:
		for ix in cols:
			if pool.is_empty():
				return
			var tex: Texture2D = pool[rng.randi() % pool.size()]
			var pos := rect.position + Vector2(float(ix) * cell, float(iy) * cell)
			var flip := rng.randf() < 0.5
			terrain.draw_texture_rect(tex, Rect2(pos, Vector2(cell, cell)), false,
				Color.WHITE, flip)

# ============================================================ 道路
func _draw_roads() -> void:
	var col_base := Palette.ROAD
	var col_dark := Palette.ROAD_DARK
	# 道路整体压暗一档，让它从平涂地里"沉"下去而不是浮在上面
	# 东西主干道
	_draw_road_band(Rect2(0, 1230, GameConfig.WORLD_SIZE.x, 150), true, false, col_base, col_dark)
	# 三条南北街道
	for cx in [960.0, 1900.0, 2900.0]:
		_draw_road_band(Rect2(cx - 75, 0, 150, GameConfig.WORLD_SIZE.y), false, false, col_base, col_dark)
		_draw_road_band(Rect2(cx - 75, 1230, 150, 150), true, true, col_base, col_dark)

func _draw_road_band(r: Rect2, horiz: bool, plain: bool, base: Color, dark: Color) -> void:
	# 路基：整条路先用深色铺一遍当作轮廓底，再铺亮色路面。
	# 卡通风格里"路比地高一层"靠的就是这一圈深边，而不是画阴影
	draw_rect(r.grow(5.0), Palette.OUTLINE, true)
	draw_rect(r, base, true)
	# 路面纹理：几条平行的浅色压痕，把平涂的路面拉出一点土质感
	var bands := 6
	for i in bands:
		var k := float(i) / float(bands - 1)
		var a := 0.22 * sin(PI * k)
		if horiz:
			draw_rect(Rect2(r.position.x, r.position.y + r.size.y * k - 3, r.size.x, 6),
				Color(dark.r, dark.g, dark.b, a), true)
		else:
			draw_rect(Rect2(r.position.x + r.size.x * k - 3, r.position.y, 6, r.size.y),
				Color(dark.r, dark.g, dark.b, a), true)
	# 中线
	if not plain:
		var dash := 38.0
		var gap := 30.0
		var total := r.size.x if horiz else r.size.y
		var t := 0.0
		while t < total:
			if horiz:
				draw_rect(Rect2(r.position.x + t, r.position.y + r.size.y * 0.5 - 2.5, dash, 5),
					Color(1.0, 0.96, 0.84, 0.55), true)
			else:
				draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 2.5, r.position.y + t, 5, dash),
					Color(1.0, 0.96, 0.84, 0.55), true)
			t += dash + gap

# ============================================================ 卡通地景
## 纯绘制的地景装饰：草丛、石堆、灌木。
## 这些东西不参与碰撞、不进导航网格、也不阻挡视线 —— 它们唯一的职责是让大片
## 平涂地表有细节可看。全部用固定种子的随机数生成，所以每次开局长得一样。
func _draw_cartoon_decor() -> void:
	for t in _tufts:
		var p: Vector2 = t["pos"]
		var s: float = t["size"]
		# 草簇：三撮深浅不同的小三角，根部对齐
		var col: Color = t["color"]
		for i in 3:
			var dx := (float(i) - 1.0) * s * 0.42
			var h := s * (0.85 + 0.22 * float(i % 2))
			var tip := p + Vector2(dx, -h)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(dx - s * 0.20, 0.0), p + Vector2(dx + s * 0.20, 0.0), tip]),
				col)
	for r in _rocks:
		var p2: Vector2 = r["pos"]
		var s2: float = r["size"]
		# 石堆：一个带深色描边的六边形，顶面亮、右下暗
		var pts := PackedVector2Array()
		for i in 6:
			var a := TAU * float(i) / 6.0 + 0.35
			pts.append(p2 + Vector2(cos(a), sin(a) * 0.78) * s2)
		draw_colored_polygon(pts, Palette.OUTLINE)
		var inner := PackedVector2Array()
		for k in pts.size():
			inner.append(p2 + (pts[k] - p2) * 0.86)
		draw_colored_polygon(inner, Palette.ROCK)
		var hi := PackedVector2Array()
		for k in 3:
			hi.append(p2 + (inner[k] - p2) * 0.55 + Vector2(0, -s2 * 0.12))
		draw_colored_polygon(hi, Palette.ROCK.lightened(0.18))

## 生成草簇与石堆。避开建筑、道路与据点圈
func _generate_cartoon_decor() -> void:
	_tufts.clear()
	_rocks.clear()
	for i in 260:
		var p := Vector2(rng.randf_range(60.0, GameConfig.WORLD_SIZE.x - 60.0),
			rng.randf_range(60.0, GameConfig.WORLD_SIZE.y - 60.0))
		if _on_road(p.x, p.y) or _solid_at(p, 14.0):
			continue
		var dark := rng.randf() < 0.45
		_tufts.append({"pos": p, "size": rng.randf_range(11.0, 20.0),
			"color": Palette.GRASS_DARK if dark else Palette.GRASS_LIGHT})
	for i in 70:
		var p2 := Vector2(rng.randf_range(60.0, GameConfig.WORLD_SIZE.x - 60.0),
			rng.randf_range(60.0, GameConfig.WORLD_SIZE.y - 60.0))
		if _on_road(p2.x, p2.y) or _solid_at(p2, 18.0):
			continue
		_rocks.append({"pos": p2, "size": rng.randf_range(10.0, 19.0)})

# ============================================================ 地面装饰
func _generate_props() -> void:
	# 履带痕迹
	for i in 34:
		var a := rng.randf() * TAU
		var p := Vector2(520 + rng.randi_range(0, 2900), 160 + rng.randi_range(0, 2280))
		var len := rng.randf_range(190.0, 640.0)
		tracks.append({"from": p, "to": p + Vector2(cos(a), sin(a)) * len})
	# 油污 / 焦痕
	for i in 18:
		stains.append({
			"kind": "oil",
			"pos": Vector2(560 + rng.randi_range(0, 2800), 200 + rng.randi_range(0, 2200)),
			"rot": rng.randf() * TAU, "size": rng.randf_range(48.0, 132.0)})
	for i in 24:
		stains.append({
			"kind": "scorch",
			"pos": Vector2(620 + rng.randi_range(0, 2700), 220 + rng.randi_range(0, 2160)),
			"rot": rng.randf() * TAU, "size": rng.randf_range(70.0, 195.0)})
	# 地物。换成 Kenney 卡通素材之后种类从 3 种扩到 12 种 ——
	# 手绘地物的最大问题是"一眼能看出是程序画的"：形状单调、重复感强。
	# 现成素材包一次给齐乔木 / 灌木 / 岩石 / 油桶 / 木箱 / 拒马 / 沙袋 / 铁丝网，
	# 混着撒就能把战场铺满细节，而且每种都有 2-3 个变体不会重复
	_scatter("tree", 40, 40.0, 78.0)
	_scatter("bush", 44, 26.0, 52.0)
	_scatter("rock", 26, 22.0, 46.0)
	_scatter("barrel", 52, 20.0, 28.0)
	_scatter("crate", 22, 22.0, 32.0)
	_scatter("barricade", 18, 22.0, 30.0)
	_scatter("sandbag", 20, 26.0, 38.0)
	_scatter("wire", 14, 0.9, 1.2)

## 撒一批同类型地物。位置随机但避开建筑与道路
func _scatter(kind: String, n: int, smin: float, smax: float) -> void:
	for i in n:
		var p := Vector2(rng.randf_range(420.0, 3380.0), rng.randf_range(140.0, 2460.0))
		_add_prop(kind, p, rng.randf_range(smin, smax))

## 地物贴图：同一种类里随机挑变体，避免整片战场长得一模一样
func _prop_texture(kind: String) -> Texture2D:
	var pool: Array = []
	match kind:
		"tree":
			pool = ["tree_green_large", "tree_green_small", "tree_brown_large", "tree_brown_small"]
		"bush":
			pool = ["bush_large", "bush_small"]
		"rock":
			pool = ["rock_large", "rock_small"]
		"barrel":
			pool = ["barrel_rust", "barrel_green", "barrel_red", "barrel_black"]
		"crate":
			pool = ["crate_wood", "crate_metal"]
		"barricade":
			pool = ["barricade_wood", "barricade_metal"]
		"sandbag":
			pool = ["sandbag_beige", "sandbag_brown"]
		"wire":
			pool = ["wire_straight", "wire_crooked"]
		_:
			return null
	return AssetDB.ktile(pool[rng.randi() % pool.size()])

func _add_prop(kind: String, pos: Vector2, size: float) -> void:
	if _solid_at(pos, 16.0):
		return
	props.append({"kind": kind, "pos": pos, "rot": rng.randf_range(-0.3, 0.3), "size": size})

func _draw_decor() -> void:
	# 履带
	var track_tex := AssetDB.ktile("tracks_large")
	for t in tracks:
		var from: Vector2 = t["from"]
		var to: Vector2 = t["to"]
		var a := (to - from).angle()
		var len := from.distance_to(to)
		var step := 46.0
		var n := int(len / step)
		for i in n:
			var p := from + Vector2(cos(a), sin(a)) * (i * step)
			if track_tex:
				draw_set_transform(p, a + PI * 0.5, Vector2(1.56, 1.56))
				draw_texture(track_tex, -Vector2(track_tex.get_width(), track_tex.get_height()) * 0.5,
					Color(1, 1, 1, 0.24))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for s in stains:
		var tex := AssetDB.ktile("oil_large") if s["kind"] == "oil" else AssetDB.kfx("expsmoke_5")
		if tex == null:
			continue
		var sz: float = s["size"]
		# 焦痕与油污去色：全屏提饱和之后，原本偏褐的焦痕会变成一滩暗红，
		# 看着像血。乘一层偏冷的灰把它拉回"烧过的地面"
		var tint := Color(0.80, 0.79, 0.76, 0.34 if s["kind"] == "oil" else 0.22)
		draw_set_transform(s["pos"], s["rot"], Vector2(sz / AssetDB.logical_width(tex), sz / AssetDB.logical_height(tex)))
		draw_texture(tex, -tex.get_size() * 0.5, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 地物改用真实节点而不是 draw_texture。
## 原因只有一个：描边是 CanvasItem 级别的材质，draw_texture 这种"在别人的 _draw 里
## 画一张贴图"的形式挂不上材质，树和油桶就只能是没有轮廓的贴片。
func _build_prop_nodes() -> void:
	props_root = Node2D.new()
	props_root.name = "Props"
	props_root.y_sort_enabled = true
	props_root.z_index = 1
	add_child(props_root)
	for p in props:
		var kind: String = p["kind"]
		var pos: Vector2 = p["pos"]
		var size: float = p["size"]
		var tex: Texture2D = _prop_texture(kind)
		var rot: float = p["rot"] if kind != "barrel" and kind != "crate" and kind != "rock" else 0.0
		if tex == null:
			continue
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.position = pos
		sp.rotation = rot
		# 铁丝网用原始尺寸（它是一条带子，按 size 缩放会变形）
		var k: float = 1.0 if kind == "wire" else size / AssetDB.logical_width(tex)
		sp.scale = Vector2(k, k)
		# 这些素材本身没有描边版本，用共享描边材质补一圈，
		# 和载具上"画进去的描边"接上同一种视觉语言
		AssetDB.apply_outline(sp)
		props_root.add_child(sp)

## 地物投影仍画在地表图层：投影必须在所有地物之下，否则后画的树会把
## 前一棵树的影子盖掉
func _draw_prop_shadows() -> void:
	for p in props:
		var kind: String = p["kind"]
		var pos: Vector2 = p["pos"]
		var size: float = p["size"]
		match kind:
			"tree":
				_ellipse_shadow(pos + Vector2(9, 12), size * 0.38, size * 0.24)
			"bush", "rock":
				_ellipse_shadow(pos + Vector2(4, 6), size * 0.40, size * 0.26)
			"barrel", "crate", "barricade", "sandbag":
				_ellipse_shadow(pos + Vector2(5, 7), size * 0.46, size * 0.30)

func _ellipse_shadow(center: Vector2, rx: float, ry: float) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * float(i) / 14.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color(0.16, 0.12, 0.09, 0.32))

# ============================================================ 建筑
func _generate_buildings() -> void:
	buildings.clear()
	# ---- 攻方基地掩体 ----
	_b("bunker", 120, 900, 180, 130, 5.0)
	_b("bunker", 120, 1580, 180, 130, 5.0)
	_b("wall", 360, 1180, 60, 240, 3.8)
	# ---- A 岩下村 ----
	var a_blocks := [
		[700, 420, 240, 170, 4.2], [700, 1020, 200, 150, 3.6],
		[700, 1680, 240, 170, 4.2], [700, 2180, 200, 150, 3.6],
		[1080, 300, 150, 250, 5.4], [1080, 1900, 150, 250, 5.4],
		[1160, 760, 300, 150, 3.8], [1160, 1620, 300, 150, 3.8],
		[1230, 1120, 170, 120, 4.6], [1230, 1360, 170, 120, 4.6],
		[900, 560, 90, 90, 3.2], [1030, 1480, 110, 110, 3.2],
	]
	for b in a_blocks:
		_b("house", b[0], b[1], b[2], b[3], b[4])
	# 村墙（留通道）
	_b("fence", 640, 900, 26, 300, 2.4); _b("fence", 640, 1400, 26, 300, 2.4)
	_b("fence", 1300, 900, 26, 300, 2.4); _b("fence", 1300, 1400, 26, 300, 2.4)
	_b("fence", 760, 660, 300, 26, 2.4); _b("fence", 1150, 660, 290, 26, 2.4)
	_b("fence", 760, 1480, 300, 26, 2.4); _b("fence", 1150, 1480, 290, 26, 2.4)
	# ---- B1 临时营地 ----
	_b("house", 1900, 620, 190, 120, 4.6)
	_b("fence", 1760, 440, 26, 250, 2.5); _b("fence", 2050, 440, 26, 250, 2.5)
	_b("fence", 1810, 330, 220, 26, 2.5); _b("fence", 1830, 760, 180, 26, 2.5)
	_b("house", 1620, 340, 300, 130, 5.2); _b("block", 2050, 200, 260, 420, 6.4)
	# ---- B2 贫民窟 ----
	_b("house", 1620, 2130, 300, 130, 5.2); _b("block", 2050, 1980, 260, 420, 6.4)
	_b("house", 1700, 1690, 150, 150, 4.0); _b("house", 1700, 760, 150, 150, 4.0)
	_b("house", 2380, 900, 150, 180, 4.4); _b("house", 2380, 1520, 150, 180, 4.4)
	_b("wall", 1560, 1180, 80, 320, 3.8); _b("wall", 1560, 1440, 80, 240, 3.8)
	# ---- 市政大楼（中央地标） ----
	_b("tower", 1960, 1080, 300, 440, 11.0)
	# ---- C 军需仓库 / 办公区 ----
	_b("house", 2620, 420, 220, 150, 5.0); _b("house", 2620, 1020, 240, 150, 4.4)
	_b("house", 2620, 1680, 240, 150, 4.4); _b("house", 2620, 2180, 220, 150, 5.0)
	_b("block", 3000, 300, 150, 260, 6.6); _b("block", 3000, 1900, 150, 260, 6.6)
	_b("warehouse", 3060, 760, 300, 160, 7.2); _b("warehouse", 3060, 1620, 300, 160, 7.2)
	_b("house", 3200, 1120, 180, 120, 4.6); _b("house", 3200, 1360, 180, 120, 4.6)
	_b("fence", 2560, 760, 26, 320, 2.7); _b("fence", 2560, 1300, 26, 320, 2.7)
	_b("fence", 3260, 760, 26, 320, 2.7); _b("fence", 3260, 1300, 26, 320, 2.7)
	_b("fence", 2700, 600, 300, 26, 2.7); _b("fence", 3090, 600, 150, 26, 2.7)
	_b("fence", 2700, 1700, 300, 26, 2.7); _b("fence", 3090, 1700, 150, 26, 2.7)
	# ---- 守方基地 ----
	_b("bunker", 3480, 880, 180, 140, 5.0)
	_b("bunker", 3480, 1580, 180, 140, 5.0)
	# ---- 程序化填充：让村落与城区真正密集（强制留通道） ----
	var districts := [
		{"x0": 660.0, "x1": 1350.0, "z0": 300.0, "z1": 2300.0, "tries": 200, "hw": [70, 150], "hd": [60, 130], "hh": [3.2, 5.6]},
		{"x0": 1560.0, "x1": 2420.0, "z0": 210.0, "z1": 2390.0, "tries": 220, "hw": [70, 170], "hd": [60, 140], "hh": [3.4, 6.8]},
		{"x0": 2570.0, "x1": 3330.0, "z0": 250.0, "z1": 2350.0, "tries": 200, "hw": [70, 180], "hd": [60, 150], "hh": [3.4, 7.4]},
	]
	for d in districts:
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var z0: float = d["z0"]
		var z1: float = d["z1"]
		for i in d["tries"]:
			var w := float(rng.randi_range(d["hw"][0], d["hw"][1]))
			var h := float(rng.randi_range(d["hd"][0], d["hd"][1]))
			var x: float = x0 + rng.randf() * (x1 - x0 - w)
			var z: float = z0 + rng.randf() * (z1 - z0 - h)
			var cx: float = x + w * 0.5
			var cz: float = z + h * 0.5
			if _on_road(cx, cz):
				continue
			if _overlaps(cx, cz, w, h, 10.0):
				continue
			var near_cap := false
			for c in GameConfig.CAPTURES:
				var cp: Vector2 = c["pos"]
				if Vector2(cx, cz).distance_to(cp) < 340.0:
					near_cap = true
					break
			if not near_cap and rng.randf() < 0.45:
				continue
			var hh := rng.randf_range(d["hh"][0], d["hh"][1])
			var type := "house"
			var r := rng.randf()
			if r < 0.12:
				type = "block"
			elif r < 0.22:
				type = "warehouse"
				hh = maxf(hh, 5.4)
			_b(type, x, z, w, h, hh)
			# 部分建筑挂沙袋
			if rng.randf() < 0.3:
				_add_cover(Vector2(cx, cz + h * 0.5 + 22.0), float(rng.randi_range(30, 54)))

func _b(type: String, x: float, z: float, w: float, h: float, height: float) -> void:
	buildings.append({"rect": Rect2(x, z, w, h), "height": height, "type": type})

func _add_cover(pos: Vector2, w: float) -> void:
	if _solid_at(pos, 18.0):
		return
	props.append({"kind": "sandbag", "pos": pos, "rot": rng.randf_range(0.0, TAU), "size": w})

func _overlaps(cx: float, cz: float, w: float, h: float, gap: float) -> bool:
	var r := Rect2(cx - w * 0.5 - gap, cz - h * 0.5 - gap, w + gap * 2.0, h + gap * 2.0)
	for b in buildings:
		if r.intersects(b["rect"]):
			return true
	return false

func _on_road(cx: float, cz: float) -> bool:
	if absf(cz - 1300.0) < 105.0:
		return true
	for x in [960.0, 1900.0, 2900.0]:
		if absf(cx - x) < 95.0:
			return true
	return false

func _solid_at(pos: Vector2, pad: float) -> bool:
	var r := Rect2(pos.x - pad, pos.y - pad, pad * 2.0, pad * 2.0)
	for b in buildings:
		if r.intersects(b["rect"]):
			return true
	return false

func _draw_buildings() -> void:
	for b in buildings:
		_draw_one_building(b)

## 建筑配色已统一收到 Palette.BUILD —— 改风格只需要改调色板一份

func _draw_one_building(b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var height: float = b["height"]
	var type: String = b["type"]
	var c: Dictionary = Palette.BUILD.get(type, Palette.BUILD["house"])
	# 围墙/栅栏的高度要单独压住：它们是"半人高的矮墙"，按普通建筑的比例
	# 拉起 55~87 像素之后会变成一片片竖着的木板，完全不像墙
	var off := clampf(height * (9.0 if type == "fence" or type == "wall" else 23.0), 8.0,
		34.0 if type == "fence" or type == "wall" else 120.0)
	var sx := -off * 0.44
	var sy := -off * 0.58
	var p := r.position
	var sz := r.size
	var w := sz.x
	var hh := sz.y
	# 硬投影：卡通风格里投影是"另一块更暗的色块"，不是柔和接触阴影，
	# 所以偏移加大、不透明度统一，不做出渐隐
	draw_rect(Rect2(p + Vector2(off * 0.58, off * 0.72), sz), Color(0.16, 0.12, 0.09, 0.34), true)

	# ---- 三个面：南立面（受光最亮）/ 东立面（背光最暗）/ 顶面 ----
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, hh), p + Vector2(w, hh),
		p + Vector2(w + sx, hh + sy), p + Vector2(sx, hh + sy)]), c["s"])
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(w, 0), p + Vector2(w, hh),
		p + Vector2(w + sx, hh + sy), p + Vector2(w + sx, sy)]), c["e"])
	var top := Rect2(p + Vector2(sx, sy), sz)
	draw_rect(top, c["top"], true)

	# ---- 顶面细节 ----
	match type:
		"warehouse":
			var x := 14.0
			while x < w:
				draw_rect(Rect2(top.position.x + x, top.position.y, 4, hh),
					Color(0, 0, 0, 0.13), true)
				draw_rect(Rect2(top.position.x + x + 4, top.position.y, 4, hh),
					Color(1, 1, 1, 0.10), true)
				x += 20.0
		"tower":
			# 地标高塔：顶面画一圈女儿墙 + 一个直升机坪十字
			draw_rect(Rect2(top.position + Vector2(10, 10), sz - Vector2(20, 20)),
				Palette.ROOF_TRIM.lerp(c["top"], 0.35), false, 3.0)
			var cc := top.position + sz * 0.5
			draw_line(cc + Vector2(-26, 0), cc + Vector2(26, 0), Palette.ROOF_TRIM, 4.0)
			draw_line(cc + Vector2(0, -26), cc + Vector2(0, 26), Palette.ROOF_TRIM, 4.0)
		"block":
			var gx := 30.0
			while gx < w - 20.0:
				draw_rect(Rect2(top.position.x + gx, top.position.y + 14, 16, hh - 28),
					Color(0, 0, 0, 0.14), true)
				gx += 52.0
		"wall", "fence":
			var wx := 0.0
			while wx < w:
				draw_rect(Rect2(top.position.x + wx, top.position.y, 3, hh),
					Color(0, 0, 0, 0.12), true)
				wx += 18.0
		"bunker":
			var bcc := top.position + sz * 0.5
			draw_circle(bcc, minf(w, hh) * 0.26, Palette.ROOF_TRIM)
			draw_circle(bcc, minf(w, hh) * 0.18, c["top"].darkened(0.15))
		_:
			# 民居屋顶：一条屋脊 + 一个烟囱
			draw_rect(Rect2(top.position + Vector2(6, 6), sz - Vector2(12, 12)),
				Palette.ROOF_TRIM, false, 2.0)
			var chim := Vector2(top.position.x + w * 0.72, top.position.y + hh * 0.24)
			draw_rect(Rect2(chim, Vector2(13, 13)), Palette.OUTLINE, true)
			draw_rect(Rect2(chim + Vector2(2, 2), Vector2(9, 9)), Palette.ROOF_TRIM, true)

	# ---- 南立面细节：门与窗 ----
	if type != "fence" and type != "wall" and hh >= 90.0:
		var door_w := minf(26.0, w * 0.18)
		var door := Rect2(p + Vector2(w * 0.5 - door_w * 0.5, hh - 30.0), Vector2(door_w, 30.0))
		draw_rect(door, Palette.OUTLINE, true)
		draw_rect(door.grow(-2.0), Color("#6b4326"), true)
		var win_w := 18.0
		var gx2 := 18.0
		while gx2 < w - win_w - 12.0:
			var win := Rect2(p + Vector2(gx2, hh - 40.0), Vector2(win_w, 16.0))
			draw_rect(win.grow(1.6), Palette.OUTLINE, true)
			draw_rect(win, Palette.WINDOW, true)
			gx2 += 40.0

	# ---- 描边：沿整个剪影走一圈闭合折线 ----
	# 早先只在几条边上描线，转角处会断开；闭合成一个多边形之后轮廓是连续的，
	# 这才有"贴纸边"的感觉
	var sil := PackedVector2Array([
		p + Vector2(0, hh),
		p + Vector2(w, hh),
		p + Vector2(w + sx, hh + sy),
		p + Vector2(w + sx, sy),
		p + Vector2(sx, sy),
		p + Vector2(sx, hh + sy),
		p + Vector2(0, hh)])
	var closed := sil.duplicate()
	closed.append(sil[0])
	draw_polyline(closed, Palette.OUTLINE, 3.0, true)
	# 面与面之间的内结构线用细一档的软描边
	draw_line(p + Vector2(sx, sy), p + Vector2(w + sx, sy), Palette.OUTLINE_SOFT, 1.6)
	draw_line(p + Vector2(sx, sy), p + Vector2(0, hh), Palette.OUTLINE_SOFT, 1.6)
	draw_line(p + Vector2(w + sx, sy), p + Vector2(w, hh), Palette.OUTLINE_SOFT, 1.6)
	draw_line(p + Vector2(sx, hh + sy), p + Vector2(0, hh), Palette.OUTLINE_SOFT, 1.6)

# ============================================================ 碰撞
func _build_obstacles() -> void:
	for b in buildings:
		var type: String = b["type"]
		var r: Rect2 = b["rect"]
		if type == "fence":
			# 围墙按细条碰撞，避免堵死通道
			pass
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = r.position + r.size * 0.5
		obstacles.add_child(cs)

# ============================================================ 导航
func _build_nav_grid() -> void:
	nav_grid = AStarGrid2D.new()
	var cols := int(ceil(GameConfig.WORLD_SIZE.x / CELL))
	var rows := int(ceil(GameConfig.WORLD_SIZE.y / CELL))
	nav_grid.region = Rect2i(0, 0, cols, rows)
	nav_grid.cell_size = Vector2(CELL, CELL)
	nav_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	nav_grid.update()
	# 标记障碍（含 1 格膨胀，避免贴墙卡住）
	var pad := 16.0
	for b in buildings:
		var r: Rect2 = b["rect"]
		var x0 := int(floor((r.position.x - pad) / CELL))
		var x1 := int(floor((r.position.x + r.size.x + pad) / CELL))
		var y0 := int(floor((r.position.y - pad) / CELL))
		var y1 := int(floor((r.position.y + r.size.y + pad) / CELL))
		for gx in range(maxi(0, x0), mini(cols - 1, x1) + 1):
			for gy in range(maxi(0, y0), mini(rows - 1, y1) + 1):
				nav_grid.set_point_solid(Vector2i(gx, gy), true)

## 网格坐标 -> 世界坐标（格中心）
func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / CELL), int(p.y / CELL))

## 取路径（世界坐标），失败返回空数组
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	# 必须先夹取到网格范围内再查。
	# 注意 _clamp_cell 是返回值而不是原地修改 —— Vector2i 是值类型，
	# 写 `_clamp_cell(a)` 那种"传进去改"的形式在 GDScript 里是空操作，
	# 越界坐标会一路带到 AStarGrid2D 里刷 out of bounds 报错。
	var a := _clamp_cell(world_to_cell(from))
	var b := _clamp_cell(world_to_cell(to))
	var solid_a := nav_grid.is_point_solid(a)
	var solid_b := nav_grid.is_point_solid(b)
	if solid_a:
		a = _nearest_open(a)
	if solid_b:
		b = _nearest_open(b)
	if nav_grid.is_point_solid(a) or nav_grid.is_point_solid(b):
		return PackedVector2Array()
	var cells := nav_grid.get_id_path(a, b)
	var out := PackedVector2Array()
	for c in cells:
		out.append(cell_to_world(c))
	if out.size() > 1:
		out[out.size() - 1] = to
	return out

func _clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(c.x, 0, nav_grid.region.size.x - 1),
		clampi(c.y, 0, nav_grid.region.size.y - 1))

func _nearest_open(c: Vector2i) -> Vector2i:
	if not nav_grid.is_point_solid(c):
		return c
	for r in range(1, 10):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := Vector2i(c.x + dx, c.y + dy)
				if n.x < 0 or n.y < 0 or n.x >= nav_grid.region.size.x or n.y >= nav_grid.region.size.y:
					continue
				if not nav_grid.is_point_solid(n):
					return n
	return c

# ============================================================ 查询
## 判断世界坐标点是否在建筑实体内部（用于视线遮挡）
func blocks_sight(p: Vector2) -> bool:
	for b in buildings:
		if b["type"] == "fence":
			continue
		if b["rect"].has_point(p):
			return true
	return false

## 两点之间是否通视
func line_of_sight(from: Vector2, to: Vector2) -> bool:
	var steps := int(maxf(2.0, from.distance_to(to) / 48.0))
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / float(steps))
		if blocks_sight(p):
			return false
	return true

func is_walkable(p: Vector2) -> bool:
	return not _solid_at(p, 12.0)
