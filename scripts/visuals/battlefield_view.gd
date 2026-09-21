extends Node3D
class_name BattlefieldView

const SCALE := 0.025
const Art := preload("res://scripts/visuals/field_art.gd")
var map: Node2D
var camera: Camera3D
var models: Dictionary = {}
var objectives: Dictionary = {}
var batches: Dictionary = {}
var effects: Array = []
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var refresh_timer := 0.0
var center := Vector3(23, 0, 20)
var imported_scenes: Dictionary = {}
var breeze: Array[Node3D] = []
var grass_material: ShaderMaterial

static func point(pos: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(pos.x * SCALE, height, pos.y * SCALE)

func setup(world: Node2D) -> void:
	map = world
	rng.seed = 271828
	add_to_group("battlefield_view")
	_build_lighting()
	_build_terrain()
	for index in map.buildings.size():
		_build_house(map.buildings[index], index)
	_build_props()
	_build_meadow()
	_flush_batches()
	_build_objectives()
	EventBus.shot_fired.connect(_shot)
	EventBus.explosion.connect(_explosion)
	EventBus.impact.connect(_impact)
	EventBus.unit_spawned.connect(_add_soldier)
	EventBus.fort_built.connect(func(_team, _kind, _pos): refresh_timer = 0.0)
	for unit in TeamManager.units:
		_add_soldier(unit)
	if OS.get_cmdline_user_args().has("--pixel-art"):
		_build_postprocess()

func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#87c5bb")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a3d3d8")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.82
	environment.ssao_enabled = true
	environment.ssao_radius = 1.1
	environment.ssao_intensity = 1.15
	environment.ssil_enabled = true
	environment.ssil_intensity = 0.65
	environment.fog_enabled = true
	environment.fog_light_color = Color("#a3d2c7")
	environment.fog_density = 0.00045
	environment.fog_height = 0.0
	environment.fog_height_density = 0.018
	environment.glow_enabled = UserSettings.glow_enabled
	environment.glow_intensity = 0.35
	var sky := WorldEnvironment.new()
	sky.environment = environment
	add_child(sky)
	UserSettings.changed.connect(func(): environment.glow_enabled = UserSettings.glow_enabled)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -38, 0)
	sun.light_color = Color("#fff0cc")
	sun.light_energy = 1.05
	sun.light_angular_distance = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	sun.shadow_bias = 0.04
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 135, 0)
	fill.light_color = Color("#9cbfd4")
	fill.light_energy = 0.22
	add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23.0
	camera.near = 0.1
	camera.far = 160
	camera.environment = environment
	add_child(camera)
	camera.make_current()
	_update_camera(1.0)

func _build_postprocess() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var filter := ColorRect.new()
	filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://assets/shaders/field_pixel.gdshader")
	filter.material = shader_material
	layer.add_child(filter)

func _stamp(pos: Vector3, size: Vector3, color: String, kind: String = "box", angle: float = 0.0) -> void:
	var key := color + ":" + kind
	if not batches.has(key):
		batches[key] = []
	var basis := Basis(Vector3.UP, angle).scaled(size)
	batches[key].append(Transform3D(basis, pos))

func _flush_batches() -> void:
	for key: String in batches:
		var entries: Array = batches[key]
		var pieces := key.split(":")
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = Art.primitive(pieces[1])
		mesh.instance_count = entries.size()
		for index in entries.size():
			mesh.set_instance_transform(index, entries[index])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mesh
		instance.material_override = Art.material(pieces[0])
		add_child(instance)
	batches.clear()

