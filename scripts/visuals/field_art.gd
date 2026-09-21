extends RefCounted
class_name FieldArt

static var materials: Dictionary = {}
static var meshes: Dictionary = {}

static func material(color: String, emissive: bool = false) -> StandardMaterial3D:
	var key := color + str(emissive)
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = 0.92
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	if emissive:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.emission_enabled = true
		result.emission = Color(color)
	materials[key] = result
	return result

static func primitive(kind: String) -> Mesh:
	if meshes.has(kind):
		return meshes[kind]
	var result: Mesh
	match kind:
		"sphere":
			var shape := SphereMesh.new()
			shape.radius = 0.5
			shape.height = 1.0
			shape.radial_segments = 12
			shape.rings = 6
			result = shape
		"cylinder":
			var shape := CylinderMesh.new()
			shape.top_radius = 0.5
			shape.bottom_radius = 0.5
			shape.height = 1.0
			shape.radial_segments = 12
			result = shape
		"cone":
			var shape := CylinderMesh.new()
			shape.top_radius = 0.05
			shape.bottom_radius = 0.5
			shape.height = 1.0
			shape.radial_segments = 7
			result = shape
		_:
			result = BoxMesh.new()
	meshes[kind] = result
	return result

static func part(parent: Node3D, pos: Vector3, size: Vector3, color: String,
		kind: String = "box", emissive: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = primitive(kind)
	instance.material_override = material(color, emissive)
	instance.position = pos
	instance.scale = size
	parent.add_child(instance)
	return instance

static func soldier(team: int, role: int) -> Node3D:
	var root := Node3D.new()
	var uniform := "65796a" if team == 0 else "a07756"
	var helmet := "718577" if team == 0 else "a58c66"
	var armor := "394b48" if team == 0 else "605246"
	var accent := "63ded5" if team == 0 else "e47a53"
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LeftLeg" if side < 0 else "RightLeg"
		leg.position = Vector3(0, 0.60, side * 0.17)
		root.add_child(leg)
		part(leg, Vector3(0, -0.19, 0), Vector3(0.27, 0.42, 0.24), uniform)
		part(leg, Vector3(0.08, -0.48, 0), Vector3(0.39, 0.18, 0.28), "303834")
		part(leg, Vector3(0.14, -0.28, 0), Vector3(0.10, 0.20, 0.26), armor)
	var torso := Node3D.new()
	torso.name = "Torso"
	root.add_child(torso)
	part(torso, Vector3(0, 0.90, 0), Vector3(0.40, 0.54, 0.57), uniform, "sphere")
	part(torso, Vector3(0.12, 0.91, 0), Vector3(0.34, 0.40, 0.52), armor)
	part(torso, Vector3(-0.26, 0.94, 0), Vector3(0.24, 0.48, 0.43), "58614a")
	part(torso, Vector3(-0.40, 0.89, 0), Vector3(0.07, 0.24, 0.25), "a5976d")
	for pocket in [-0.17, 0.0, 0.17]:
		part(torso, Vector3(0.32, 0.79, pocket), Vector3(0.11, 0.21, 0.13), "a09972")
	part(torso, Vector3(0, 0.66, 0), Vector3(0.45, 0.10, 0.60), "292f2b")
	part(torso, Vector3(0.03, 1.36, 0), Vector3(0.40, 0.44, 0.40), "d4a77b", "sphere")
	part(torso, Vector3(-0.025, 1.49, 0), Vector3(0.57, 0.40, 0.56), helmet, "sphere")
	part(torso, Vector3(0.05, 1.45, 0), Vector3(0.59, 0.08, 0.57), helmet)
	part(torso, Vector3(0.24, 1.38, 0), Vector3(0.06, 0.11, 0.33), "303f40")
	part(torso, Vector3(0.277, 1.40, -0.10), Vector3(0.025, 0.04, 0.10), "b5d2bd")
	part(torso, Vector3(0.23, 1.22, 0), Vector3(0.12, 0.13, 0.29), "584f40")
	for side in [-1.0, 1.0]:
		var arm := part(torso, Vector3(0.12, 1.02, side * 0.37), Vector3(0.30, 0.33, 0.27), uniform, "sphere")
		arm.rotation.z = -0.5
		part(torso, Vector3(0.36, 0.91, side * 0.27), Vector3(0.34, 0.19, 0.18), "c99b71", "sphere")
		part(torso, Vector3(0.08, 1.08, side * 0.51), Vector3(0.17, 0.09, 0.025), accent, "box", true)
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0.28, 0.96, -0.25)
	torso.add_child(gun)
	var barrel := 0.87 if role == 3 else 0.57
	part(gun, Vector3(0.23, 0, 0), Vector3(0.58, 0.16, 0.14), "293332")
	part(gun, Vector3(-0.14, -0.035, 0), Vector3(0.27, 0.12, 0.15), "716d51")
	part(gun, Vector3(0.12, -0.14, 0), Vector3(0.14, 0.25, 0.11), "424c45")
	part(gun, Vector3(barrel, 0.03, 0), Vector3(0.44, 0.065, 0.075), "343b39")
	part(gun, Vector3(0.20, 0.14, 0), Vector3(0.20, 0.11, 0.09), "242e2e")
	if role == 1:
		part(torso, Vector3(-0.405, 1.01, 0), Vector3(0.025, 0.20, 0.06), "e8ded0")
		part(torso, Vector3(-0.41, 1.01, 0), Vector3(0.025, 0.065, 0.20), "e8ded0")
	if role == 2:
		var launcher := part(torso, Vector3(-0.36, 1.08, 0.31), Vector3(0.21, 0.98, 0.21), "525d41", "cylinder")
		launcher.rotation.z = -0.23
	return root

