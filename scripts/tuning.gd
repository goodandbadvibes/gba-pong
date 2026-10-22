extends RefCounted
## Game variables that the debug menu can change. Saved to user://tuning.cfg so tweaks survive restarts.

const SAVE_PATH := "user://tuning.cfg"

## Each entry: key, menu label, default, min, max, step. A 0..1 range with step 1 is shown as ON/OFF;
## "labels" names the first values (the rest show as numbers).
const DEFS := [
	# Match structure
	{"key": "points_per_game", "label": "POINTS PER GAME", "default": 3.0, "min": 1.0, "max": 21.0, "step": 1.0},
	{"key": "best_of", "label": "ROUND IS BEST OF GAMES", "default": 5.0, "min": 1.0, "max": 9.0, "step": 2.0},
	{"key": "serve_delay", "label": "SERVE DELAY", "default": 0.7, "min": 0.0, "max": 3.0, "step": 0.1},
	# Opponent difficulty
	{"key": "cpu_speed", "label": "CPU BASE SPEED", "default": 98.0, "min": 20.0, "max": 400.0, "step": 4.0},
	{"key": "cpu_lv", "label": "CPU SPEED +% PER LEVEL", "default": 8.0, "min": 0.0, "max": 50.0, "step": 1.0},
	{"key": "cpu_error", "label": "CPU BASE AIM ERROR", "default": 10.0, "min": 0.0, "max": 30.0, "step": 1.0},
	{"key": "cpu_aim_lv", "label": "CPU AIM GAIN PER LEVEL", "default": 0.8, "min": 0.0, "max": 5.0, "step": 0.1},
	{"key": "ball_lv", "label": "BALL SPEED +% PER LEVEL", "default": 3.0, "min": 0.0, "max": 20.0, "step": 1.0},
	{"key": "boss_every", "label": "BOSS EVERY N LEVELS", "default": 5.0, "min": 0.0, "max": 10.0, "step": 1.0},
	{"key": "boss_bonus", "label": "BOSS STRENGTH +%", "default": 25.0, "min": 0.0, "max": 100.0, "step": 5.0},
	# Ball
	{"key": "ball_start", "label": "BALL SPEED", "default": 110.0, "min": 40.0, "max": 300.0, "step": 10.0},
	{"key": "ball_accel", "label": "SPEED UP PER HIT", "default": 9.0, "min": 0.0, "max": 40.0, "step": 1.0},
	{"key": "ball_max", "label": "MAX BALL SPEED", "default": 250.0, "min": 80.0, "max": 500.0, "step": 10.0},
	{"key": "bounce_angle", "label": "MAX BOUNCE ANGLE", "default": 55.0, "min": 15.0, "max": 75.0, "step": 5.0},
	# Paddles
	{"key": "player_speed", "label": "PLAYER PADDLE SPEED", "default": 150.0, "min": 40.0, "max": 400.0, "step": 10.0},
	{"key": "paddle_h", "label": "PADDLE SIZE", "default": 24.0, "min": 8.0, "max": 80.0, "step": 2.0},
	# Power-ups and pickups
	{"key": "powerups", "label": "POWER UPS", "default": 1.0, "min": 0.0, "max": 1.0, "step": 1.0},
	{"key": "pu_interval", "label": "POWER UP EVERY SEC", "default": 6.0, "min": 1.0, "max": 30.0, "step": 1.0},
	{"key": "pu_max", "label": "MAX POWER UPS ON FIELD", "default": 2.0, "min": 1.0, "max": 6.0, "step": 1.0},
	{"key": "pu_hitbox", "label": "POWER UP HITBOX", "default": 7.0, "min": 3.0, "max": 24.0, "step": 1.0},
	{"key": "pu_duration", "label": "EFFECT TIME SEC", "default": 8.0, "min": 2.0, "max": 30.0, "step": 1.0},
	{"key": "max_balls", "label": "MAX BALLS", "default": 5.0, "min": 1.0, "max": 12.0, "step": 1.0},
	{"key": "gem_interval", "label": "GEM SHARD EVERY SEC", "default": 9.0, "min": 2.0, "max": 30.0, "step": 1.0},
	# Upgrades
	{"key": "burn_time", "label": "BURN TIME SEC", "default": 4.0, "min": 1.0, "max": 15.0, "step": 0.5},
	{"key": "slime_time", "label": "SLIME TIME SEC", "default": 4.0, "min": 1.0, "max": 15.0, "step": 0.5},
	{"key": "magnet_range", "label": "MAGNET RANGE", "default": 40.0, "min": 10.0, "max": 120.0, "step": 5.0},
	# Wingmen (extra paddles) and turrets
	{"key": "drone_hp", "label": "WINGMAN HP", "default": 2.0, "min": 1.0, "max": 10.0, "step": 1.0},
	{"key": "drone_speed", "label": "WINGMAN PATROL SPEED", "default": 50.0, "min": 10.0, "max": 200.0, "step": 5.0},
	{"key": "unit_hp", "label": "TURRET HP", "default": 2.0, "min": 1.0, "max": 10.0, "step": 1.0},
	{"key": "unit_range", "label": "TURRET REACH", "default": 12.0, "min": 4.0, "max": 30.0, "step": 1.0},
	{"key": "unit_respawn", "label": "TURRET REBUILD SEC", "default": 8.0, "min": 1.0, "max": 30.0, "step": 0.5},
	# Shop and relics
	{"key": "shop_every", "label": "SHOP EVERY N LEVELS", "default": 2.0, "min": 0.0, "max": 10.0, "step": 1.0},
	{"key": "relic_price", "label": "RELIC PRICE %", "default": 100.0, "min": 10.0, "max": 300.0, "step": 10.0},
	{"key": "split_chance", "label": "SPLITTER CHANCE %", "default": 15.0, "min": 0.0, "max": 100.0, "step": 5.0},
	# Sound and music. Layers: OFF, AUTO (joins as levels rise) or always ON.
	{"key": "sound", "label": "SOUND", "default": 1.0, "min": 0.0, "max": 1.0, "step": 1.0},
	{"key": "music_volume", "label": "MUSIC VOLUME", "default": 60.0, "min": 0.0, "max": 100.0, "step": 5.0},
	{"key": "music_bpm", "label": "MUSIC BASE BPM", "default": 84.0, "min": 50.0, "max": 180.0, "step": 2.0},
	{"key": "music_bpm_lv", "label": "MUSIC BPM + PER LEVEL", "default": 4.0, "min": 0.0, "max": 20.0, "step": 1.0},
	{"key": "music_intensity", "label": "MUSIC INTENSITY", "default": 0.0, "min": 0.0, "max": 8.0, "step": 1.0, "labels": ["AUTO"]},
	{"key": "layer_pulse", "label": "LAYER LOW PULSE", "default": 1.0, "min": 0.0, "max": 2.0, "step": 1.0, "labels": ["OFF", "AUTO", "ON"]},
	{"key": "layer_bass", "label": "LAYER BASS", "default": 1.0, "min": 0.0, "max": 2.0, "step": 1.0, "labels": ["OFF", "AUTO", "ON"]},
	{"key": "layer_hats", "label": "LAYER NOISE HATS", "default": 1.0, "min": 0.0, "max": 2.0, "step": 1.0, "labels": ["OFF", "AUTO", "ON"]},
	{"key": "layer_arp", "label": "LAYER ARPEGGIO", "default": 1.0, "min": 0.0, "max": 2.0, "step": 1.0, "labels": ["OFF", "AUTO", "ON"]},
	{"key": "layer_lead", "label": "LAYER LEAD", "default": 1.0, "min": 0.0, "max": 2.0, "step": 1.0, "labels": ["OFF", "AUTO", "ON"]},
	# Feel and controls
	{"key": "hitstop", "label": "HITSTOP SEC", "default": 0.05, "min": 0.0, "max": 0.2, "step": 0.01},
	{"key": "shake", "label": "SCREEN SHAKE", "default": 1.0, "min": 0.0, "max": 3.0, "step": 0.25},
	{"key": "swipe_speed", "label": "SWIPE SPEED", "default": 1.5, "min": 0.5, "max": 4.0, "step": 0.25},
	{"key": "touch_buttons", "label": "ON SCREEN BUTTONS", "default": 0.0, "min": 0.0, "max": 1.0, "step": 1.0},
]