func _build_terrain() -> void:
	var ground := Art.part(self, Vector3(47.5, -0.4, 32.5), Vector3(110, 0.8, 80), "a89974")
	var ground_material := ShaderMaterial.new()
	ground_material.shader = preload("res://assets/shaders/field_ground.gdshader")
	ground.material_override = ground_material
	var soil := ["a59972", "b1a17a", "b6a47d", "a49671", "b4a27a"]
	for road in map._road_rects():
		var position := Vector3((road.x + road.w / 2) * SCALE, 0.014, (road.y + road.h / 2) * SCALE)
		var dimensions := Vector3(road.w * SCALE, 0.035, road.h * SCALE)
		_stamp(position, dimensions + Vector3(0.5, 0, 0.5), "756f59")
		_stamp(position + Vector3(0, 0.025, 0), dimensions, "656961")
		var horizontal: bool = road.w > road.h
		var count := int(maxf(dimensions.x, dimensions.z) / 1.6)
		for step in count:
			var marking := Vector3(road.x * SCALE + 0.6 + step * 1.6, 0.063, position.z) if horizontal else Vector3(position.x, 0.063, road.y * SCALE + 0.6 + step * 1.6)
			_stamp(marking, Vector3(0.66, 0.012, 0.055) if horizontal else Vector3(0.055, 0.012, 0.66), "bdb58b")
	for index in 6500:
		var pos := Vector2(rng.randf_range(20, 3780), rng.randf_range(20, 2580))
		var on_road: bool = map._on_road(pos.x, pos.y)
		var width := rng.randf_range(0.04, 0.18)
		_stamp(point(pos, 0.078 if on_road else 0.008), Vector3(width, 0.014, width * 0.55), "797a6b" if on_road else soil[index % soil.size()])
	for index in 800:
		var pos := Vector2(rng.randf_range(30, 3770), rng.randf_range(30, 2570))
		if map._on_road(pos.x, pos.y) or map._solid_at(pos, 20):
			continue
		var color: String = ["727953", "82845b", "8e9165"][index % 3]
		for blade in 3:
			_stamp(point(pos, 0.09) + Vector3(blade * 0.08, 0, 0), Vector3(0.055, rng.randf_range(0.13, 0.28), 0.08), color, "cone")
	for index in 220:
		var pos := Vector2(rng.randf_range(20, 3780), rng.randf_range(20, 2580))
		if map._on_road(pos.x, pos.y):
			continue
		_stamp(point(pos, 0.09), Vector3(0.3, 0.20, 0.25), "8a8e7b", "sphere", rng.randf() * TAU)

