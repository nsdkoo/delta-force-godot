extends Node
## ============================================================================
## AudioManager · 程序化音效
## ----------------------------------------------------------------------------
## 全部音效在启动时用数学合成（无外部音频资源），零依赖且体积为零。
## 空间音效走 AudioStreamPlayer2D 池，UI 音效走独立 AudioStreamPlayer。
## ============================================================================

const RATE := 22050
const POOL_SIZE := 10

var streams: Dictionary = {}
var muted := false
var _pool: Array[AudioStreamPlayer2D] = []
var _pool_idx := 0
var _ui: AudioStreamPlayer

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
	# 枪声：按武器差异化的噪声包络
	streams["shot_ar"] = _make_burst(0.11, 0.020, 5200.0, 260.0, 0.26, 0.95)
	streams["shot_lmg"] = _make_burst(0.15, 0.032, 3600.0, 190.0, 0.32, 1.0)
	streams["shot_smg"] = _make_burst(0.08, 0.016, 5600.0, 310.0, 0.22, 0.85)
	streams["shot_sniper"] = _make_burst(0.34, 0.075, 6400.0, 140.0, 0.45, 1.0)
	streams["shot_pistol"] = _make_burst(0.07, 0.014, 5800.0, 340.0, 0.20, 0.75)
	streams["shot_cannon"] = _make_burst(0.55, 0.130, 2200.0, 80.0, 0.55, 1.0)
	streams["shot_mg_veh"] = _make_burst(0.10, 0.022, 4200.0, 210.0, 0.30, 0.9)
	# 爆炸
	streams["boom_small"] = _make_burst(0.50, 0.100, 1600.0, 90.0, 0.45, 1.0)
	streams["boom_big"] = _make_burst(1.10, 0.260, 1000.0, 52.0, 0.60, 1.0)
	# 命中 / 反馈
	streams["hit_flesh"] = _make_burst(0.07, 0.014, 2400.0, 420.0, 0.35, 0.75)
	streams["hit_head"] = _make_tone(0.09, 1700.0, 900.0, 0, 0.35)
	streams["hit_metal"] = _make_burst(0.09, 0.020, 7000.0, 900.0, 0.30, 0.6)
	streams["hurt"] = _make_burst(0.30, 0.060, 900.0, 120.0, 0.40, 0.8)
	streams["reload_a"] = _make_tone(0.06, 430.0, 200.0, 0, 0.28)
	streams["reload_b"] = _make_tone(0.07, 320.0, 170.0, 0, 0.30)
	streams["step"] = _make_burst(0.09, 0.016, 1200.0, 180.0, 0.20, 0.45)
	streams["kill"] = _make_tone(0.14, 880.0, 1700.0, 2, 0.34)
	streams["ui_up"] = _make_tone(0.08, 780.0, 1250.0, 0, 0.28)
	streams["ui_down"] = _make_tone(0.08, 620.0, 380.0, 0, 0.26)
	streams["alarm"] = _make_tone(0.42, 700.0, 500.0, 0, 0.32)
	streams["announce"] = _make_tone(0.30, 520.0, 880.0, 1, 0.24)

# ---------------------------------------------------------------- 播放
func play_2d(kind: String, pos: Vector2, volume_db: float = 0.0) -> void:
	if muted:
		return
	var st: AudioStream = streams.get(kind, null)
	if st == null:
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = st
	p.global_position = pos
	p.volume_db = volume_db
	p.play()

func play_ui(kind: String, volume_db: float = -4.0) -> void:
	if muted or _ui == null:
		return
	var st: AudioStream = streams.get(kind, null)
	if st == null:
		return
	_ui.stream = st
	_ui.volume_db = volume_db
	_ui.play()

func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted

## 距离衰减后的音量（用于世界音效）
func volume_for(pos: Vector2, listener: Vector2, full_range: float = 350.0, max_range: float = 2200.0) -> float:
	var d := pos.distance_to(listener)
	if d <= full_range:
		return 0.0
	if d >= max_range:
		return -80.0
	var k := (d - full_range) / (max_range - full_range)
	return lerpf(0.0, -42.0, k)
