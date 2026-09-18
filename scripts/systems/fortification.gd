class_name Fortification
extends StaticBody2D
## ============================================================================
## Fortification · 工事
## ----------------------------------------------------------------------------
## 小队长可建的四类阵地设施：岸防炮（反装甲）/ 防空炮（反空中）/
## 机枪碉堡（压步兵）/ 火神炮（高射速近防）。双方同时最多存在 1 个。
##
## 全部程序化绘制，不依赖任何贴图 —— 工事是"打出来的东西"，
## 每次架设的位置与朝向都不同，用固定素材反而难对齐，而且现在只有四条，
## 画形状比找素材快。
##
## 不带导航碰撞（collision_mask = 0）：工事是阵地而不是路障，
## 给它实体碰撞会让 AI 在自己人身后排成一列卡死。
## 但它在阵营碰撞层上，所以敌方子弹的射线会命中它。
## ============================================================================

## 子弹伤害系数。载具默认吃 15% 的枪械伤害（装甲），工事吃满
var bullet_damage_scale := 1.0

var team: int = GameConfig.Team.GTI
var kind: String = "bunker"
var alive: bool = true
var hp: float = 800.0
var max_hp: float = 800.0
var aim_angle: float = 0.0
var _cd: float = 0.0
var _data: Dictionary = {}
var _flash: float = 0.0
var _target: Node2D = null
var _spr: Sprite2D

## 工事外观：直接用素材包里的塔与炮位（Tower Defense 包，CC0）。
## 比程序化画六边形强得多 —— 玩家一眼能分辨"这是碉堡还是防空炮"
const FORT_ART := {
	"coastal": "fort_gun",
	"aa": "fort_turret",
	"bunker": "fort_bunker",
	"vulcan": "fort_block",
}

func setup(p_team: int, p_kind: String) -> void:
	team = p_team
	kind = p_kind

func _ready() -> void:
	_data = GameConfig.FORTIFICATIONS.get(kind, GameConfig.FORTIFICATIONS["bunker"])
	max_hp = float(_data["hp"])
	hp = max_hp
	# 在阵营层上，敌方子弹的 mask 含这一层，所以能被扫到；自己人打不到
	collision_layer = GameConfig.team_layer(team)
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = 26.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	_spr = Sprite2D.new()
	_spr.texture = AssetDB.ktile(FORT_ART.get(kind, "fort_bunker"))
	_spr.scale = Vector2.ONE * (56.0 / maxf(1.0, AssetDB.logical_width(_spr.texture)))
	# 守方镜像一下，让两边的塔朝向各自的面
	_spr.flip_h = team == GameConfig.Team.HAVOC
	add_child(_spr)
	z_index = 1

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
	if _cd > 0.0:
		_cd -= delta
	if _cd <= 0.0:
		_fire()
	queue_redraw()

func _fire() -> void:
	_target = _acquire()
	if _target == null:
		return
	_cd = float(_data["rate"])
	aim_angle = (_target.global_position - global_position).angle()
	var dmg := float(_data["damage"])
	EventBus.shot_fired.emit(self, global_position + Vector2.from_angle(aim_angle) * 30.0,
		Vector2.from_angle(aim_angle), "fort_" + kind)
	AudioManager.play_2d("shot_mg_veh" if kind == "bunker" or kind == "vulcan" else "shot_cannon",
		global_position, AudioManager.volume_for(global_position, _listener(), 400.0, 2600.0))
	var splash := float(_data.get("splash", 0.0))
	if splash <= 0.0:
		_target.take_damage(dmg, null)
		return
	# 有溅射的（岸防炮 / 防空炮）：命中点周围一起受伤
	var center: Vector2 = _target.global_position
	EventBus.explosion.emit(center, 1.5, "boom")
	for u in TeamManager.alive_units():
		if u.team == team:
			continue
		var d := center.distance_to(u.global_position)
		if d < splash:
			u.take_damage(dmg * (1.0 - d / splash), null)
	for v in TeamManager.vehicles:
		if not is_instance_valid(v) or not v.alive or v.team == team:
			continue
		var d2 := center.distance_to(v.global_position)
		if d2 < splash + 30.0:
			v.take_damage(dmg * 0.5 * (1.0 - d2 / (splash + 30.0)), null)

## 索敌：防空炮只打空中，其余只打地面
func _acquire() -> Node2D:
	var rng := float(_data["range"])
	var want_air: bool = _data.get("anti", "ground") == "air"
	var best: Node2D = null
	var best_d := rng * rng
	if not want_air:
		for u in TeamManager.alive_units():
			if u.team == team:
				continue
			var d := global_position.distance_squared_to(u.global_position)
			if d < best_d:
				best_d = d
				best = u
	for v in TeamManager.vehicles:
		if not is_instance_valid(v) or not v.alive or v.team == team:
			continue
		if bool(v.is_air) != want_air:
			continue
		var d2 := global_position.distance_squared_to(v.global_position)
		if d2 < best_d:
			best_d = d2
			best = v
	return best

func _listener() -> Vector2:
	if TeamManager.player != null and is_instance_valid(TeamManager.player):
		return TeamManager.player.global_position
	return global_position

func take_damage(amount: float, _attacker: Soldier) -> void:
	if not alive:
		return
	hp -= amount
	_flash = 1.0
	if hp <= 0.0:
		_destroy()

func _destroy() -> void:
	alive = false
	visible = false
	collision_layer = 0
	EventBus.explosion.emit(global_position, 2.0, "boom")
	EventBus.feed.emit("%s 被摧毁" % _data["name"], Palette.MARK_WARN)
	CommandOps.on_fort_destroyed(team, kind)
	queue_free()

# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var col := GameConfig.team_color(team)
	var dark := Color(col.r * 0.55, col.g * 0.55, col.b * 0.55)
	var base := Color("#8b7f63") if _data.get("anti", "ground") == "ground" else Color("#6f7d8c")
	if _flash > 0.0:
		base = base.lerp(Color(1, 0.5, 0.4), _flash)

	# 底座：沙袋掩体的六边形
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.4
		pts.append(Vector2(cos(a), sin(a) * 0.8) * 30.0)
	draw_colored_polygon(pts, Palette.OUTLINE)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.87)
	draw_colored_polygon(inner, base)
	draw_colored_polygon(PackedVector2Array([inner[0] * 0.5, inner[1] * 0.5, inner[2] * 0.5,
		inner[3] * 0.5]), base.lightened(0.16))

	# 阵营识别环
	draw_arc(Vector2.ZERO, 32.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.9), 3.0)

	# 阵地底座：素材只画了塔身，底下这块"打进地里的底座"仍然自己画 ——
	# 它负责区分阵营，也让塔不像贴纸一样浮在地上
	draw_circle(Vector2.ZERO, 30.0, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.9))
	draw_arc(Vector2.ZERO, 30.0, 0, TAU, 26, Palette.OUTLINE, 3.0)

	# 血量条
	var k := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-24, -46, 48, 6), Palette.OUTLINE, true)
	draw_rect(Rect2(-22, -44, 44 * k, 2), Color("#57e08a") if k > 0.5 else
		(Color("#ffd24a") if k > 0.25 else Color("#ff5b4a")), true)
