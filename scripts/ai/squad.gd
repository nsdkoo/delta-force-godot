class_name Squad
extends RefCounted
## 战术小队：指挥官指令 -> 队长的最小执行单元

var id: int = 0
var team: int = 0
var members: Array = []
var leader: Node2D = null

var order_kind: int = -1          ## -1 表示无指令
var order_pos: Vector2 = Vector2.ZERO
var order_label: String = ""
var order_time: float = 0.0

func _init(p_id: int = 0, p_team: int = 0) -> void:
	id = p_id
	team = p_team

func add_member(u: Node2D) -> void:
	if u in members:
		return
	members.append(u)
	if leader == null:
		leader = u
		u.is_squad_leader = true

func remove_member(u: Node2D) -> void:
	members.erase(u)
	if leader == u:
		leader = null

func alive_members() -> Array:
	var out: Array = []
	for m in members:
		if is_instance_valid(m) and m.alive:
			out.append(m)
	return out

func size_alive() -> int:
	return alive_members().size()

func average_position() -> Vector2:
	var alive := alive_members()
	if alive.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for m in alive:
		sum += m.global_position
	return sum / float(alive.size())

func set_order(kind: int, pos: Vector2, label: String, now: float) -> void:
	order_kind = kind
	order_pos = pos
	order_label = label
	order_time = now
	EventBus.squad_order_changed.emit(id, kind, pos)

func clear_order() -> void:
	order_kind = -1
	order_label = ""