func _build_house(building: Dictionary, index: int) -> void:
	var rect: Rect2 = building.rect
	var pos := point(rect.get_center())
	var width := rect.size.x * SCALE
	var depth := rect.size.y * SCALE
	var height := float(building.height) * 0.45
	var type: String = building.type
	if type == "wall" or type == "fence":
		height = 0.8 if type == "fence" else 1.4
		_stamp(pos + Vector3(0, height / 2, 0), Vector3(width, height, depth), "96967d")
		_stamp(pos + Vector3(0, height, 0), Vector3(width + 0.07, 0.12, depth + 0.07), "c0b593")
		for course in 3:
			_stamp(pos + Vector3(0, 0.18 + course * 0.24, depth / 2 + 0.015), Vector3(width, 0.025, 0.025), "737864")
		return
	var wall: String = ["c3b08a", "b8ad8e", "b7aa8c", "c6b694"][index % 4]
	var roof: String = ["637c77", "768982", "a37151", "6f807b"][index % 4]
	if type == "bunker":
		wall = "7c8778"
		roof = "606e64"
	_stamp(pos + Vector3(0, 0.10, 0), Vector3(width + 0.30, 0.20, depth + 0.30), "797e6b")
	_stamp(pos + Vector3(0, height / 2, 0), Vector3(width, height, depth), wall)
	_stamp(pos + Vector3(0, 0.35, 0), Vector3(width + 0.02, 0.25, depth + 0.02), "a49676")
	_stamp(pos + Vector3(0, height, 0), Vector3(width + 0.28, 0.18, depth + 0.28), "d0c49f")
	_stamp(pos + Vector3(0, height + 0.14, 0), Vector3(width, 0.14, depth), roof)
	for ridge in range(int(width / 0.18)):
		_stamp(pos + Vector3(-width / 2 + ridge * 0.18, height + 0.23, 0), Vector3(0.035, 0.07, depth), roof)
	for side in [-1.0, 1.0]:
		_stamp(pos + Vector3(side * (width / 2 - 0.1), height / 2, depth / 2 + 0.025), Vector3(0.15, height, 0.08), "ded0a8")
		_stamp(pos + Vector3(side * (width / 2 + 0.07), height * 0.5, depth / 2 + 0.06), Vector3(0.08, height, 0.08), "6a7b74", "cylinder")
	var window_count := maxi(1, int(width / 1.35))
	for window in window_count:
		var offset := -width / 2 + (window + 0.5) * width / window_count
		var window_pos := pos + Vector3(offset, height * 0.63, depth / 2 + 0.02)
		_stamp(window_pos, Vector3(0.66, 0.79, 0.10), "ded0aa")
		_stamp(window_pos + Vector3(0, 0, 0.065), Vector3(0.49, 0.61, 0.035), "334f50")
		_stamp(window_pos + Vector3(0, 0, 0.09), Vector3(0.04, 0.63, 0.025), "92a399")
		_stamp(window_pos + Vector3(0, -0.36, 0.1), Vector3(0.76, 0.07, 0.20), "e0cc9e")
		_stamp(window_pos + Vector3(-0.40, 0, 0.04), Vector3(0.18, 0.68, 0.08), roof)
	var door_pos := pos + Vector3(width * 0.24, 0.59, depth / 2 + 0.04)
	_stamp(door_pos, Vector3(0.74, 1.18, 0.10), "716b52")
	_stamp(door_pos + Vector3(0, 0, 0.07), Vector3(0.58, 1.06, 0.035), "465c57")
	_stamp(door_pos + Vector3(0, 0.73, 0.18), Vector3(1.07, 0.09, 0.66), roof)
	_stamp(door_pos + Vector3(0.18, -0.10, 0.11), Vector3(0.035, 0.17, 0.025), "d2ba7b")
	for chip in 14:
		var offset := Vector3(rng.randf_range(-width * 0.44, width * 0.44), rng.randf_range(0.15, height * 0.4), depth / 2 + 0.04)
		_stamp(pos + offset, Vector3(rng.randf_range(0.08, 0.3), 0.055, 0.025), "918a70")
	var roof_pos := pos + Vector3(-width * 0.25, height + 0.46, -depth * 0.18)
	_stamp(roof_pos, Vector3(0.69, 0.54, 0.59), "a1aaa0")
	for fin in 5:
		_stamp(roof_pos + Vector3(-0.24 + fin * 0.12, 0.29, 0), Vector3(0.035, 0.035, 0.44), "5b706a")
	if index % 4 == 0:
		_stamp(pos + Vector3(width * 0.20, height + 0.61, 0), Vector3(0.72, 1.0, 0.72), "818c7d", "cylinder")
		_stamp(pos + Vector3(width * 0.20, height + 1.12, 0), Vector3(0.79, 0.09, 0.79), "bec1a5", "cylinder")
	if type == "tower":
		_stamp(pos + Vector3(0, height + 1.5, 0), Vector3(0.10, 3, 0.10), "596f68")
		_stamp(pos + Vector3(0, height + 2.1, 0), Vector3(2.8, 0.06, 0.08), "8a9f95")
		_stamp(pos + Vector3(0, height + 2.55, 0), Vector3(1.7, 0.05, 0.07), "8a9f95")
	if index % 3 == 0:
		var plaque := Label3D.new()
		plaque.text = "%02d" % (index + 1)
		plaque.font_size = 64
		plaque.pixel_size = 0.007
		plaque.modulate = Color("ecdbad")
		plaque.outline_size = 0
		plaque.position = pos + Vector3(-width * 0.33, height * 0.32, depth / 2 + 0.07)
		add_child(plaque)

