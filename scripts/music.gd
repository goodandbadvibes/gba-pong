extends Node
## Procedural GBA-style background music. Like the GBA's sound chip it uses square-wave pulse
## channels, a 4-bit wave channel (bass) and an LFSR noise channel, mixed down to 8-bit at 16384 Hz.
## Three tracks: "game" (layers join as levels rise, tempo rises per level and per game played in
## the level), "map" (calm, D minor) and "shop" (bouncy, C major). A two-bar loop is rendered a slice
## per frame so nothing stutters. Finished loops are cached, and the game asks for the loops it will
## need next (prefetch), so changing screens normally switches music instantly. When a loop is not
## ready yet, the old music stops at once and the new loop is built at high priority.

const Tuning := preload("res://scripts/tuning.gd")

const RATE := 16384
const STEPS := 32
## Samples rendered per frame while building in the background (about 1-2 ms on a desktop).
const SAMPLES_PER_FRAME := 1000
## Background samples per frame on menu screens, where nothing time-critical runs.
const MENU_SAMPLES_PER_FRAME := 4000
## Samples per frame when the screen is waiting in silence for its loop (done in well under a second).
const URGENT_SAMPLES_PER_FRAME := 8000
## Float-to-8-bit samples converted per frame once a loop is rendered.
const CONVERT_PER_FRAME := 12000
const CACHE_MAX := 16
const PREFETCH_MAX := 6
const MAX_BPM := 200.0
const LAYERS := ["pulse", "bass", "hats", "arp", "lead"]
## The intensity at which each game-track layer joins when it is set to AUTO.
const LAYER_FROM := {"pulse": 0, "bass": 1, "hats": 2, "arp": 3, "lead": 4}

## Tracks and jingles are loaded from content/music.cfg (see the notes at the top of that file).
const Content := preload("res://scripts/content.gd")
static var _data: Dictionary = Content.table("music")
## Per track: bar roots, chords, bass steps and length, pulse/hats/arp spacing, lead line, layers.
static var TRACKS: Dictionary = _pick(false)
## Per jingle ("win", "lose"): [frequency Hz, start s, length s, wave, pulse width, volume] rows.
static var JINGLES: Dictionary = _pick(true)


static func _pick(jingles: bool) -> Dictionary:
	var out: Dictionary = {}
	for section in _data:
		if section.begins_with("jingle_") == jingles:
			out[section.trim_prefix("jingle_") if jingles else section] = _data[section].notes if jingles else _data[section]
	return out


var tuning: Tuning
var player: AudioStreamPlayer
var jingle_player: AudioStreamPlayer
var _jingles: Dictionary = {}
var current_key: String = ""
## The loop the current screen wants; empty once it plays.
var wanted_key: String = ""
## Background build speed: the game raises it on menu screens and keeps it low during play.
var background_budget: int = SAMPLES_PER_FRAME
var _job: Dictionary = {}
var _cache: Dictionary = {}
var _cache_order: Array[String] = []
var _queue: Array[Dictionary] = []


func _ready() -> void:
	_ensure_player()


func _ensure_player() -> void:
	if player == null:
		player = AudioStreamPlayer.new()
		add_child(player)
	if jingle_player == null:
		jingle_player = AudioStreamPlayer.new()
		add_child(jingle_player)


func _process(_delta: float) -> void:
	if tuning == null:
		return
	_ensure_player()
	var volume: float = tuning.get_value("music_volume") / 100.0
	player.volume_db = linear_to_db(volume * 0.8) if volume > 0.0 else -80.0
	jingle_player.volume_db = player.volume_db
	if _job.is_empty():
		if _queue.is_empty():
			return
		_start_job(_queue.pop_front())
	var urgent: bool = _job.key == wanted_key
	if _work(URGENT_SAMPLES_PER_FRAME if urgent else background_budget):
		_finish_job()


## Describes the loop for a track, intensity (game track) and games played in the level.
func spec(intensity: int, track: String = "game", games: int = 0) -> Dictionary:
	# Map and shop music doesn't change with the level, so every level shares one cached loop.
	var level: int = effective_intensity(intensity) if track == "game" else 0
	var bpm: float = track_bpm(track, level, games)
	var layers: Array = layers_for(track, level)
	return {"key": "%s|%d|%d|%s" % [track, level, roundi(bpm), ",".join(layers)],
		"track": track, "level": level, "bpm": bpm}


## Switches to the loop for this screen: instantly when cached, otherwise silence until it is built.
func play_for(intensity: int, track: String = "game", games: int = 0) -> void:
	var want: Dictionary = spec(intensity, track, games)
	if want.key == current_key or want.key == wanted_key:
		return
	if _cache.has(want.key):
		_switch_to(want.key)
		return
	# Kill the old music now rather than letting it play on while the new loop is built.
	wanted_key = want.key
	current_key = ""
	_ensure_player()
	player.stop()
	if _job.is_empty() or _job.key != want.key:
		if not _job.is_empty():
			_queue.push_front(_job.spec)
		_queue = _queue.filter(func(q: Dictionary) -> bool: return q.key != want.key)
		_start_job(want)


