extends Node
## Procedural GBA-style background music. Like the GBA's sound chip it uses square-wave pulse
## channels, a 4-bit wave channel (bass) and an LFSR noise channel, mixed down to 8-bit at 16384 Hz.
## Three tracks: "game" (layers join as levels rise, tempo rises per level and per game played in
## the level), "map" (calm, D minor) and "shop" (bouncy, C major). A two-bar loop is rendered a slice
## per frame so nothing stutters, then swapped in.

const Tuning := preload("res://scripts/tuning.gd")

const RATE := 16384
const STEPS := 32
## Samples rendered per frame while a new loop is built (about 1-2 ms on a desktop, more on phones).
const SAMPLES_PER_FRAME := 1000
const MAX_BPM := 200.0
const LAYERS := ["pulse", "bass", "hats", "arp", "lead"]
## The intensity at which each game-track layer joins when it is set to AUTO.
const LAYER_FROM := {"pulse": 0, "bass": 1, "hats": 2, "arp": 3, "lead": 4}

## Per track: bar roots (Hz), chord tones (semitones), bass steps and length, how often the pulse,
## hats and arpeggio play, whether the bass bounces an octave, the lead line ([step, MIDI note,
## steps]) and, for map and shop, a fixed set of layers.
const TRACKS := {
	"game": {"roots": [110.0, 87.307], "chords": [[0, 3, 7, 12], [0, 4, 7, 12]],
		"bass_steps": [0, 3, 6, 8, 11, 14], "bass_len": 1.8, "bass_bounce": false,
		"pulse_every": 4, "hats_every": 4, "arp_every": 1,
		"lead": [[0, 76, 4], [6, 74, 2], [8, 72, 4], [14, 69, 2], [16, 72, 4], [22, 69, 2], [24, 65, 6]]},
	"map": {"roots": [73.416, 58.27], "chords": [[0, 3, 7, 12], [0, 4, 7, 12]],
		"bass_steps": [0, 8], "bass_len": 7.5, "bass_bounce": false,
		"pulse_every": 16, "hats_every": 0, "arp_every": 2,
		"lead": [[0, 74, 6], [8, 72, 4], [12, 69, 4], [16, 70, 6], [24, 69, 8]],
		"layers": ["pulse", "bass", "arp", "lead"]},
	"shop": {"roots": [65.406, 97.999], "chords": [[0, 4, 7, 12], [0, 4, 7, 10]],
		"bass_steps": [0, 4, 8, 12], "bass_len": 1.6, "bass_bounce": true,
		"pulse_every": 8, "hats_every": 4, "arp_every": 1,
		"lead": [[0, 72, 2], [2, 76, 2], [4, 79, 2], [6, 76, 2], [8, 77, 4], [12, 76, 4],
			[16, 74, 2], [18, 77, 2], [20, 79, 2], [22, 77, 2], [24, 76, 6]],
		"layers": ["pulse", "bass", "hats", "arp", "lead"]},
}

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


## Asks for the loop for a track, intensity (game track) and games played in the level;
## builds it in the background if it changed.
func play_for(intensity: int, track: String = "game", games: int = 0) -> void:
	var level: int = effective_intensity(intensity)
	var bpm: float = track_bpm(track, level, games)
	var layers: Array = layers_for(track, level)
	var key: String = "%s|%d|%d|%s" % [track, level, roundi(bpm), ",".join(layers)]
	if key == current_key or (not _job.is_empty() and _job.key == key):
		return
	var buf := PackedFloat32Array()
	buf.resize(loop_samples(bpm))
	_job = {"key": key, "events": build_events(level, track, bpm), "buf": buf, "next": 0, "k": 0,
		"phase": 0.0, "lfsr": 0x4000, "noise": 1.0}


func effective_intensity(intensity: int) -> int:
	var forced: int = int(tuning.get_value("music_intensity"))
	return forced if forced > 0 else maxi(0, intensity)


## Game-track tempo for a level: base plus per level, then plus per game already played in it.
func bpm_for(level: int, games: int = 0) -> float:
	return minf(MAX_BPM, tuning.get_value("music_bpm") + tuning.get_value("music_bpm_lv") * maxi(0, level - 1)
		+ tuning.get_value("music_bpm_game") * maxi(0, games))


func track_bpm(track: String, level: int, games: int = 0) -> float:
	match track:
		"map":
			return tuning.get_value("map_bpm")
		"shop":
			return tuning.get_value("shop_bpm")
	return bpm_for(level, games)


func layers_for(track: String, level: int) -> Array:
	return TRACKS[track].layers if TRACKS[track].has("layers") else active_layers(level)


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
func build_events(level: int, track: String = "game", bpm: float = -1.0) -> Array[Dictionary]:
	var t: Dictionary = TRACKS[track]
	if bpm <= 0.0:
		bpm = track_bpm(track, level)
	var spb: float = RATE * 60.0 / bpm / 4.0
	var layers: Array = layers_for(track, level)
	var events: Array[Dictionary] = []
	for step in STEPS:
		var bar: int = step / 16
		var s: int = step % 16
		var start: int = int(step * spb)
		var root: float = t.roots[bar]
		if layers.has("pulse") and s % t.pulse_every == 0:
			events.append(_ev(start, 0.14, "square", 90.0, 45.0, 0.45, 0.06, 0.5))
		if layers.has("bass") and t.bass_steps.has(s):
			var bass: float = root * (2.0 if t.bass_bounce and t.bass_steps.find(s) % 2 == 1 else 1.0)
			events.append(_ev(start, spb * t.bass_len / RATE, "wave", bass, bass, 0.38, 0.6 if t.bass_len < 4.0 else 1.6))
		if layers.has("hats") and t.hats_every > 0 and (s % t.hats_every == 2 or (track == "game" and level >= 5 and s % 2 == 0)):
			events.append(_ev(start, 0.03, "noise", 9000.0, 9000.0, 0.16 if s % 4 == 2 else 0.09, 0.012))
		if layers.has("arp") and s % t.arp_every == 0:
			var tone: float = root * 4.0 * pow(2.0, t.chords[bar][(s / t.arp_every) % 4] / 12.0)
			events.append(_ev(start, spb * t.arp_every * 0.9 / RATE, "square", tone, tone, 0.11, 0.07 * t.arp_every, 0.125))
	if layers.has("lead"):
		for note in t.lead:
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
func render_now(intensity: int, track: String = "game", games: int = 0) -> AudioStreamWAV:
	_ensure_player()
	play_for(intensity, track, games)
	if _job.is_empty():
		return player.stream
	while not _render_some(1 << 20):
		pass
	_finish_job()
	return player.stream