func _build_props() -> void:
	for prop in map.props:
		var pos := point(prop.pos)
		var type: String = prop.kind
		if type.contains("tree"):
			_build_tree(pos)
		elif type.contains("barrel"):
			_stamp(pos + Vector3(0, 0.36, 0), Vector3(0.49, 0.72, 0.49), "8d5e47", "cylinder")
			for level in [0.12, 0.58]:
				_stamp(pos + Vector3(0, level, 0), Vector3(0.51, 0.06, 0.51), "b29264", "cylinder")
		elif type.contains("sandbag"):
			for row in 2:
				for bag in 4:
					_stamp(pos + Vector3((bag - 1.5) * 0.39 + row * 0.12, 0.14 + row * 0.23, 0), Vector3(0.45, 0.27, 0.42), "ae9e73", "sphere")
		elif type.contains("crate") or type.contains("barricade"):
			_stamp(pos + Vector3(0, 0.38, 0), Vector3(0.76, 0.76, 0.72), "887c52")
			for side in [-1.0, 1.0]:
				_stamp(pos + Vector3(side * 0.24, 0.40, 0), Vector3(0.065, 0.80, 0.77), "b3a477")
		elif type.contains("rock"):
			_import_prop("nature/rock_largeA", pos, 0.9)
	for tree_pos in [Vector2(580, 520), Vector2(600, 850), Vector2(1120, 950), Vector2(1060, 1590), Vector2(490, 1750), Vector2(1460, 480), Vector2(1480, 2050), Vector2(2430, 740)]:
		_build_tree(point(tree_pos))
	for pole_pos in [Vector2(875, 1160), Vector2(1510, 1160), Vector2(2430, 1160), Vector2(3400, 1160)]:
		var pos := point(pole_pos)
		_stamp(pos + Vector3(0, 1.7, 0), Vector3(0.15, 3.4, 0.15), "716b50")
		_stamp(pos + Vector3(0, 3.35, 0), Vector3(1.15, 0.11, 0.12), "776f54")
		for side in [-0.4, 0.4]:
			_stamp(pos + Vector3(side, 3.48, 0), Vector3(0.09, 0.2, 0.09), "b3c3b5", "cylinder")

func _build_meadow() -> void:
	for index in 1200:
		var pos := Vector2(rng.randf_range(30, 3770), rng.randf_range(30, 2570))
		if map._on_road(pos.x, pos.y) or map._solid_at(pos, 28):
			continue
		var height := rng.randf_range(0.18, 0.46)
		var color: String = ["477f35", "5d9636", "70a941", "84b849"][index % 4]
		_stamp(point(pos, 0.06 + height * 0.5), Vector3(0.045, height, 0.045), color, "cone", rng.randf() * TAU)

func _build_tree(pos: Vector3) -> void:
	var names := ["nature/tree_palmDetailedTall", "nature/tree_palmBend", "nature/tree_palmDetailedShort"]
	var tree := _import_prop(names[rng.randi_range(0, names.size() - 1)], pos, rng.randf_range(2.8, 4.0))
	if tree != null:
		breeze.append(tree)
	else:
		_stamp(pos + Vector3(0, 1.1, 0), Vector3(0.28, 2.2, 0.28), "6d6949", "cone")
	for cluster in 6:
		var angle := cluster * TAU / 6.0
		var offset := Vector3(cos(angle) * 0.58, 2.45 + rng.randf_range(-0.12, 0.20), sin(angle) * 0.58)
		_stamp(pos + offset, Vector3(0.92, 0.55, 0.82), "2f7d3c" if cluster % 2 else "459449", "sphere")
	_stamp(pos + Vector3(0, 2.72, 0), Vector3(0.98, 0.62, 0.92), "6bb34c", "sphere")

func _import_prop(id: String, pos: Vector3, height: float) -> Node3D:
	if not imported_scenes.has(id):
		var path := "res://assets/field_kit/%s.glb" % id
		if not ResourceLoader.exists(path):
			return null
		imported_scenes[id] = load(path)
	var model: Node3D = imported_scenes[id].instantiate()
	add_child(model)
	model.scale = Vector3.ONE * height * 0.72
	model.position = pos
	model.rotation.y = rng.randf() * TAU
	return model

func _model_bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform := parent_transform * node.transform
	var bounds := AABB()
	if node is MeshInstance3D:
		bounds = transform * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _model_bounds(child, transform)
			if child_bounds.size != Vector3.ZERO:
				bounds = child_bounds if bounds.size == Vector3.ZERO else bounds.merge(child_bounds)
	return bounds