## Builds a loop in the background if it is not cached yet, so a later play_for is instant.
func prefetch(intensity: int, track: String = "game", games: int = 0) -> void:
	var want: Dictionary = spec(intensity, track, games)
	if _cache.has(want.key) or (not _job.is_empty() and _job.key == want.key):
		return
	for q in _queue:
		if q.key == want.key:
			return
	if _queue.size() < PREFETCH_MAX:
		_queue.append(want)


func is_cached(intensity: int, track: String = "game", games: int = 0) -> bool:
	return _cache.has(spec(intensity, track, games).key)


func _switch_to(key: String) -> void:
	_ensure_player()
	player.stream = _cache[key]
	current_key = key
	wanted_key = ""
	_cache_order.erase(key)
	_cache_order.append(key)
	if player.is_inside_tree():
		player.play()


func _start_job(want: Dictionary) -> void:
	var buf := PackedFloat32Array()
	buf.resize(loop_samples(want.bpm))
	_job = {"key": want.key, "spec": want, "events": build_events(want.level, want.track, want.bpm), "buf": buf,
		"next": 0, "k": 0, "phase": 0.0, "lfsr": 0x4000, "noise": 1.0, "data": PackedByteArray(), "converted": 0}


## Renders, then converts to 8-bit, a frame's worth. Returns true when the loop is complete.
func _work(budget: int) -> bool:
	if _job.next < _job.events.size():
		_render_some(budget)
		return false
	return _convert_some(CONVERT_PER_FRAME)


func _convert_some(budget: int) -> bool:
	var buf: PackedFloat32Array = _job.buf
	var data: PackedByteArray = _job.data
	if data.size() != buf.size():
		data.resize(buf.size())
	var i: int = _job.converted
	var stop: int = mini(buf.size(), i + budget)
	while i < stop:
		data[i] = int(clampf(buf[i], -1.0, 1.0) * 110.0) & 0xFF
		i += 1
	_job.data = data
	_job.converted = i
	return i >= buf.size()


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
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = RATE
	wav.data = _job.data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = _job.data.size()
	var key: String = _job.key
	_job = {}
	_cache[key] = wav
	_cache_order.append(key)
	while _cache_order.size() > CACHE_MAX:
		var old: String = _cache_order.pop_front()
		if old != current_key:
			_cache.erase(old)
	if key == wanted_key:
		_switch_to(key)


## Builds and plays a loop immediately (tests and tools). Returns the stream.
func render_now(intensity: int, track: String = "game", games: int = 0) -> AudioStreamWAV:
	_ensure_player()
	play_for(intensity, track, games)
	while not _job.is_empty():
		if _work(1 << 22):
			_finish_job()
	return player.stream


# ---------------------------------------------------------------- jingles

## Stops the music and plays the level win or loss jingle. The next screen starts its own track.
func play_jingle(win: bool) -> void:
	_ensure_player()
	player.stop()
	current_key = ""
	wanted_key = ""
	jingle_player.stream = jingle(win)
	if jingle_player.is_inside_tree():
		jingle_player.play()


func jingle(win: bool) -> AudioStreamWAV:
	var name: String = "win" if win else "lose"
	if not _jingles.has(name):
		_jingles[name] = _synth(JINGLES[name])
	return _jingles[name]


## Renders a short one-shot from note rows.
static func _synth(notes: Array) -> AudioStreamWAV:
	var length: float = 0.0
	for n in notes:
		length = maxf(length, n[1] + n[2])
	var buf := PackedFloat32Array()
	buf.resize(int((length + 0.1) * RATE))
	for n in notes:
		var start: int = int(n[1] * RATE)
		var count: int = int(n[2] * RATE)
		var phase: float = 0.0
		var lfsr: int = 0x4000
		var noise: float = 1.0
		for k in count:
			var prev: float = phase
			# The last note of the loss jingle sags in pitch, like a sad trombone.
			var bend: float = 1.0 - 0.06 * float(k) / count if n[3] == "square" and n[2] > 0.5 and n[4] == 0.5 else 1.0
			phase += n[0] * bend / RATE
			var frac: float = phase - floorf(phase)
			var v: float
			match n[3]:
				"square":
					v = 1.0 if frac < n[4] else -1.0
				"wave":
					v = roundf((1.0 - 4.0 * absf(frac - 0.5)) * 7.5) / 7.5
				_:
					if floorf(phase) != floorf(prev):
						var bit: int = (lfsr ^ (lfsr >> 1)) & 1
						lfsr = (lfsr >> 1) | (bit << 14)
						noise = 1.0 if lfsr & 1 else -1.0
					v = noise
			var release: float = clampf((count - k) / (count * 0.1 + 1.0), 0.0, 1.0)
			buf[start + k] += v * n[5] * release
	var data := PackedByteArray()
	data.resize(buf.size())
	for i in buf.size():
		data[i] = int(clampf(buf[i], -1.0, 1.0) * 110.0) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
