extends Node
## ============================================================================
## EventBus · 全局事件总线
## ----------------------------------------------------------------------------
## 战斗逻辑只负责 emit，UI / 音频 / 特效只负责 connect。
## 任何模块之间不允许直接持有引用，一律经由此总线通信。
## ============================================================================

# ---------------------------------------------------------------- 单位
signal unit_spawned(unit: Node2D)
signal unit_died(victim: Node2D, killer: Node2D, headshot: bool)
signal unit_damaged(victim: Node2D, amount: float, attacker: Node2D)
signal operator_changed(unit: Node2D)

# ---------------------------------------------------------------- 战斗
signal shot_fired(shooter: Node2D, origin: Vector2, dir: Vector2, weapon_id: String)
signal explosion(pos: Vector2, scale: float, kind: String)
signal impact(pos: Vector2, normal: Vector2, kind: String)
signal kill_feed(text: String, color: Color)
signal hitmarker(headshot: bool, lethal: bool, damage: float)
signal vehicle_destroyed(pos: Vector2, name: String, by_player: bool)

# ---------------------------------------------------------------- 战局
signal phase_changed(phase: int)
signal ticket_changed(team: int, value: int, delta: int)
signal capture_state_changed(point_id: String, owner: int, progress: float, contested: bool)
signal segment_unlocked(seg: int, seg_name: String)
signal objective_changed(text: String)
signal match_ended(win_team: int, title: String, subtitle: String)
signal match_started()
signal overtime_started(phase: int, point_id: String)

# ---------------------------------------------------------------- 指挥部
signal faction_points_changed(team: int, value: float, delta: float)
signal cmd_skill_used(team: int, skill_id: String, pos: Vector2)
signal cmd_skill_ready(team: int, skill_id: String, ready: bool)
signal marked_target(team: int, kind: String, target_id: String, pos: Vector2, until: float)
signal mark_completed(team: int, kind: String, target_id: String, points: float)
signal heavy_support_used(team: int, kind: String, pos: Vector2)
signal commander_replaced(team: int, new_name: String, by_player: bool)

# ---------------------------------------------------------------- 工事
signal fort_built(team: int, kind: String, pos: Vector2)
signal fort_destroyed(team: int, kind: String)

# ---------------------------------------------------------------- 倒地与救援
signal unit_downed(unit: Node2D, killer: Node2D, bleed_out: float)
signal unit_reviving(healer: Node2D, target: Node2D, needs: float)
signal unit_revived(unit: Node2D)
signal unit_drag_changed(unit: Node2D, dragged_by: Node2D)

# ---------------------------------------------------------------- 指挥链
signal commander_elected(team: int, cmd_name: String, is_player: bool, votes: int)
signal order_issued(team: int, order_kind: int, pos: Vector2, label: String)
signal order_expired(team: int, order_kind: int)
signal squad_order_changed(squad_id: int, order_kind: int, pos: Vector2)
signal support_ready(kind: String)
signal support_used(kind: String, pos: Vector2)

# ---------------------------------------------------------------- 玩家
signal player_streak_changed(streak: int)
signal player_uav(seconds: float)
signal player_hurt(direction: float, intensity: float)
signal player_death(respawn_in: float)
signal player_respawned(unit: Node2D)

# ---------------------------------------------------------------- UI 输出
signal banner(text: String, color: Color, duration: float)
signal feed(text: String, color: Color)
signal toast(text: String, color: Color)
signal score_changed(unit: Node2D)

# ---------------------------------------------------------------- 应用级
## 应用外壳的状态（主菜单 / 设置 / 对局中 …），见 AppState
signal app_state_changed(state: int)