func _build_objectives() -> void:
	for capture in GameConfig.CAPTURES:
		var root := Node3D.new()
		root.position = point(capture.pos, 0.07)
		add_child(root)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = capture.radius * SCALE - 0.045
		torus.outer_radius = capture.radius * SCALE + 0.045
		torus.rings = 64
		torus.ring_segments = 6
		ring.mesh = torus
		root.add_child(ring)
		Art.part(root, Vector3(0, 0.13, 0), Vector3(0.85, 0.26, 0.85), "666d57")
		Art.part(root, Vector3(0, 1.25, 0), Vector3(0.06, 2.5, 0.06), "b7b396", "cylinder")
		var flag := Art.part(root, Vector3(0.42, 2.16, 0), Vector3(0.8, 0.48, 0.035), "dc7b56")
		var label := Label3D.new()
		label.text = capture.id
		label.font = UiTheme.cjk_font(true)
		label.font_size = 58
		label.pixel_size = 0.01
		label.position.y = 3.0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color("ffe4ae")
		root.add_child(label)
		objectives[capture.id] = {"root": root, "ring": ring, "flag": flag, "label": label, "segment": capture.seg}

func _add_soldier(unit: Node2D) -> void:
	if models.has(unit):
		return
	var model := Art.soldier(unit.team, unit.op_class)
	add_child(model)
	models[unit] = {"root": model, "type": "soldier", "phase": rng.randf() * TAU}
	var marker := Art.part(model, Vector3(0, 0.025, 0), Vector3(0.7, 0.025, 0.7), "5ccfc5" if unit.team == 0 else "cd7457", "cylinder", true)
	marker.name = "Marker"
	marker.visible = unit.is_player

func _sync_entities() -> void:
	for vehicle in TeamManager.vehicles:
		if not is_instance_valid(vehicle) or models.has(vehicle):
			continue
		var model := Art.vehicle(vehicle.team, vehicle.kind)
		add_child(model)
		models[vehicle] = {"root": model, "type": "vehicle"}
	for fort in CommandOps.forts:
		if not is_instance_valid(fort) or models.has(fort):
			continue
		var model := Art.vehicle(fort.team, 2)
		model.scale = Vector3.ONE * 0.6
		add_child(model)
		models[fort] = {"root": model, "type": "fort"}

func _process(delta: float) -> void:
	if map == null:
		return
	elapsed += delta
	for index in breeze.size():
		breeze[index].rotation.z = sin(elapsed * 1.2 + index * 0.7) * 0.013
	refresh_timer -= delta
	if refresh_timer <= 0:
		_sync_entities()
		refresh_timer = 0.25
	_update_camera(delta)
	for unit in models.keys():
		var record: Dictionary = models[unit]
		var model: Node3D = record.root
		if not is_instance_valid(unit):
			model.queue_free()
			models.erase(unit)
			continue
		model.visible = unit.alive
		model.position = point(unit.global_position)
		if record.type == "soldier":
			model.visible = unit.alive and unit.in_vehicle == null
			model.rotation.y = -unit.aim_dir.angle()
			model.rotation.z = -1.25 if unit.downed else 0.0
			var stride := sin(elapsed * (18 if unit.sprinting else 12) + record.phase) * minf(unit.velocity.length() / 200.0, 1.0)
			model.get_node("LeftLeg").rotation.z = stride * 0.55
			model.get_node("RightLeg").rotation.z = -stride * 0.55
			model.get_node("Torso").position.y = absf(stride) * 0.045
			model.get_node("Torso/Gun").rotation.z = -0.45 if unit.is_reloading else 0.0
			model.get_node("Torso/Gun").position.x = lerpf(model.get_node("Torso/Gun").position.x, 0.28, delta * 14.0)
			model.get_node("Marker").visible = unit.is_player
		else:
			var angle: float = unit.body_angle if record.type == "vehicle" else unit.aim_angle
			model.rotation.y = -angle
			if model.has_node("Turret"):
				model.get_node("Turret").rotation.y = -(unit.turret_angle - angle) if record.type == "vehicle" else 0.0
			if record.type == "vehicle" and unit.is_air:
				model.position.y = 4.0 + sin(elapsed * 1.5) * 0.15
				model.get_node("Rotor").rotation.y += delta * 45
	for id: String in objectives:
		var objective: Dictionary = objectives[id]
		var state: Dictionary = MatchState.captures[id]
		var active: bool = objective.segment == MatchState.unlocked_segment
		var color := "57c9bf" if state.owner == 0 else "d88659"
		if not active:
			color = "89958b"
		objective.ring.material_override = Art.material(color, true)
		objective.flag.material_override = Art.material(color)
		objective.label.text = id + ("  %.0f%%" % state.progress if active and state.progress > 0 else "")
		objective.label.modulate = Color(color)
	_update_effects(delta)

