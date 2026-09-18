extends Node
## ============================================================================
## AudioManager · 程序化音效
## ----------------------------------------------------------------------------
## 全部音效在启动时用数学合成（无外部音频资源），零依赖且体积为零。
## 空间音效走 AudioStreamPlayer2D 池，UI 音效走独立 AudioStreamPlayer。
## ============================================================================

const RATE := 22050
const POOL_SIZE := 24

var streams: Dictionary = {}
var muted := false
var _pool: Array[AudioStreamPlayer2D] = []
var _pool_idx := 0
var _ui: AudioStreamPlayer
## 同类音效最短间隔（秒），防止 40 人齐射把合成方波糊成「噔噔噔」
var _kind_cd: Dictionary = {}
const KIND_MIN_GAP := {
	"shot_ar": 0.045, "shot_lmg": 0.055, "shot_smg": 0.038, "shot_sniper": 0.12,
	"shot_pistol": 0.05, "shot_cannon": 0.18, "shot_mg_veh": 0.06,
	"hit_flesh": 0.04, "hit_head": 0.08, "hit_metal": 0.05,
	"reload_a": 0.12, "reload_b": 0.12, "hurt": 0.15, "kill": 0.08,
	"alarm": 0.8, "ui_up": 0.1, "ui_down": 0.1, "step": 0.08,
}

func _ready() -> void:
	_synth_all()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 2600.0
		p.attenuation = 0.9
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	_ui.bus = "Master"
	add_child(_ui)

# ---------------------------------------------------------------- 合成
## 噪声爆发 + 一阶低通 + 可选音调分量
func _make_burst(dur: float, decay: float, cutoff: float,
		tone_freq: float = 0.0, tone_mix: float = 0.0, gain: float = 1.0) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	var alpha := clampf(cutoff / float(RATE), 0.01, 0.995)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260529
	for i in count:
		var t := float(i) / RATE
		var env: float = exp(-t / maxf(decay, 0.001))
		var n := rng.randf() * 2.0 - 1.0
		lp += (n - lp) * alpha
		var s := lp * env
		if tone_mix > 0.0:
			s += sin(TAU * tone_freq * t) * env * tone_mix
		var v := int(clampf(s * gain, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

## 纯音（UI / 提示）
func _make_tone(dur: float, f0: float, f1: float, kind: int = 0, gain: float = 0.5) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var k := float(i) / float(count)
		var f: float = lerpf(f0, f1, k)
		var env := sin(PI * clampf(k * 1.15, 0.0, 1.0))
		var ph := TAU * f * t
		var s := 0.0
		match kind:
			0: s = 1.0 if sin(ph) >= 0.0 else -1.0        # 方波
			1: s = sin(ph)                                 # 正弦
			_: s = fmod(ph / PI, 2.0) - 1.0                # 锯齿
		var v := int(clampf(s * env * gain, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

func _synth_all() -> void:
	# 枪声刻意压低增益 —— 40 人齐射时仍可辨，但不刺耳
	streams["shot_ar"] = _make_burst(0.07, 0.016, 4200.0, 160.0, 0.08, 0.38)
	streams["shot_lmg"] = _make_burst(0.09, 0.022, 3000.0, 120.0, 0.09, 0.42)
	streams["shot_smg"] = _make_burst(0.05, 0.012, 4600.0, 200.0, 0.06, 0.32)
	streams["shot_sniper"] = _make_burst(0.22, 0.055, 5000.0, 100.0, 0.14, 0.48)
	streams["shot_pistol"] = _make_burst(0.05, 0.010, 4800.0, 240.0, 0.06, 0.30)
	streams["shot_cannon"] = _make_burst(0.38, 0.095, 1800.0, 65.0, 0.22, 0.55)
	streams["shot_mg_veh"] = _make_burst(0.06, 0.014, 3400.0, 140.0, 0.08, 0.36)
	streams["boom_small"] = _make_burst(0.36, 0.080, 1400.0, 70.0, 0.22, 0.55)
	streams["boom_big"] = _make_burst(0.80, 0.180, 850.0, 45.0, 0.28, 0.62)
	streams["hit_flesh"] = _make_burst(0.04, 0.008, 2000.0, 0.0, 0.0, 0.28)
	streams["hit_head"] = _make_tone(0.05, 1200.0, 650.0, 1, 0.12)
	streams["hit_metal"] = _make_burst(0.05, 0.012, 5500.0, 600.0, 0.08, 0.28)
	streams["hurt"] = _make_burst(0.18, 0.040, 750.0, 90.0, 0.14, 0.35)
	streams["reload_a"] = _make_tone(0.04, 360.0, 170.0, 1, 0.10)
	streams["reload_b"] = _make_tone(0.05, 260.0, 140.0, 1, 0.12)
	streams["step"] = _make_burst(0.06, 0.010, 900.0, 0.0, 0.0, 0.18)
	streams["kill"] = _make_tone(0.08, 680.0, 1100.0, 1, 0.14)
	streams["ui_up"] = _make_tone(0.05, 640.0, 920.0, 1, 0.12)
	streams["ui_down"] = _make_tone(0.05, 480.0, 300.0, 1, 0.10)
	streams["alarm"] = _make_tone(0.22, 520.0, 400.0, 1, 0.12)
	streams["announce"] = _make_tone(0.20, 450.0, 680.0, 1, 0.12)

# ---------------------------------------------------------------- 播放
func play_2d(kind: String, pos: Vector2, volume_db: float = 0.0) -> void:
	if muted:
		return
	var st: AudioStream = streams.get(kind, null)
	if st == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = float(KIND_MIN_GAP.get(kind, 0.03))
	# 枪声再拉长间隔，避免前线齐射糊成一片
	if kind.begins_with("shot_"):
		gap = maxf(gap, 0.07)
	var last: float = float(_kind_cd.get(kind, -999.0))
	if now - last < gap:
		return
	_kind_cd[kind] = now
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = st
	p.global_position = pos
	var sfx_scale := clampf(UserSettings.sfx_volume, 0.0, 1.0) * 0.55
	var gun_extra := -10.0 if kind.begins_with("shot_") else -4.0
	p.volume_db = volume_db + gun_extra + linear_to_db(maxf(sfx_scale, 0.05))
	p.play()

func play_ui(kind: String, volume_db: float = -4.0) -> void:
	if muted or _ui == null:
		return
	var st: AudioStream = streams.get(kind, null)
	if st == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = float(KIND_MIN_GAP.get(kind, 0.05))
	var last: float = float(_kind_cd.get("ui:" + kind, -999.0))
	if now - last < gap:
		return
	_kind_cd["ui:" + kind] = now
	_ui.stream = st
	var sfx_scale := clampf(UserSettings.sfx_volume, 0.0, 1.0) * 0.6
	_ui.volume_db = volume_db - 4.0 + linear_to_db(maxf(sfx_scale, 0.05))
	_ui.play()

func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted

## 停掉全部正在播放的音效。
## 退出前不清的话，正在播放的 AudioStreamPlaybackWAV 会活到进程结束，
## Godot 在退出时会把它们报成 ObjectDB 泄漏。
func stop_all() -> void:
	for p in _pool:
		if p != null:
			p.stop()
	if _ui != null:
		_ui.stop()

## 距离衰减后的音量（用于世界音效）
func volume_for(pos: Vector2, listener: Vector2, full_range: float = 350.0, max_range: float = 2200.0) -> float:
	var d := pos.distance_to(listener)
	if d <= full_range:
		return 0.0
	if d >= max_range:
		return -80.0
	var k := (d - full_range) / (max_range - full_range)
	return lerpf(0.0, -42.0, k)
