extends Node
## ============================================================================
## TeamManager · 单位与小队注册表
## ----------------------------------------------------------------------------
## 所有单位在 _ready 时注册、死亡时注销。AI / 指挥 / UI 一律通过这里查询，
## 避免各自遍历场景树。
## ============================================================================

var units: Array = []                    ## 全部 Soldier（含阵亡待重生）
var squads: Dictionary = {}              ## squad_id(int) -> Squad
var commanders: Array = [null, null]     ## 各方指挥官单位
var player: Node2D = null
var vehicles: Array = []
var _space: PhysicsDirectSpaceState2D = null

func _ready() -> void:
	EventBus.unit_died.connect(_on_unit_died)

func reset() -> void:
	units.clear()
	squads.clear()
	vehicles.clear()
	commanders = [null, null]
	player = null

# ---------------------------------------------------------------- 注册
func register_unit(u: Node2D) -> void:
	if u not in units:
		units.append(u)
	EventBus.unit_spawned.emit(u)

func unregister_unit(u: Node2D) -> void:
	units.erase(u)

func register_vehicle(v: Node2D) -> void:
	if v not in vehicles:
		vehicles.append(v)

func unregister_vehicle(v: Node2D) -> void:
	vehicles.erase(v)

func _on_unit_died(_victim: Node2D, _killer: Node2D, _hs: bool) -> void:
	pass   # 保留：阵亡不立即移除，等待重生

# ---------------------------------------------------------------- 编制
func build_squads() -> void:
	squads.clear()
	var counter := 0
	for team in [GameConfig.Team.GTI, GameConfig.Team.HAVOC]:
		var t_units := all_units(team)
		var i := 0
		while i < t_units.size():
			var sq := Squad.new(counter, team)
			for j in range(GameConfig.SQUAD_SIZE):
				var idx := i + j
				if idx < t_units.size():
					var u: Node2D = t_units[idx]
					u.squad_id = sq.id
					sq.add_member(u)
			squads[counter] = sq
			counter += 1
			i += GameConfig.SQUAD_SIZE

func squad_of(unit: Node2D) -> Squad:
	if unit == null:
		return null
	return squads.get(unit.squad_id, null)

func squads_of_team(team: int) -> Array:
	var out: Array = []
	for id in squads:
		if squads[id].team == team:
			out.append(squads[id])
	return out

# ---------------------------------------------------------------- 查询
func all_units(team: int = -1) -> Array:
	if team < 0:
		return units.duplicate()
	var out: Array = []
	for u in units:
		if is_instance_valid(u) and u.team == team:
			out.append(u)
	return out

## 存活且"还能打"的单位。倒地的排除在外 ——
## 倒地的人不该占点、不该被索敌、也不该被算进指挥官判断兵力的口径里
func alive_units(team: int = -1) -> Array:
	var out: Array = []
	for u in units:
		if not is_instance_valid(u) or not u.alive or u.downed:
			continue
		if team < 0 or u.team == team:
			out.append(u)
	return out

## 战场上等待救援的倒地单位（救援 AI 与 HUD 用）
func downed_units(team: int = -1) -> Array:
	var out: Array = []
	for u in units:
		if not is_instance_valid(u) or not u.alive or not u.downed:
			continue
		if team < 0 or u.team == team:
			out.append(u)
	return out

func nearest_downed(from: Vector2, team: int, max_range: float) -> Soldier:
	var best: Soldier = null
	var best_d := max_range * max_range
	for u in downed_units(team):
		var d := from.distance_squared_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

func alive_count(team: int) -> int:
	return alive_units(team).size()

func player_squad() -> Squad:
	if player == null:
		return null
	return squad_of(player)

func nearest_enemy(from: Vector2, team: int, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range * max_range
	for u in alive_units():
		if u.team == team:
			continue
		var d := from.distance_squared_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	for v in vehicles:
		if not is_instance_valid(v) or not v.alive or v.team == team:
			continue
		var d := from.distance_squared_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best

func nearest_enemy_vehicle(from: Vector2, team: int, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range * max_range
	for v in vehicles:
		if not is_instance_valid(v) or not v.alive or v.team == team:
			continue
		var d := from.distance_squared_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best

## 找最近的可搭乘载具（同队、存活、且没有别的驾驶员）
func nearest_friendly_vehicle(from: Vector2, team: int, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range * max_range
	for v in vehicles:
		if not is_instance_valid(v) or not v.alive or v.team != team or v.driver != null:
			continue
		var d := from.distance_squared_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best

## 战场上双方载具总数（计分板用）
func alive_vehicle_count(team: int) -> int:
	var n := 0
	for v in vehicles:
		if is_instance_valid(v) and v.alive and (team < 0 or v.team == team):
			n += 1
	return n

func units_in_radius(pos: Vector2, radius: float, team: int = -1) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for u in alive_units(team):
		if pos.distance_squared_to(u.global_position) <= r2:
			out.append(u)
	return out

func count_in_radius(pos: Vector2, radius: float, team: int) -> int:
	return units_in_radius(pos, radius, team).size()

# ---------------------------------------------------------------- 视线
func _get_space() -> PhysicsDirectSpaceState2D:
	var w := get_viewport().world_2d if get_viewport() else null
	if w == null:
		return null
	return w.direct_space_state

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space := _get_space()
	if space == null:
		return true
	var params := PhysicsRayQueryParameters2D.create(from, to)
	params.collision_mask = GameConfig.Layer.WORLD
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	return hit.is_empty()

## 找最近且可见的敌人（AI 主用）
func nearest_visible_enemy(from: Vector2, team: int, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range * max_range
	for u in alive_units():
		if u.team == team:
			continue
		var d := from.distance_squared_to(u.global_position)
		if d < best_d and has_line_of_sight(from, u.global_position):
			best_d = d
			best = u
	return best
