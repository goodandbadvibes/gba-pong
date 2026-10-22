extends Node
## Procedural GBA-style background music. Like the GBA's sound chip it uses square-wave pulse
## channels, a 4-bit wave channel (bass) and an LFSR noise channel, mixed down to 8-bit at 16384 Hz.
## A two-bar loop is built for an intensity (layers and tempo grow with it), rendered a few notes per
## frame so nothing stutters, then swapped in.

const Tuning := preload("res://scripts/tuning.gd")

const RATE := 16384
const STEPS := 32
## Samples rendered per frame while a new loop is built (about 1-2 ms on a desktop, more on phones).
const SAMPLES_PER_FRAME := 1000
const MAX_BPM := 200.0
const LAYERS := ["pulse", "bass", "hats", "arp", "lead"]
## The intensity at which each layer joins when it is set to AUTO.
const LAYER_FROM := {"pulse": 0, "bass": 1, "hats": 2, "arp": 3, "lead": 4}

# A minor: bar 1 sits on A, bar 2 on F.
const ROOTS := [110.0, 87.307]
const CHORDS := [[0, 3, 7, 12], [0, 4, 7, 12]]
const BASS_STEPS := [0, 3, 6, 8, 11, 14]
## Lead line over both bars: [step, MIDI note, length in steps].
const LEAD := [[0, 76, 4], [6, 74, 2], [8, 72, 4], [14, 69, 2], [16, 72, 4], [22, 69, 2], [24, 65, 6]]

var tuning: Tuning
var player: AudioStreamPlayer
var current_key: String = ""
var _job: Dictionary = {}


func _ready() -> void:
	_ensure_player()


func _ensure_player() -> void:
	if player == null:
		player = AudioStreamPlayer.new()
		add_child(player)


func _process(_delta: float) -> void:
	if tuning == null:
		return
	_ensure_player()
	var volume: float = tuning.get_value("music_volume") / 100.0
	player.volume_db = linear_to_db(volume * 0.8) if volume > 0.0 else -80.0
	if _job.is_empty():
		return
	if _render_some(SAMPLES_PER_FRAME):
		_finish_job()


## Asks for the loop that fits this intensity; builds it in the background if it changed.
func play_for(intensity: int) -> void:
	var level: int = effective_intensity(intensity)
	var key: String = "%d|%d|%s" % [level, roundi(bpm_for(level)), ",".join(active_layers(level))]
	if key == current_key or (not _job.is_empty() and _job.key == key):
		return
	var events: Array[Dictionary] = build_events(level)
	var size: int = loop_samples(bpm_for(level))
	var buf := PackedFloat32Array()
	buf.resize(size)
	_job = {"key": key, "events": events, "buf": buf, "next": 0, "k": 0, "phase": 0.0, "lfsr": 0x4000, "noise": 1.0}


func effective_intensity(intensity: int) -> int:
	var forced: int = int(tuning.get_value("music_intensity"))
	return forced if forced > 0 else maxi(0, intensity)


func bpm_for(level: int) -> float:
	return minf(MAX_BPM, tuning.get_value("music_bpm") + tuning.get_value("music_bpm_lv") * maxi(0, level - 1))


func active_layers(level: int) -> Array[String]:
	var out: Array[String] = []
	for layer in LAYERS:
		var mode: int = int(tuning.get_value("layer_" + layer))
		if mode == 2 or (mode == 1 and level >= LAYER_FROM[layer]):
			out.append(layer)
	return out


static func loop_samples(bpm: float) -> int:
	return int(RATE * 60.0 / bpm / 4.0 * STEPS)