func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target := point(map.camera.global_position) if map != null else center
	center = center.lerp(target, minf(1.0, delta * 9.0))
	var zoom: float = map.camera.zoom.x if map != null else 1.0
	camera.size = lerpf(camera.size, 24.0 / maxf(zoom, 0.4), minf(1.0, delta * 6.0))
	var shake := ImpactFx.offset() * SCALE
	camera.position = center + Vector3(shake.x, 28, 24 + shake.y)
	camera.look_at(center + Vector3(shake.x, 0, shake.y), Vector3.UP)

func mouse_world() -> Vector2:
	return screen_to_world(get_viewport().get_mouse_position())

func screen_to_world(screen: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit == null:
		return Vector2(center.x, center.z) / SCALE
	return Vector2(hit.x, hit.z) / SCALE

func world_to_screen(world: Vector2, height: float = 0.0) -> Vector2:
	return camera.unproject_position(point(world, height))

func _effect(pos: Vector3, size: Vector3, color: String, lifetime: float, speed: Vector3 = Vector3.ZERO, kind: String = "sphere", lit: bool = true) -> Node3D:
	if effects.size() >= 240:
		return null
	var piece := Art.part(self, pos, size, color, kind, lit)
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.append({"node": piece, "time": lifetime, "duration": lifetime, "speed": speed, "scale": size})
	return piece

func _shot(shooter: Node2D, origin: Vector2, direction: Vector2, weapon: String) -> void:
	var height := 0.94
	if shooter is CombatVehicle:
		height = 4.45 if shooter.is_air else 1.16
	var pos := point(origin, height)
	var muzzle := _effect(pos, Vector3(0.6, 0.16, 0.16), "fff1b4", 0.055, Vector3.ZERO, "sphere")
	if muzzle != null:
		muzzle.rotation.y = -direction.angle()
	if models.has(shooter) and shooter is Soldier:
		models[shooter].root.get_node("Torso/Gun").position.x = 0.23
	var tracer := _effect(pos, Vector3(0.75, 0.028, 0.028), "ffe7a2", 0.11, Vector3(direction.x, 0, direction.y) * (38.0 if weapon != "sniper" else 60.0), "box")
	if tracer != null:
		tracer.rotation.y = -direction.angle()

func _explosion(pos: Vector2, strength: float, _kind: String) -> void:
	var size := clampf(strength, 0.65, 2.6)
	for index in 10:
		var offset := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.1, 0.9), rng.randf_range(-0.6, 0.6)) * size
		_effect(point(pos, 0.4) + offset, Vector3.ONE * size * rng.randf_range(0.45, 1.0), "ffbf66" if index % 2 == 0 else "df7749", 0.24 + index * 0.025, offset * 1.7)
	for index in 8:
		var offset := Vector3(rng.randf_range(-0.6, 0.6), 0.5, rng.randf_range(-0.6, 0.6))
		_effect(point(pos, 0.3) + offset, Vector3.ONE * size * 0.8, "656e63" if index % 2 == 0 else "89907b", 1.2 + rng.randf(), Vector3(offset.x, 1.3, offset.z), "sphere", false)

func _impact(pos: Vector2, _normal: Vector2, kind: String) -> void:
	for index in 2:
		_effect(point(pos, 0.4), Vector3.ONE * 0.09, "dfac76" if kind != "blood" else "9a604b", 0.22, Vector3(rng.randf_range(-1, 1), 1.0, rng.randf_range(-1, 1)))

func _update_effects(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		effect.time -= delta
		if effect.time <= 0:
			effect.node.queue_free()
			effects.remove_at(index)
			continue
		effect.node.position += effect.speed * delta
		effect.node.scale = effect.scale * minf(1.0, effect.time / effect.duration * 2.0)