var values: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	for def in DEFS:
		values[def.key] = def.default


func get_value(key: String) -> float:
	return values[key]


func set_value(key: String, value: float) -> void:
	var def: Dictionary = _def(key)
	# Snap to steps counted from the minimum, so odd-only settings (best of 1, 3, 5...) stay odd.
	values[key] = clampf(def.min + snappedf(value - def.min, def.step), def.min, def.max)


## Moves a setting by steps (negative to decrease).
func nudge(key: String, steps: int) -> void:
	set_value(key, get_value(key) + steps * float(_def(key).step))


func format(key: String) -> String:
	var def: Dictionary = _def(key)
	var v: float = get_value(key)
	if def.has("labels") and int(v) < def.labels.size():
		return def.labels[int(v)]
	if def.min == 0.0 and def.max == 1.0 and def.step == 1.0:
		return "ON" if v >= 1.0 else "OFF"
	if def.step >= 1.0:
		return str(int(v))
	return String.num(v, 2)


func save() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("tuning", key, values[key])
	cfg.save(SAVE_PATH)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for def in DEFS:
		if cfg.has_section_key("tuning", def.key):
			set_value(def.key, float(cfg.get_value("tuning", def.key)))


func _def(key: String) -> Dictionary:
	for def in DEFS:
		if def.key == key:
			return def
	push_error("Unknown tuning key: " + key)
	return {}