## All notes of the two-bar loop as events: start sample, length, wave kind, pitch sweep, volume, decay.
func build_events(level: int) -> Array[Dictionary]:
	var bpm: float = bpm_for(level)
	var spb: float = RATE * 60.0 / bpm / 4.0
	var layers := active_layers(level)
	var events: Array[Dictionary] = []
	for step in STEPS:
		var bar: int = step / 16
		var s: int = step % 16
		var start: int = int(step * spb)
		var root: float = ROOTS[bar]
		if layers.has("pulse") and s % 4 == 0:
			events.append(_ev(start, 0.14, "square", 90.0, 45.0, 0.45, 0.06, 0.5))
		if layers.has("bass") and BASS_STEPS.has(s):
			events.append(_ev(start, spb * 1.8 / RATE, "wave", root, root, 0.38, 0.6))
		if layers.has("hats") and (s % 4 == 2 or (level >= 5 and s % 2 == 0)):
			events.append(_ev(start, 0.03, "noise", 9000.0, 9000.0, 0.16 if s % 4 == 2 else 0.09, 0.012))
		if layers.has("arp"):
			var tone: float = root * 4.0 * pow(2.0, CHORDS[bar][s % 4] / 12.0)
			events.append(_ev(start, spb * 0.9 / RATE, "square", tone, tone, 0.11, 0.07, 0.125))
	if layers.has("lead"):
		for note in LEAD:
			var freq: float = 440.0 * pow(2.0, (note[1] - 69) / 12.0)
			events.append(_ev(int(note[0] * spb), note[2] * spb * 0.95 / RATE, "square", freq, freq, 0.13, 0.5, 0.25))
	return events


func _ev(start: int, seconds: float, kind: String, f0: float, f1: float, amp: float, decay: float, duty: float = 0.5) -> Dictionary:
	return {"start": start, "len": int(seconds * RATE), "kind": kind, "f0": f0, "f1": f1, "amp": amp, "decay": decay, "duty": duty}


## Renders up to budget samples of the queued notes, resuming mid-note across frames.
## Returns true once every note is in the buffer.
func _render_some(budget: int) -> bool:
	var buf: PackedFloat32Array = _job.buf
	var size: int = buf.size()
	while budget > 0:
		if _job.next >= _job.events.size():
			_job.buf = buf
			return true
		var e: Dictionary = _job.events[_job.next]
		var length: int = e.len
		var k: int = _job.k
		var phase: float = _job.phase
		var lfsr: int = _job.lfsr
		var noise: float = _job.noise
		var stop: int = mini(length, k + budget)
		budget -= stop - k
		while k < stop:
			var t: float = float(k) / RATE
			var prev: float = phase
			phase += lerpf(e.f0, e.f1, float(k) / length) / RATE
			var frac: float = phase - floorf(phase)
			var v: float
			match e.kind:
				"square":
					v = 1.0 if frac < e.duty else -1.0
				"wave":
					# Triangle on a 4-bit wave table, like the GBA wave channel.
					v = roundf((1.0 - 4.0 * absf(frac - 0.5)) * 7.5) / 7.5
				_:
					if floorf(phase) != floorf(prev):
						var bit: int = (lfsr ^ (lfsr >> 1)) & 1
						lfsr = (lfsr >> 1) | (bit << 14)
						noise = 1.0 if lfsr & 1 else -1.0
					v = noise
			# Quick release over the last 5% so notes end without clicks; wrap for a seamless loop.
			var release: float = clampf((length - k) / (length * 0.05 + 1.0), 0.0, 1.0)
			buf[(e.start + k) % size] += v * e.amp * exp(-t / e.decay) * release
			k += 1
		if k >= length:
			_job.next += 1
			k = 0
			phase = 0.0
			lfsr = 0x4000
			noise = 1.0
		_job.k = k
		_job.phase = phase
		_job.lfsr = lfsr
		_job.noise = noise
	_job.buf = buf
	return _job.next >= _job.events.size()


func _finish_job() -> void:
	var buf: PackedFloat32Array = _job.buf
	var data := PackedByteArray()
	data.resize(buf.size())
	for i in buf.size():
		data[i] = int(clampf(buf[i], -1.0, 1.0) * 110.0) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buf.size()
	current_key = _job.key
	_job = {}
	_ensure_player()
	player.stream = wav
	if player.is_inside_tree():
		player.play()


## Builds a loop immediately (tests and tools). Returns the stream.
func render_now(intensity: int) -> AudioStreamWAV:
	_ensure_player()
	play_for(intensity)
	if _job.is_empty():
		return player.stream
	while not _render_some(1 << 20):
		pass
	_finish_job()
	return player.stream