static func vehicle(team: int, kind: int) -> Node3D:
	var root := Node3D.new()
	var paint := "768376" if team == 0 else "a68c63"
	var light := "a0aa8a" if team == 0 else "c9ac7b"
	var dark := "3e514d" if team == 0 else "716346"
	if kind == 3:
		part(root, Vector3(0, 0.5, 0), Vector3(2.7, 1.0, 1.2), paint, "sphere")
		part(root, Vector3(0.8, 0.55, 0), Vector3(1.10, 0.7, 1.02), "38585a", "sphere")
		part(root, Vector3(-1.7, 0.6, 0), Vector3(2.8, 0.26, 0.29), dark)
		part(root, Vector3(-2.8, 0.90, 0), Vector3(0.5, 0.7, 0.14), paint)
		var rotor := Node3D.new()
		rotor.name = "Rotor"
		rotor.position.y = 1.25
		root.add_child(rotor)
		part(rotor, Vector3.ZERO, Vector3(5.4, 0.06, 0.12), "263936")
		part(rotor, Vector3.ZERO, Vector3(0.12, 0.06, 5.4), "263936")
		for side in [-1.0, 1.0]:
			part(root, Vector3(0, -0.05, side * 0.65), Vector3(2.4, 0.10, 0.10), "33413d")
		return root
	var wheeled := kind == 1 or kind == 4
	var length := 2.55 if kind == 4 else 3.5
	part(root, Vector3(0, 0.54, 0), Vector3(length, 0.58, 1.66), paint)
	part(root, Vector3(0.14, 0.91, 0), Vector3(length * 0.72, 0.20, 1.47), light)
	for side in [-1.0, 1.0]:
		part(root, Vector3(0, 0.31, side * 0.96), Vector3(length + 0.05, 0.53, 0.37), "303833")
		for wheel in range(5):
			var tire := part(root, Vector3(-length * 0.4 + wheel * length * 0.2, 0.33, side * 1.02), Vector3(0.54, 0.20, 0.54), "4f5a4d", "cylinder")
			tire.rotation.x = PI / 2
			part(root, Vector3(-length * 0.4 + wheel * length * 0.2, 0.70, side * 0.99), Vector3(length * 0.17, 0.17, 0.12), paint)
		part(root, Vector3(length * 0.50, 0.70, side * 0.60), Vector3(0.06, 0.14, 0.20), "f3d69a", "box", true)
	for vent in range(7):
		part(root, Vector3(-length * 0.30 + vent * 0.10, 1.02, 0), Vector3(0.04, 0.025, 0.87), dark)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position.y = 1.02
	root.add_child(turret)
	part(turret, Vector3.ZERO, Vector3(1.28, 0.52, 1.14), dark, "cylinder")
	part(turret, Vector3(0.12, 0.13, 0), Vector3(1.45, 0.38, 1.03), paint)
	part(turret, Vector3(-0.24, 0.38, 0.10), Vector3(0.52, 0.08, 0.52), light, "cylinder")
	var barrel_length := 1.1 if wheeled else 2.1
	part(turret, Vector3(barrel_length * 0.63, 0.14, 0), Vector3(barrel_length, 0.17, 0.19), dark)
	part(turret, Vector3(barrel_length * 1.10, 0.14, 0), Vector3(0.26, 0.23, 0.25), "303d37")
	part(turret, Vector3(-0.5, 0.82, -0.42), Vector3(0.028, 1.15, 0.028), "333e34")
	part(turret, Vector3(0, 0.23, -0.53), Vector3(0.55, 0.12, 0.03), "69c8bd" if team == 0 else "d87550")
	if kind == 2:
		for side in [-1.0, 1.0]:
			part(turret, Vector3(0.45, 0.55, side * 0.57), Vector3(1.75, 0.28, 0.30), paint)
	return root
