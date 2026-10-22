extends RefCounted
## Game variables that the debug menu can change. Saved to user://tuning.cfg so tweaks survive restarts.

const SAVE_PATH := "user://tuning.cfg"

## Each entry: key, menu label, default, min, max, step. A 0..1 range with step 1 is shown as ON/OFF.
const DEFS := [
	{"key": "ball_start", "label": "BALL SPEED", "default": 110.0, "min": 40.0, "max": 300.0, "step": 10.0},
	{"key": "ball_accel", "label": "SPEED UP PER HIT", "default": 9.0, "min": 0.0, "max": 40.0, "step": 1.0},
	{"key": "ball_max", "label": "MAX BALL SPEED", "default": 250.0, "min": 80.0, "max": 500.0, "step": 10.0},
	{"key": "bounce_angle", "label": "MAX BOUNCE ANGLE", "default": 55.0, "min": 15.0, "max": 75.0, "step": 5.0},
	{"key": "player_speed", "label": "PLAYER PADDLE SPEED", "default": 150.0, "min": 40.0, "max": 400.0, "step": 10.0},
	{"key": "cpu_speed", "label": "CPU PADDLE SPEED", "default": 98.0, "min": 20.0, "max": 400.0, "step": 4.0},
	{"key": "cpu_error", "label": "CPU AIM ERROR", "default": 10.0, "min": 0.0, "max": 30.0, "step": 1.0},
	{"key": "paddle_h", "label": "PADDLE SIZE", "default": 24.0, "min": 8.0, "max": 80.0, "step": 2.0},
	{"key": "win_score", "label": "POINTS TO WIN", "default": 7.0, "min": 1.0, "max": 21.0, "step": 1.0},
	{"key": "serve_delay", "label": "SERVE DELAY", "default": 0.7, "min": 0.0, "max": 3.0, "step": 0.1},
	{"key": "powerups", "label": "POWER UPS", "default": 1.0, "min": 0.0, "max": 1.0, "step": 1.0},
	{"key": "pu_interval", "label": "POWER UP EVERY SEC", "default": 6.0, "min": 1.0, "max": 30.0, "step": 1.0},
	{"key": "pu_max", "label": "MAX POWER UPS ON FIELD", "default": 2.0, "min": 1.0, "max": 6.0, "step": 1.0},
	{"key": "pu_duration", "label": "EFFECT TIME SEC", "default": 8.0, "min": 2.0, "max": 30.0, "step": 1.0},
	{"key": "max_balls", "label": "MAX BALLS", "default": 5.0, "min": 1.0, "max": 12.0, "step": 1.0},
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
	values[key] = clampf(snappedf(value, def.step), def.min, def.max)


## Moves a setting by steps (negative to decrease).
func nudge(key: String, steps: int) -> void:
	set_value(key, get_value(key) + steps * float(_def(key).step))


func format(key: String) -> String:
	var def: Dictionary = _def(key)
	var v: float = get_value(key)
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
