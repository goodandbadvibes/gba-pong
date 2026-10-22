extends Node2D
## GBA-style roguelite Pong at 240x160.
## Point -> game (first to POINTS PER GAME) -> round (best of N games, one map node) -> run.
## Win a round: pick an upgrade, move one node on the map, and visit the relic shop every few levels.
## Lose one: the run ends (gems are credited as they are earned). Wingmen patrol in front of a paddle
## and turrets swat balls away; both have HP. Pause: Esc, P or the corner button. Debug: F1, ` or tap
## the top center.

const Palette := preload("res://scripts/palette.gd")
const Tuning := preload("res://scripts/tuning.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Ball := preload("res://scripts/ball.gd")
const Run := preload("res://scripts/run.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const Relics := preload("res://scripts/relics.gd")
const Screens := preload("res://scripts/screens.gd")
const Music := preload("res://scripts/music.gd")

enum State { TITLE, MAP, SHOP, SERVE, PLAY, ROUND_END, UPGRADE, RUN_OVER }
enum PowerUp { FAST_BALL, MULTI_BALL, BIG_PADDLE, FAST_PADDLE, SHRINK_FOE, SLOW_FOE, WINGMAN, TURRET, POISON, BOOSTER }

const W := 240
const H := 160
const TOP := 14
const BOTTOM := 156
const PADDLE_W := 4
const PADDLE_X: Array[int] = [8, W - 8 - PADDLE_W]
const BALL := 4
const PU_SIZE := 7
const PU_LIFE := 9.0
const GEM_SIZE := 5
const GEM_LIFE := 10.0
const MULTI_SPREAD := 0.35
const ROUND_END_TIME := 1.4
const SCREEN_LOCK := 0.35
const MAP_ANIM := Screens.MAP_ANIM
const DRONE_W := 3
const DRONE_H := 14
const DRONE_LANES := 4
const UNIT_SIZE := 6
const UNIT_SLOTS_Y := [44.0, 116.0, 80.0, 30.0, 130.0]
const UNIT_HIT_COOLDOWN := 0.3
const MOMENTUM_STEP := 0.06
const MOMENTUM_MAX := 10

const BG := Palette.BG
const BG_FLASH := Palette.BG_FLASH
const DIM := Palette.DIM
const MID := Palette.MID
const WHITE := Palette.WHITE
const SIDE_COL: Array[Color] = [Palette.PLAYER, Palette.CPU]
const SPARK := Palette.SPARK
const GEM_COL := Palette.GEM
const BOSS_COL := Palette.BOSS

const PU_INFO := {
	PowerUp.FAST_BALL: {"label": "FAST BALL!", "color": Color8(248, 216, 72),
		"icon": ["10100", "01010", "00101", "01010", "10100"]},
	PowerUp.MULTI_BALL: {"label": "MULTI BALL!", "color": Color8(248, 248, 248),
		"icon": ["10001", "00000", "00100", "00000", "10001"]},
	PowerUp.BIG_PADDLE: {"label": "BIG PADDLE!", "color": Color8(88, 216, 104),
		"icon": ["01110", "00100", "00100", "00100", "01110"]},
	PowerUp.FAST_PADDLE: {"label": "QUICK PADDLE!", "color": Color8(72, 200, 248),
		"icon": ["00110", "01100", "11110", "00110", "01100"]},
	PowerUp.SHRINK_FOE: {"label": "SHRINK FOE!", "color": Color8(248, 72, 72),
		"icon": ["10001", "01010", "00100", "01010", "10001"]},
	PowerUp.SLOW_FOE: {"label": "SLOW FOE!", "color": Color8(168, 104, 248),
		"icon": ["01010", "01010", "01010", "01010", "01010"]},
	PowerUp.WINGMAN: {"label": "WINGMAN!", "color": Color8(152, 184, 248),
		"icon": ["10100", "10101", "10101", "10101", "00101"]},
	PowerUp.TURRET: {"label": "TURRET!", "color": Color8(248, 200, 72),
		"icon": ["00100", "01110", "11011", "01110", "00100"]},
	PowerUp.POISON: {"label": "POISON!", "color": Color8(176, 96, 248),
		"icon": ["01110", "10101", "11111", "01110", "01010"]},
	PowerUp.BOOSTER: {"label": "BOOSTER!", "color": Color8(248, 248, 120),
		"icon": ["00110", "01100", "11111", "00110", "01100"]},
}
## Timed paddle effects. size/speed are fixed multipliers; burn and slime are computed from upgrades.
const EFFECT_INFO := {
	"big": {"size": 1.5, "speed": 1.0, "pu": PowerUp.BIG_PADDLE},
	"small": {"size": 0.6, "speed": 1.0, "pu": PowerUp.SHRINK_FOE},
	"fast": {"size": 1.0, "speed": 1.5, "pu": PowerUp.FAST_PADDLE},
	"slow": {"size": 1.0, "speed": 0.6, "pu": PowerUp.SLOW_FOE},
	"boost": {"size": 1.0, "speed": 1.0, "pu": PowerUp.BOOSTER},
	"burn": {"upgrade": "flame"},
	"slime": {"upgrade": "slime"},
}

var tuning := Tuning.new()
var run := Run.new()
## Off in tests, so they neither load nor overwrite the player's saved settings and progress.
## Applied at once rather than in _ready(), which never runs for nodes created in a test's _initialize().
var persist_tuning: bool = true:
	set(value):
		persist_tuning = value
		run.persist = value
var music: Music
var state: State = State.TITLE
var paddle_cy: Array[float] = [H / 2.0, H / 2.0]
## effects[side][name] = {"t": seconds left, "total": starting seconds, "src": side that caused it}
var effects: Array[Dictionary] = [{}, {}]
var balls: Array[Ball] = []
var scores: Array[int] = [0, 0]
var serve_dir: int = 1
var serve_timer: float = 0.0
var cpu_aim_error: float = 0.0
var powerups: Array[Dictionary] = []
var pu_timer: float = 0.0
var gems: Array[Dictionary] = []
var gem_timer: float = 0.0
## Extra paddles: {side, x, y (center), dir, hp, max_hp, temp, flash}
var drones: Array[Dictionary] = []
## Turrets: {side, pos (center), hp, max_hp, alive, rebuild, hit_cd, temp, flash}
var units: Array[Dictionary] = []
## Poison built up on each side; at POISON TO TRIGGER the side's paddle freezes and its allies are hurt.
var poison: Array[float] = [0.0, 0.0]
## Seconds each paddle stays frozen.
var frozen: Array[float] = [0.0, 0.0]
## Seconds played in this round, for the power-up ramp.
var round_time: float = 0.0

# Round and screen flow
var round_won: bool = false
var transition: float = 0.0
var screen_lock: float = 0.0
var map_anim: float = 0.0
var offers: Array[String] = []
var offer_index: int = 0
## True for the free upgrade picked at the start of a run.
var starting_pick: bool = false
var shop_offers: Array[String] = []
var shop_index: int = 0
var title_index: int = 0
var run_result: Dictionary = {}
var banner: String = ""

# Pause menu
var paused: bool = false
var pause_index: int = 0
var pause_view: String = "main"

# Effects
var hitstop: float = 0.0
var shake: float = 0.0
var bg_flash: float = 0.0
var paddle_flash: Array[float] = [0.0, 0.0]
var score_pop: Array[float] = [0.0, 0.0]
var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var blink: float = 0.0
var rng := RandomNumberGenerator.new()

# Debug menu
var menu_open: bool = false
var menu_index: int = 0
var menu_scroll: int = 0

# Touch: one finger swipes the paddle; on-screen buttons are optional (debug menu).
var touch_seen: bool = false
var swipe_index: int = -1
var pending_swipe: float = 0.0
var button_touches: Dictionary = {}

var sfx := {}


func _ready() -> void:
	rng.randomize()
	if persist_tuning:
		tuning.load_saved()
		run.load_saved()
	sfx["paddle"] = _make_blip(880.0, 0.05)
	sfx["wall"] = _make_blip(440.0, 0.03)
	sfx["score"] = _make_blip(196.0, 0.2)
	sfx["serve"] = _make_blip(660.0, 0.04)
	sfx["power"] = _make_blip(1320.0, 0.09)
	sfx["menu"] = _make_blip(990.0, 0.02)
	sfx["gem"] = _make_blip(1760.0, 0.06)
	sfx["win"] = _make_blip(1046.0, 0.25)
	sfx["lose"] = _make_blip(131.0, 0.35)
	sfx["break"] = _make_blip(165.0, 0.12)
	sfx["zap"] = _make_blip(1480.0, 0.03)
	sfx["poison"] = _make_blip(98.0, 0.3)
	music = Music.new()
	music.tuning = tuning
	add_child(music)


func _process(delta: float) -> void:
	blink += delta
	AudioServer.set_bus_mute(0, tuning.get_value("sound") < 1.0)
	if music:
		music.play_for(music_intensity(), music_track(), run.games[0] + run.games[1] if in_round() else 0)
	if not menu_open and not paused:
		screen_lock = maxf(0.0, screen_lock - delta)
		map_anim = maxf(0.0, map_anim - delta)
		_screen_keys()
		var touch_dir: float = 0.0
		for dir in button_touches.values():
			touch_dir += dir
		simulate(delta, clampf(Input.get_axis("ui_up", "ui_down") + touch_dir, -1.0, 1.0))
	queue_redraw()


## Music grows with the level: calm on the title, a step busier and faster each level, more for bosses.
func music_intensity() -> int:
	match state:
		State.TITLE, State.RUN_OVER:
			return 0
	return run.level + (1 if is_boss() and in_round() else 0)


func music_track() -> String:
	match state:
		State.MAP, State.UPGRADE:
			return "map"
		State.SHOP:
			return "shop"
	return "game"


func _screen_keys() -> void:
	if screen_lock > 0.0:
		return
	var confirm: bool = Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up") \
		or Input.is_action_just_pressed("ui_down")
	match state:
		State.TITLE:
			if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
				title_index = wrapi(title_index + 1, 0, title_items().size())
				_play("menu")
			elif Input.is_action_just_pressed("ui_accept"):
				title_choose(title_index)
		State.UPGRADE:
			if Input.is_action_just_pressed("ui_left"):
				offer_index = wrapi(offer_index - 1, 0, offers.size())
				_play("menu")
			elif Input.is_action_just_pressed("ui_right"):
				offer_index = wrapi(offer_index + 1, 0, offers.size())
				_play("menu")
			elif Input.is_action_just_pressed("ui_accept"):
				pick_upgrade(offer_index)
		State.SHOP:
			# The cards plus LEAVE as the last choice.
			if Input.is_action_just_pressed("ui_left"):
				shop_index = wrapi(shop_index - 1, 0, shop_offers.size() + 1)
				_play("menu")
			elif Input.is_action_just_pressed("ui_right"):
				shop_index = wrapi(shop_index + 1, 0, shop_offers.size() + 1)
				_play("menu")
			elif Input.is_action_just_pressed("ui_accept"):
				shop_choose(shop_index)
		State.MAP, State.RUN_OVER:
			if confirm:
				_screen_confirm()


## Advances from the map or run-over screen.
func _screen_confirm() -> void:
	match state:
		State.MAP:
			if map_anim > 0.0:
				return
			if run.shop_pending:
				open_shop()
			else:
				start_round()
		State.RUN_OVER:
			state = State.TITLE
			title_index = 0
			screen_lock = SCREEN_LOCK


func title_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if run.can_continue():
		items.append({"id": "continue", "label": "CONTINUE RUN  LEVEL %d" % int(run.suspended.get("level", 1))})
	items.append({"id": "new", "label": "NEW RUN"})
	return items


func title_choose(index: int) -> void:
	var items := title_items()
	if index < 0 or index >= items.size():
		return
	if items[index].id == "continue":
		run.resume()
		_enter_map(false)
	else:
		start_run()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch(event)
		_consume()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_F1 or key.keycode == KEY_QUOTELEFT:
		if not key.echo:
			_toggle_menu()
		_consume()
	elif menu_open:
		_menu_key(key)
		_consume()
	elif paused:
		_pause_key(key)
		_consume()
	elif (key.keycode == KEY_ESCAPE or key.keycode == KEY_P) and not key.echo and can_pause():
		set_paused(true)
		_consume()


## Marks the event handled. Guarded so tests can feed input to a node outside a viewport.
func _consume() -> void:
	var viewport := get_viewport()
	if viewport:
		viewport.set_input_as_handled()


# ---------------------------------------------------------------- touch

const DEBUG_HOTSPOT := Rect2(W / 2 - 32, 0, 64, TOP)
const PAUSE_BUTTON := Rect2(0, 0, 13, 13)
const TOUCH_UP := Rect2(W - 64, TOP + 8, 30, 30)
const TOUCH_DOWN := Rect2(W - 64, BOTTOM - 38, 30, 30)
const MENU_BAR_H := 12
const MENU_BUTTONS := ["UP", "DOWN", "-", "+", "OK", "CLOSE"]


func touch_buttons_on() -> bool:
	return tuning.get_value("touch_buttons") >= 1.0


func in_round() -> bool:
	return state == State.SERVE or state == State.PLAY


func can_pause() -> bool:
	return state in [State.MAP, State.SHOP, State.SERVE, State.PLAY, State.UPGRADE]


## Positions arrive in game pixels (240x160) because the viewport stretch transforms them.
func _touch(event: InputEvent) -> void:
	touch_seen = true
	var drag := event as InputEventScreenDrag
	if drag:
		if drag.index == swipe_index and not menu_open and not paused:
			pending_swipe += drag.relative.y * tuning.get_value("swipe_speed")
		return

	var touch := event as InputEventScreenTouch
	if not touch.pressed:
		button_touches.erase(touch.index)
		if touch.index == swipe_index:
			swipe_index = -1
		return
	if menu_open:
		_menu_touch(touch.position)
		return
	if paused:
		_pause_touch(touch.position)
		return
	if DEBUG_HOTSPOT.has_point(touch.position):
		_toggle_menu()
		return
	if can_pause() and PAUSE_BUTTON.has_point(touch.position):
		set_paused(true)
		return
	if screen_lock > 0.0 and not in_round():
		return
	match state:
		State.TITLE:
			var row: int = Screens.title_item_at(touch.position, title_items().size())
			if row >= 0:
				title_index = row
				title_choose(row)
			return
		State.MAP, State.RUN_OVER:
			_screen_confirm()
			return
		State.UPGRADE:
			var card: int = Screens.card_at(touch.position, offers.size())
			if card >= 0:
				if card == offer_index:
					pick_upgrade(card)
				else:
					offer_index = card
					_play("menu")
			return
		State.SHOP:
			var choice: int = Screens.shop_choice_at(touch.position, shop_offers.size())
			if choice >= 0:
				if choice == shop_index or choice == shop_offers.size():
					shop_index = choice
					shop_choose(choice)
				else:
					shop_index = choice
					_play("menu")
			return
		State.ROUND_END:
			return
	if touch_buttons_on():
		if TOUCH_UP.grow(4).has_point(touch.position):
			button_touches[touch.index] = -1.0
			return
		if TOUCH_DOWN.grow(4).has_point(touch.position):
			button_touches[touch.index] = 1.0
			return
	swipe_index = touch.index


func _menu_touch(pos: Vector2) -> void:
	if pos.y >= H - MENU_BAR_H:
		var button: int = clampi(int(pos.x / (W / MENU_BUTTONS.size())), 0, MENU_BUTTONS.size() - 1)
		_menu_action(["up", "down", "dec", "inc", "ok", "close"][button])
		return
	var row: int = menu_scroll + int((pos.y - 11.0) / 7.0)
	if pos.y < 11.0 or row >= _menu_items().size():
		return
	if row != menu_index:
		menu_index = row
		_play("menu")
	elif _menu_items()[row].kind == "value":
		# Tap the right half of the selected row's value: right quarter raises, the quarter before lowers.
		if pos.x >= W * 0.75:
			_menu_action("inc")
		elif pos.x >= W * 0.5:
			_menu_action("dec")
	else:
		_menu_action("ok")


# ---------------------------------------------------------------- pause menu

func pause_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{"id": "resume", "label": "RESUME"},
		{"id": "sound", "label": "SOUND: " + ("ON" if tuning.get_value("sound") >= 1.0 else "OFF")},
		{"id": "relics", "label": "RELICS (%d)" % run.relics.size()},
		{"id": "suspend", "label": "SUSPEND RUN"},
		{"id": "menu", "label": "MAIN MENU (END RUN)"},
	]
	# Browsers can't close their own tab, so QUIT only exists on desktop builds.
	if not OS.has_feature("web"):
		items.append({"id": "quit", "label": "QUIT GAME"})
	return items


func set_paused(on: bool) -> void:
	paused = on
	pause_index = 0
	pause_view = "main"
	button_touches.clear()
	swipe_index = -1
	pending_swipe = 0.0
	_play("menu")


func _pause_key(key: InputEventKey) -> void:
	if pause_view == "relics":
		pause_view = "main"
		_play("menu")
		return
	match key.keycode:
		KEY_UP:
			pause_index = wrapi(pause_index - 1, 0, pause_items().size())
			_play("menu")
		KEY_DOWN:
			pause_index = wrapi(pause_index + 1, 0, pause_items().size())
			_play("menu")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			pause_choose(pause_index)
		KEY_ESCAPE, KEY_P:
			if not key.echo:
				set_paused(false)


func _pause_touch(pos: Vector2) -> void:
	if pause_view == "relics":
		pause_view = "main"
		_play("menu")
		return
	var row: int = Screens.pause_item_at(pos, pause_items().size())
	if row >= 0:
		pause_index = row
		pause_choose(row)


func pause_choose(index: int) -> void:
	var items := pause_items()
	if index < 0 or index >= items.size():
		return
	match items[index].id:
		"resume":
			set_paused(false)
		"sound":
			tuning.set_value("sound", 0.0 if tuning.get_value("sound") >= 1.0 else 1.0)
			if persist_tuning:
				tuning.save()
			_play("menu")
		"relics":
			pause_view = "relics"
			_play("menu")
		"suspend":
			run.suspend()
			_leave_to_title()
		"menu":
			run_result = run.finish()
			_leave_to_title()
		"quit":
			run.suspend()
			get_tree().quit()


func _leave_to_title() -> void:
	set_paused(false)
	_clear_field()
	state = State.TITLE
	title_index = 0
	screen_lock = SCREEN_LOCK


# ---------------------------------------------------------------- run flow

## A new run opens with a free upgrade pick, then the map.
func start_run() -> void:
	run.start()
	offers = Upgrades.offers(rng, run.stacks)
	offer_index = 0
	starting_pick = true
	state = State.UPGRADE
	screen_lock = SCREEN_LOCK
	_play("menu")


func _clear_field() -> void:
	balls.clear()
	powerups.clear()
	gems.clear()
	drones.clear()
	units.clear()
	effects = [{}, {}]
	poison = [0.0, 0.0]
	frozen = [0.0, 0.0]


func start_round() -> void:
	scores = [0, 0]
	run.games.assign([0, 0])
	_clear_field()
	paddle_cy = [H / 2.0, H / 2.0]
	pu_timer = _pu_interval()
	gem_timer = _gem_interval()
	serve_dir = 1 if rng.randf() < 0.5 else -1
	round_time = 0.0
	for side in 2:
		for i in level_of(side, "turret"):
			spawn_unit(side, false)
	_start_game()
	_begin_serve()


## Every game: WINGMAN refills patrolling paddles and OVERCHARGE starts a booster.
func _start_game() -> void:
	for side in 2:
		var have: int = drones.filter(func(d: Dictionary) -> bool: return d.side == side and not d.temp).size()
		for i in level_of(side, "wingman") - have:
			spawn_drone(side, false)
		if level_of(side, "overcharge") > 0:
			_add_effect(side, "boost", 2.0 * level_of(side, "overcharge"), side)


func games_to_win() -> int:
	return int(tuning.get_value("best_of")) / 2 + 1


func is_boss() -> bool:
	return Run.is_boss(run.level, int(tuning.get_value("boss_every")))


## How much stronger the CPU is this level, as a multiplier (1.0 at level 1).
func level_factor(per_level_pct: String) -> float:
	var f: float = 1.0 + tuning.get_value(per_level_pct) / 100.0 * (run.level - 1)
	if is_boss():
		f *= 1.0 + tuning.get_value("boss_bonus") / 100.0
	return f


func cpu_error() -> float:
	var err: float = maxf(1.0, tuning.get_value("cpu_error") - tuning.get_value("cpu_aim_lv") * (run.level - 1))
	return err / (1.0 + tuning.get_value("boss_bonus") / 100.0) if is_boss() else err


func _game_won(winner: int) -> void:
	run.games[winner] += 1
	run.streak = run.streak + 1 if winner == 0 else 0
	scores = [0, 0]
	balls.clear()
	var color: Color = SIDE_COL[winner]
	_popup("GAME!" if winner == 0 else "CPU GAME", Vector2(W / 2.0, 40.0), color, 1.0)
	_burst(Vector2(W / 2.0, H / 2.0), Vector2.ZERO, 24, color)
	if run.games[winner] >= games_to_win():
		_round_end(winner)
	else:
		_start_game()
		_begin_serve(0.8)


func _round_end(winner: int) -> void:
	state = State.ROUND_END
	round_won = winner == 0
	transition = ROUND_END_TIME
	_clear_field()
	_shake(4.0)
	bg_flash = 0.12
	if round_won:
		run.clear_round(int(tuning.get_value("boss_every")), int(tuning.get_value("shop_every")))
		for i in int(tuning.get_value("cpu_upgrades")):
			give_cpu_upgrade()
		_play("win")
	else:
		_play("lose")


## The opponent gets stronger: one random upgrade per level it reaches (none on level 1).
func give_cpu_upgrade() -> String:
	var pick: Array[String] = Upgrades.offers(rng, run.cpu_stacks, 1, Upgrades.CPU_EXCLUDED)
	if pick.is_empty():
		return ""
	run.cpu_add(pick[0])
	return pick[0]


func _after_round() -> void:
	screen_lock = SCREEN_LOCK
	if round_won:
		offers = Upgrades.offers(rng, run.stacks)
		offer_index = 0
		starting_pick = false
		if offers.is_empty():
			_enter_map(true)
		else:
			state = State.UPGRADE
	elif run.has_relic("second") and not run.second_wind_used:
		# SECOND WIND: the run survives one lost round; replay the same level.
		run.second_wind_used = true
		run.streak = 0
		run.save()
		_enter_map(false)
		_popup("SECOND WIND!", Vector2(W / 2.0, 110.0), Relics.DEFS.second.color, 1.5)
	else:
		run_result = run.finish()
		state = State.RUN_OVER


func pick_upgrade(index: int) -> void:
	if state != State.UPGRADE or index < 0 or index >= offers.size():
		return
	run.add(offers[index])
	_play("power")
	_enter_map(not starting_pick)
	starting_pick = false


func _enter_map(advanced: bool) -> void:
	state = State.MAP
	map_anim = MAP_ANIM if advanced else 0.0
	screen_lock = SCREEN_LOCK


func open_shop() -> void:
	shop_offers = Relics.offers(rng, run.relics)
	shop_index = 0
	state = State.SHOP
	screen_lock = SCREEN_LOCK
	_play("menu")


func relic_price(id: String) -> int:
	return Relics.price(id, tuning.get_value("relic_price"))


## Buys the relic at index, or leaves the shop when index is past the cards.
func shop_choose(index: int) -> void:
	if state != State.SHOP:
		return
	if index >= shop_offers.size():
		run.shop_pending = false
		run.save()
		_enter_map(false)
		_play("menu")
		return
	var id: String = shop_offers[index]
	if run.buy(id, relic_price(id)):
		_popup(Relics.DEFS[id].name + "!", Screens.card_rect(index, shop_offers.size()).get_center(), Relics.DEFS[id].color, 1.0)
		_burst(Screens.card_rect(index, shop_offers.size()).get_center(), Vector2.ZERO, 20, Relics.DEFS[id].color)
		_play("power")
	else:
		_shake(2.0)
		_play("wall")


# ---------------------------------------------------------------- simulation

## Advances the game by delta seconds. dir is the player's input: -1 up, 1 down, 0 none.
func simulate(delta: float, dir: float) -> void:
	_update_effects(delta)
	if state == State.ROUND_END:
		transition -= delta
		if transition <= 0.0:
			_after_round()
		return
	if not in_round():
		return
	if hitstop > 0.0:
		hitstop -= delta
		return

	if frozen[0] <= 0.0:
		_move_paddle(0, dir * paddle_speed(0) * delta)
		# Swipes move the paddle directly, scaled by speed effects and upgrades so they still matter.
		_move_paddle(0, pending_swipe * paddle_speed(0) / tuning.get_value("player_speed"))
	pending_swipe = 0.0
	for side in 2:
		frozen[side] = maxf(0.0, frozen[side] - delta)
	if frozen[1] <= 0.0:
		_update_cpu(delta)
	_tick_paddle_effects(delta)
	_update_allies(delta)

	if state == State.SERVE:
		serve_timer -= delta
		if serve_timer <= 0.0:
			_launch_ball()
	else:
		round_time += delta
		_update_pickups(delta)
		for ball in balls.duplicate():
			if state != State.PLAY:
				break
			_move_ball(ball, delta)


func momentum_factor(side: int) -> float:
	if side != 0 or not run.has_relic("momentum"):
		return 1.0
	return 1.0 + MOMENTUM_STEP * mini(run.streak, MOMENTUM_MAX)


## Upgrade levels of side (the player's picks or the CPU's), not scaled.
func level_of(side: int, id: String) -> int:
	return run.stack(id) if side == 0 else run.cpu_stack(id)


## BOOSTER: while active, everything that side has works this much harder.
func boost(side: int) -> float:
	return tuning.get_value("booster_mult") if side >= 0 and effects[side].has("boost") else 1.0


## Upgrade strength of side: its level times its booster.
func up(side: int, id: String) -> float:
	return level_of(side, id) * boost(side)


## A fixed multiplier (power-up effect) pushed further by the booster of the side that caused it.
func _boosted(mult: float, src: int) -> float:
	return 1.0 + (mult - 1.0) * boost(src)


func paddle_height(side: int) -> float:
	var h: float = tuning.get_value("paddle_h") * momentum_factor(side) * (1.0 + 0.15 * up(side, "long"))
	for name in effects[side]:
		var e: Dictionary = effects[side][name]
		if name == "burn":
			h *= 1.0 - burn_strength(e.src) * (1.0 - e.t / e.total)
		elif EFFECT_INFO[name].has("size"):
			h *= _boosted(EFFECT_INFO[name].size, e.src)
	return clampf(roundf(h), 4.0, BOTTOM - TOP)


func paddle_speed(side: int) -> float:
	var s: float
	if side == 0:
		s = tuning.get_value("player_speed") * momentum_factor(0)
	else:
		s = tuning.get_value("cpu_speed") * level_factor("cpu_lv")
	s *= 1.0 + 0.15 * up(side, "swift")
	for name in effects[side]:
		var e: Dictionary = effects[side][name]
		if name == "slime":
			s *= slime_factor(e.src)
		elif EFFECT_INFO[name].has("speed"):
			s *= _boosted(EFFECT_INFO[name].speed, e.src)
	return s


## VIRULENT relic (player only): status effects last and hit 50% more.
func status_boost(src: int) -> float:
	return 1.5 if src == 0 and run.has_relic("virulent") else 1.0


## How much of the paddle a full burn from src takes away (more with more FLAME BALL).
func burn_strength(src: int) -> float:
	return minf(0.8, (0.3 + 0.1 * maxf(0.0, up(src, "flame") - 1.0)) * status_boost(src))


func slime_factor(src: int) -> float:
	var slow: float = (0.4 + 0.1 * maxf(0.0, up(src, "slime") - 1.0)) * status_boost(src)
	return maxf(0.2, 1.0 - slow)


func paddle_top(side: int) -> float:
	return paddle_cy[side] - paddle_height(side) / 2.0


func _move_paddle(side: int, amount: float) -> void:
	var half: float = paddle_height(side) / 2.0
	paddle_cy[side] = clampf(paddle_cy[side] + amount, TOP + half, BOTTOM - half)


func _begin_serve(extra_delay: float = 0.0) -> void:
	state = State.SERVE
	serve_timer = tuning.get_value("serve_delay") + extra_delay
	var game_no: int = run.games[0] + run.games[1] + 1
	banner = ("BOSS " if is_boss() else "") + "LEVEL %d  GAME %d" % [run.level, game_no]
	var ball := Ball.new()
	ball.pos = Vector2((W - BALL) / 2.0, (H - BALL) / 2.0)
	balls = [ball]


func _launch_ball() -> void:
	state = State.PLAY
	var angle: float = rng.randf_range(-0.4, 0.4)
	balls[0].vel = Vector2(cos(angle) * serve_dir, sin(angle)) * tuning.get_value("ball_start") * level_factor("ball_lv")
	_play("serve")


## Follows the ball that will reach the CPU side first; recenters when none is coming.
func _update_cpu(delta: float) -> void:
	var target: float = H / 2.0
	if state == State.PLAY:
		var best_time: float = INF
		for ball in balls:
			if ball.vel.x > 0.0:
				var t: float = (PADDLE_X[1] - ball.pos.x) / ball.vel.x
				if t < best_time:
					best_time = t
					target = ball.pos.y + BALL / 2.0 + cpu_aim_error
	var step: float = paddle_speed(1) * delta
	_move_paddle(1, clampf(target - paddle_cy[1], -step, step))


# Moves in small steps so a fast ball can't pass through a paddle.
func _move_ball(ball: Ball, delta: float) -> void:
	var motion: Vector2 = ball.vel * delta
	var steps: int = maxi(1, ceili(motion.length() / 2.0))
	for i in steps:
		ball.pos += motion / steps
		if _collide(ball):
			return
	ball.trail.push_front(ball.pos)
	if ball.trail.size() > 5:
		ball.trail.pop_back()
	if (ball.flame or ball.slime or ball.venom) and rng.randf() < 0.5:
		var col: Color = upgrade_color("flame") if ball.flame else (upgrade_color("slime") if ball.slime else upgrade_color("venom"))
		particles.append({"pos": ball.pos + Vector2(rng.randf_range(0, BALL), rng.randf_range(0, BALL)),
			"vel": Vector2(rng.randf_range(-10, 10), -20.0 if ball.flame else 25.0), "life": 0.25, "color": col})


## Handles walls, paddles, wingmen, turrets, pickups and goals. Returns true when this ball's motion should stop.
func _collide(ball: Ball) -> bool:
	if ball.pos.y < TOP:
		ball.pos.y = TOP
		ball.vel.y = absf(ball.vel.y)
		_wall_hit(ball)
	elif ball.pos.y > BOTTOM - BALL:
		ball.pos.y = BOTTOM - BALL
		ball.vel.y = -absf(ball.vel.y)
		_wall_hit(ball)

	if ball.vel.x < 0.0 and _overlaps_paddle(ball, 0):
		ball.pos.x = PADDLE_X[0] + PADDLE_W
		_deflect(ball, 0, paddle_cy[0], paddle_height(0) / 2.0, "paddle")
		paddle_flash[0] = 0.1
		return true
	if ball.vel.x > 0.0 and _overlaps_paddle(ball, 1):
		ball.pos.x = PADDLE_X[1] - BALL
		_deflect(ball, 1, paddle_cy[1], paddle_height(1) / 2.0, "paddle")
		paddle_flash[1] = 0.1
		return true
	if _collide_drones(ball) or _collide_units(ball):
		return true

	_check_pickups(ball)

	if ball.pos.x + BALL < 0.0:
		_goal(ball, 1)
		return true
	if ball.pos.x > W:
		_goal(ball, 0)
		return true
	return false


## Side whose goal a ball is heading for (0 player, 1 CPU).
static func _heading_to(ball: Ball) -> int:
	return 0 if ball.vel.x < 0.0 else 1


func _overlaps_paddle(ball: Ball, side: int) -> bool:
	var top: float = paddle_top(side)
	return ball.pos.x < PADDLE_X[side] + PADDLE_W and ball.pos.x + BALL > PADDLE_X[side] \
		and ball.pos.y < top + paddle_height(side) and ball.pos.y + BALL > top


## Sends a ball back toward the other side, angled by where it hit (center_y +- half).
## source is "paddle", "drone" or "unit". A ball last hit by the other side hands over its
## burn, slime and poison first. Then the hitter's upgrades go on the ball: the CPU's always,
## the player's from the paddle, from wingmen with WING SYNC and from turrets with HIVE MIND.
func _deflect(ball: Ball, side: int, center_y: float, half: float, source: String) -> void:
	var offset: float = clampf((ball.pos.y + BALL / 2.0 - center_y) / maxf(half, 1.0), -1.0, 1.0)
	var top_speed: float = tuning.get_value("ball_max") * level_factor("ball_lv")
	var speed: float = minf(ball.vel.length() + tuning.get_value("ball_accel"), maxf(top_speed, ball.vel.length()))
	var angle: float = offset * deg_to_rad(tuning.get_value("bounce_angle"))
	var dir_x: float = 1.0 if side == 0 else -1.0
	var center: Vector2 = ball.pos + Vector2.ONE * BALL / 2.0

	if ball.last_touch == 1 - side:
		_inflict(ball, side, center)

	var inherits: bool = side == 1 or source == "paddle" or (source == "drone" and run.has_relic("sync")) \
		or (source == "unit" and run.has_relic("hive"))
	if inherits:
		speed *= 1.0 + 0.12 * up(side, "power")
	ball.flame = inherits and level_of(side, "flame") > 0
	ball.slime = inherits and level_of(side, "slime") > 0
	ball.venom = inherits and level_of(side, "venom") > 0
	if side == 0:
		var err: float = cpu_error()
		cpu_aim_error = rng.randf_range(-err, err)

	ball.vel = Vector2(cos(angle) * dir_x, sin(angle)) * speed
	ball.last_touch = side
	ball.squash = 0.08
	hitstop = tuning.get_value("hitstop")
	_shake(2.0 if source == "paddle" else 1.0)
	_burst(center, Vector2(dir_x, 0.0), 8, SPARK)
	_play("paddle" if source != "unit" else "zap")

	# SPLITTER: the player's paddle sometimes splits off an extra ball.
	if side == 0 and source == "paddle" and run.has_relic("splitter") \
			and rng.randf() * 100.0 < tuning.get_value("split_chance"):
		_split_ball(ball, MULTI_SPREAD * (1.0 if rng.randf() < 0.5 else -1.0))
		_popup("SPLIT!", center, Relics.DEFS.splitter.color)


## A burning, slimy or poisonous ball from the other side hits side: hand over its effects.
func _inflict(ball: Ball, side: int, center: Vector2) -> void:
	var src: int = 1 - side
	var away: Vector2 = Vector2(1, 0) if side == 0 else Vector2(-1, 0)
	if ball.flame:
		_add_effect(side, "burn", (tuning.get_value("burn_time") + 0.5 * (up(src, "flame") - 1.0)) * status_boost(src), src)
		_popup("BURN!", center, upgrade_color("flame"))
		_burst(center, away, 14, upgrade_color("flame"))
	if ball.slime:
		_add_effect(side, "slime", (tuning.get_value("slime_time") + 0.5 * (up(src, "slime") - 1.0)) * status_boost(src), src)
		_popup("SLIMED!", center + Vector2(0, 8), upgrade_color("slime"))
		_burst(center, away, 14, upgrade_color("slime"))
	if ball.venom:
		# VENOM BALL: 2 poison per hit at level 1, one more per extra level.
		add_poison(side, 1.0 + up(src, "venom"))
		_burst(center, away, 8, upgrade_color("venom"))


## Adds poison to side; reaching POISON TO TRIGGER freezes its paddle and hurts its allies.
func add_poison(side: int, amount: float) -> void:
	poison[side] += amount
	if poison[side] < tuning.get_value("poison_cap"):
		return
	poison[side] = 0.0
	frozen[side] = tuning.get_value("poison_freeze")
	var at := Vector2(PADDLE_X[side] + PADDLE_W / 2.0, paddle_cy[side])
	_popup("POISONED!", at + Vector2(16 if side == 0 else -16, -10), upgrade_color("venom"), 1.0)
	_burst(at, Vector2.ZERO, 24, upgrade_color("venom"))
	for d in drones.duplicate():
		if d.side == side:
			_damage_drone(d)
	for u in units:
		if u.side == side and u.alive:
			_damage_unit(u)
	_shake(4.0)
	_play("poison")


func _split_ball(ball: Ball, turn: float) -> bool:
	if balls.size() >= int(tuning.get_value("max_balls")):
		return false
	var extra := Ball.new()
	extra.pos = ball.pos
	extra.vel = ball.vel.rotated(turn)
	extra.last_touch = ball.last_touch
	extra.flame = ball.flame
	extra.slime = ball.slime
	extra.venom = ball.venom
	balls.append(extra)
	return true


func _wall_hit(ball: Ball) -> void:
	_shake(1.0)
	_burst(ball.pos + Vector2.ONE * BALL / 2.0, Vector2(0.0, signf(ball.vel.y)), 4, MID)
	_play("wall")


func _goal(ball: Ball, scorer: int) -> void:
	balls.erase(ball)
	scores[scorer] += 1
	score_pop[scorer] = 0.3
	_shake(5.0)
	bg_flash = 0.08
	var edge_x: float = 0.0 if scorer == 1 else float(W)
	_burst(Vector2(edge_x, ball.pos.y), Vector2(1.0 if scorer == 1 else -1.0, 0.0), 18, SIDE_COL[scorer])
	_play("score")
	serve_dir = -1 if scorer == 0 else 1
	if scores[scorer] >= int(tuning.get_value("points_per_game")):
		_game_won(scorer)
	elif balls.is_empty():
		_begin_serve()


# ---------------------------------------------------------------- wingmen and turrets

func _ally_hp(key: String, side: int) -> int:
	return int(tuning.get_value(key)) + (1 if side == 0 and run.has_relic("plating") else 0)


## Adds an extra paddle for side in the next free lane in front of its goal. temp ones come from power-ups.
func spawn_drone(side: int, temp: bool) -> bool:
	var used: Array = drones.filter(func(d: Dictionary) -> bool: return d.side == side).map(func(d: Dictionary) -> int: return d.lane)
	var lane: int = -1
	for i in DRONE_LANES:
		if not used.has(i):
			lane = i
			break
	if lane < 0:
		return false
	var x: float = 40.0 + 12.0 * lane if side == 0 else W - 40.0 - DRONE_W - 12.0 * lane
	var hp: int = _ally_hp("drone_hp", side)
	drones.append({"side": side, "lane": lane, "x": x, "y": rng.randf_range(TOP + 20.0, BOTTOM - 20.0),
		"dir": 1.0 if rng.randf() < 0.5 else -1.0, "hp": hp, "max_hp": hp, "temp": temp, "flash": 0.0})
	_burst(Vector2(x, H / 2.0), Vector2.ZERO, 8, PU_INFO[PowerUp.WINGMAN].color)
	return true


## Adds a turret for side in the next free slot. temp ones (power-ups) are not rebuilt when destroyed.
func spawn_unit(side: int, temp: bool) -> bool:
	var used: Array = units.filter(func(u: Dictionary) -> bool: return u.side == side).map(func(u: Dictionary) -> int: return u.slot)
	var slot: int = -1
	for i in UNIT_SLOTS_Y.size():
		if not used.has(i):
			slot = i
			break
	if slot < 0:
		return false
	var x: float = 72.0 if side == 0 else W - 72.0
	var hp: int = _ally_hp("unit_hp", side)
	units.append({"side": side, "slot": slot, "pos": Vector2(x, UNIT_SLOTS_Y[slot]), "hp": hp, "max_hp": hp,
		"alive": true, "rebuild": 0.0, "hit_cd": 0.0, "temp": temp, "flash": 0.0})
	_burst(Vector2(x, UNIT_SLOTS_Y[slot]), Vector2.ZERO, 8, PU_INFO[PowerUp.TURRET].color)
	return true


func _update_allies(delta: float) -> void:
	var half: float = DRONE_H / 2.0
	for d in drones:
		d.flash = maxf(0.0, d.flash - delta)
		d.y += d.dir * tuning.get_value("drone_speed") * delta
		if d.y < TOP + half or d.y > BOTTOM - half:
			d.y = clampf(d.y, TOP + half, BOTTOM - half)
			d.dir = -d.dir
	for u in units:
		u.flash = maxf(0.0, u.flash - delta)
		u.hit_cd = maxf(0.0, u.hit_cd - delta)
		if not u.alive:
			u.rebuild -= delta
			if u.rebuild <= 0.0:
				u.alive = true
				u.hp = u.max_hp
				_burst(u.pos, Vector2.ZERO, 10, PU_INFO[PowerUp.TURRET].color)
				_popup("REBUILT", u.pos + Vector2(0, -8), MID, 0.6)


func _collide_drones(ball: Ball) -> bool:
	var side: int = _heading_to(ball)
	for d in drones:
		if d.side != side:
			continue
		var rect := Rect2(d.x, d.y - DRONE_H / 2.0, DRONE_W, DRONE_H)
		if not rect.intersects(Rect2(ball.pos, Vector2(BALL, BALL))):
			continue
		ball.pos.x = rect.end.x if side == 0 else rect.position.x - BALL
		_deflect(ball, side, d.y, DRONE_H / 2.0, "drone")
		_damage_drone(d)
		return true
	return false


func _collide_units(ball: Ball) -> bool:
	var side: int = _heading_to(ball)
	var reach: float = tuning.get_value("unit_range")
	var center: Vector2 = ball.pos + Vector2.ONE * BALL / 2.0
	for u in units:
		if u.side != side or not u.alive or u.hit_cd > 0.0 or center.distance_to(u.pos) > reach:
			continue
		_deflect(ball, side, u.pos.y, reach, "unit")
		u.hit_cd = UNIT_HIT_COOLDOWN
		# A short zap line from the turret to the ball.
		for i in 6:
			particles.append({"pos": u.pos.lerp(center, i / 5.0), "vel": Vector2.ZERO, "life": 0.12, "color": PU_INFO[PowerUp.TURRET].color})
		_damage_unit(u)
		return true
	return false


func _damage_drone(d: Dictionary) -> void:
	d.hp -= 1
	d.flash = 0.12
	if d.hp <= 0:
		drones.erase(d)
		_ally_destroyed(Vector2(d.x, d.y), "WINGMAN DOWN")


func _damage_unit(u: Dictionary) -> void:
	u.flash = 0.12
	u.hp -= 1
	if u.hp > 0:
		return
	u.alive = false
	_ally_destroyed(u.pos, "TURRET DOWN")
	if u.temp:
		units.erase(u)
	else:
		u.rebuild = tuning.get_value("unit_respawn") / (2.0 if u.side == 0 and run.has_relic("repair") else 1.0)


func _ally_destroyed(at: Vector2, text: String) -> void:
	_burst(at, Vector2.ZERO, 22, SPARK)
	_burst(at, Vector2.ZERO, 12, Palette.BOSS)
	_popup(text, at + Vector2(0, -8), MID, 0.8)
	_shake(3.0)
	_play("break")


# ---------------------------------------------------------------- power-ups, gems, magnet

func _pu_interval() -> float:
	return tuning.get_value("pu_interval") / (1.0 + 0.25 * run.stack("lucky")) / pu_ramp()


## After MORE POWER UPS AFTER SEC in a round, power-ups come POWER UPS THEN X MORE OFTEN.
func pu_ramp() -> float:
	var after: float = tuning.get_value("pu_ramp_after")
	return tuning.get_value("pu_ramp_mult") if after > 0.0 and round_time >= after else 1.0


func _gem_interval() -> float:
	return tuning.get_value("gem_interval") / (1.0 + 0.25 * run.stack("lucky"))


func _update_pickups(delta: float) -> void:
	for list in [powerups, gems]:
		for i in range(list.size() - 1, -1, -1):
			var item: Dictionary = list[i]
			item.life -= delta
			if item.life <= 0.0:
				list.remove_at(i)
	_apply_magnet(delta)
	if tuning.get_value("powerups") >= 1.0:
		pu_timer -= delta
		# The ramp also shortens a wait that started before it kicked in.
		pu_timer = minf(pu_timer, _pu_interval() * 1.3)
		if pu_timer <= 0.0:
			pu_timer = _pu_interval() * rng.randf_range(0.7, 1.3)
			if powerups.size() < int(tuning.get_value("pu_max")):
				spawn_powerup(rng.randi_range(0, PowerUp.size() - 1))
	gem_timer -= delta
	if gem_timer <= 0.0:
		gem_timer = _gem_interval() * rng.randf_range(0.7, 1.3)
		if gems.size() < 2:
			spawn_gem()


## MAGNET BALL: balls pull power-ups and gems within range toward themselves, for whoever hit them last.
func _apply_magnet(delta: float) -> void:
	for ball in balls:
		if ball.last_touch < 0:
			continue
		var level: float = up(ball.last_touch, "magnet")
		if level <= 0.0:
			continue
		var reach: float = tuning.get_value("magnet_range") + 15.0 * (level - 1.0)
		var pull: float = (50.0 + 30.0 * level) * delta
		var center: Vector2 = ball.pos + Vector2.ONE * BALL / 2.0
		for item in powerups + gems:
			var size: float = PU_SIZE if item.has("type") else GEM_SIZE
			var item_center: Vector2 = item.pos + Vector2.ONE * size / 2.0
			if item_center.distance_to(center) < reach:
				item.pos = item.pos.move_toward(item.pos + (center - item_center), pull)


## Places a power-up somewhere in the middle of the court.
func spawn_powerup(type: int, at: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if at.x < 0.0:
		at = _random_field_spot(PU_SIZE)
	powerups.append({"type": type, "pos": at.round(), "life": PU_LIFE})
	_burst(at + Vector2.ONE * PU_SIZE / 2.0, Vector2.ZERO, 6, PU_INFO[type].color)


func spawn_gem(at: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if at.x < 0.0:
		at = _random_field_spot(GEM_SIZE)
	gems.append({"pos": at.round(), "life": GEM_LIFE})
	_burst(at + Vector2.ONE * GEM_SIZE / 2.0, Vector2.ZERO, 5, GEM_COL)


func _random_field_spot(size: float) -> Vector2:
	return Vector2(rng.randf_range(80.0, W - 80.0 - size), rng.randf_range(TOP + 10.0, BOTTOM - 10.0 - size))


## Collision box for a pickup: POWER UP HITBOX around the item's center, bigger with BIG GRAB.
func pickup_rect(item_pos: Vector2, item_size: float, ball: Ball) -> Rect2:
	var box: float = tuning.get_value("pu_hitbox")
	if ball.last_touch >= 0:
		box += 4.0 * up(ball.last_touch, "grab")
	var center: Vector2 = item_pos + Vector2.ONE * item_size / 2.0
	return Rect2(center - Vector2.ONE * box / 2.0, Vector2.ONE * box)


func _check_pickups(ball: Ball) -> void:
	if ball.last_touch < 0:
		return
	var ball_rect := Rect2(ball.pos, Vector2(BALL, BALL))
	for i in range(powerups.size() - 1, -1, -1):
		var pu: Dictionary = powerups[i]
		if ball_rect.intersects(pickup_rect(pu.pos, PU_SIZE, ball)):
			powerups.remove_at(i)
			apply_powerup(pu.type, ball.last_touch, ball)
	# Gems only count for the player; balls the CPU hit fly through them.
	if ball.last_touch != 0:
		return
	for i in range(gems.size() - 1, -1, -1):
		if ball_rect.intersects(pickup_rect(gems[i].pos, GEM_SIZE, ball)):
			var value: int = 1 + run.stack("lucky")
			run.add_shards(value)
			_popup("+%d GEM" % value, gems[i].pos, GEM_COL)
			_burst(gems[i].pos, Vector2.ZERO, 10, GEM_COL)
			gems.remove_at(i)
			_play("gem")


## Gives a power-up to side (0 player, 1 CPU). ball is the ball that collected it, if any.
func apply_powerup(type: int, side: int, ball: Ball = null) -> void:
	var foe: int = 1 - side
	var duration: float = tuning.get_value("pu_duration")
	match type:
		PowerUp.FAST_BALL:
			if ball:
				ball.vel *= _boosted(1.35, side)
		PowerUp.MULTI_BALL:
			if ball:
				_split_ball(ball, -MULTI_SPREAD)
				_split_ball(ball, MULTI_SPREAD)
		PowerUp.BIG_PADDLE:
			_add_effect(side, "big", duration, side)
		PowerUp.FAST_PADDLE:
			_add_effect(side, "fast", duration, side)
		PowerUp.SHRINK_FOE:
			_add_effect(foe, "small", duration, side)
		PowerUp.SLOW_FOE:
			_add_effect(foe, "slow", duration, side)
		PowerUp.POISON:
			add_poison(foe, tuning.get_value("poison_pu") * boost(side))
		PowerUp.BOOSTER:
			_add_effect(side, "boost", tuning.get_value("booster_time"), side)
		PowerUp.WINGMAN:
			spawn_drone(side, true)
		PowerUp.TURRET:
			spawn_unit(side, true)
	var color: Color = PU_INFO[type].color
	var at: Vector2 = ball.pos if ball else Vector2(W / 2.0, H / 2.0)
	_burst(at, Vector2.ZERO, 14, color)
	_popup(PU_INFO[type].label, at + Vector2(0, -6), color)
	paddle_flash[side] = 0.15
	hitstop = maxf(hitstop, tuning.get_value("hitstop"))
	_shake(2.0)
	_play("power")


## src is the side that caused it, whose booster and upgrades set its strength.
func _add_effect(side: int, name: String, duration: float, src: int) -> void:
	effects[side][name] = {"t": duration, "total": duration, "src": src}
	_move_paddle(side, 0.0)


func _tick_paddle_effects(delta: float) -> void:
	for side in 2:
		for name in effects[side].keys():
			var e: Dictionary = effects[side][name]
			e.t -= delta
			if e.t <= 0.0:
				effects[side].erase(name)
		_move_paddle(side, 0.0)


# ---------------------------------------------------------------- effects

func _shake(amount: float) -> void:
	shake = maxf(shake, amount * tuning.get_value("shake"))


func _popup(text: String, at: Vector2, color: Color, life: float = 0.8) -> void:
	popups.append({"text": text, "pos": at, "life": life, "color": color})


func _burst(at: Vector2, dir: Vector2, count: int, color: Color) -> void:
	for i in count:
		var spread: Vector2 = dir.rotated(rng.randf_range(-1.1, 1.1)) if dir != Vector2.ZERO else Vector2.RIGHT.rotated(rng.randf() * TAU)
		particles.append({
			"pos": at,
			"vel": spread * rng.randf_range(40.0, 140.0),
			"life": rng.randf_range(0.15, 0.4),
			"color": color,
		})


func _update_effects(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 30.0)
	bg_flash = maxf(0.0, bg_flash - delta)
	for ball in balls:
		ball.squash = maxf(0.0, ball.squash - delta)
	for i in 2:
		paddle_flash[i] = maxf(0.0, paddle_flash[i] - delta)
		score_pop[i] = maxf(0.0, score_pop[i] - delta)
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.pos += p.vel * delta
		p.vel *= 0.86
		p.life -= delta
		if p.life <= 0.0:
			particles.remove_at(i)
	for i in range(popups.size() - 1, -1, -1):
		var popup: Dictionary = popups[i]
		popup.pos += Vector2(0.0, -20.0 * delta)
		popup.life -= delta
		if popup.life <= 0.0:
			popups.remove_at(i)


# ---------------------------------------------------------------- debug menu

func _menu_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for def in Tuning.DEFS:
		items.append({"kind": "value", "key": def.key, "label": def.label})
	items.append({"kind": "win_round", "label": "WIN THIS ROUND NOW"})
	items.append({"kind": "lose_round", "label": "LOSE THIS ROUND NOW"})
	items.append({"kind": "shop", "label": "OPEN SHOP NOW"})
	items.append({"kind": "gems", "label": "GIVE 20 GEMS"})
	items.append({"kind": "cpu_upgrade", "label": "GIVE CPU A RANDOM UPGRADE"})
	items.append({"kind": "poison_cpu", "label": "POISON THE CPU +5"})
	for id in Upgrades.DEFS:
		items.append({"kind": "upgrade", "id": id, "label": "ADD UPGRADE " + Upgrades.DEFS[id].name})
	for id in Relics.DEFS:
		items.append({"kind": "relic", "id": id, "label": "ADD RELIC " + Relics.DEFS[id].name})
	for type in PowerUp.values():
		items.append({"kind": "spawn", "type": type, "label": "SPAWN " + PU_INFO[type].label.trim_suffix("!")})
	items.append({"kind": "gem", "label": "SPAWN GEM SHARD"})
	items.append({"kind": "reset", "label": "RESET SETTINGS TO DEFAULTS"})
	items.append({"kind": "reset_save", "label": "RESET BEST AND GEMS"})
	items.append({"kind": "close", "label": "CLOSE"})
	return items


func _toggle_menu() -> void:
	menu_open = not menu_open
	# Fingers that were down when the menu opened or closed must not keep steering.
	button_touches.clear()
	swipe_index = -1
	pending_swipe = 0.0
	if not menu_open:
		if persist_tuning:
			tuning.save()
		for side in 2:
			_move_paddle(side, 0.0)
	_play("menu")


func _menu_key(key: InputEventKey) -> void:
	var steps: int = 5 if key.shift_pressed else 1
	match key.keycode:
		KEY_UP:
			_menu_action("up")
		KEY_DOWN:
			_menu_action("down")
		KEY_LEFT:
			_menu_action("dec", steps)
		KEY_RIGHT:
			_menu_action("inc", steps)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_menu_action("ok")
		KEY_ESCAPE:
			_menu_action("close")


## Shared by keys and touch: up, down, dec, inc, ok, close.
func _menu_action(action: String, steps: int = 1) -> void:
	var items := _menu_items()
	var item: Dictionary = items[menu_index]
	match action:
		"up":
			menu_index = wrapi(menu_index - 1, 0, items.size())
		"down":
			menu_index = wrapi(menu_index + 1, 0, items.size())
		"dec", "inc":
			if item.kind == "value":
				tuning.nudge(item.key, steps if action == "inc" else -steps)
		"ok":
			match item.kind:
				"spawn", "gem", "win_round", "lose_round", "shop":
					_toggle_menu()
					if item.kind == "spawn":
						spawn_powerup(item.type)
					elif item.kind == "gem":
						spawn_gem()
					elif item.kind == "shop":
						if state in [State.MAP, State.SERVE, State.PLAY]:
							_clear_field()
							run.shop_pending = true
							open_shop()
					elif in_round():
						_round_end(0 if item.kind == "win_round" else 1)
					return
				"gems":
					run.gems += 20
					run.save()
				"cpu_upgrade":
					var id: String = give_cpu_upgrade()
					if id != "":
						_popup("CPU GOT " + Upgrades.DEFS[id].name, Vector2(W / 2.0, 30.0), SIDE_COL[1])
				"poison_cpu":
					add_poison(1, 5.0)
				"upgrade":
					run.add(item.id)
					_popup(Upgrades.DEFS[item.id].name + " LV %d" % run.stack(item.id), Vector2(W / 2.0, 30.0), Upgrades.DEFS[item.id].color)
				"relic":
					if not run.has_relic(item.id):
						run.relics.append(item.id)
				"reset":
					tuning.reset()
				"reset_save":
					run.reset_save()
				"close":
					_toggle_menu()
					return
		"close":
			_toggle_menu()
			return
	_play("menu")


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var offset := Vector2.ZERO
	if shake > 0.0:
		offset = Vector2(rng.randi_range(-1, 1), rng.randi_range(-1, 1)) * ceilf(shake)
	draw_set_transform(offset)
	draw_rect(Rect2(-8, -8, W + 16, H + 16), BG_FLASH if bg_flash > 0.0 else BG)

	match state:
		State.TITLE:
			Screens.draw_title(self)
		State.MAP:
			Screens.draw_map(self)
		State.SHOP:
			Screens.draw_shop(self)
		State.UPGRADE:
			Screens.draw_upgrade(self)
		State.RUN_OVER:
			Screens.draw_run_over(self)
		_:
			_draw_court()

	for p in particles:
		var size: float = 2.0 if p.life > 0.2 else 1.0
		draw_rect(Rect2(p.pos.round(), Vector2(size, size)), p.color)
	for popup in popups:
		# Keep the whole label on screen even when it starts near an edge.
		var half: int = PixelFont.width(popup.text) / 2 + 2
		var x: int = clampi(int(popup.pos.x), half, W - half)
		PixelFont.draw(self, popup.text, x, maxi(int(popup.pos.y), TOP + 1), 1, popup.color, PixelFont.Align.CENTER)

	draw_set_transform(Vector2.ZERO)
	if can_pause() and not paused:
		_draw_pause_button()
	if paused:
		Screens.draw_pause(self)
	if menu_open:
		_draw_menu()


func _draw_pause_button() -> void:
	draw_rect(Rect2(3, 3, 2, 6), DIM)
	draw_rect(Rect2(7, 3, 2, 6), DIM)


func _draw_court() -> void:
	draw_rect(Rect2(0, TOP - 2, W, 2), DIM)
	draw_rect(Rect2(0, BOTTOM, W, 2), DIM)
	for y in range(TOP + 2, BOTTOM, 8):
		draw_rect(Rect2(W / 2 - 1, y, 2, 4), DIM)

	_draw_score(0, W / 2 - 19)
	_draw_score(1, W / 2 + 19)
	_draw_game_pips()
	_draw_poison_meters()
	_draw_effect_icons(0)
	_draw_effect_icons(1)

	if touch_buttons_on() and in_round():
		_draw_touch_button(TOUCH_UP, true, button_touches.values().has(-1.0))
		_draw_touch_button(TOUCH_DOWN, false, button_touches.values().has(1.0))

	for gem in gems:
		if gem.life > 2.0 or fmod(gem.life, 0.2) > 0.1:
			_draw_gem(gem.pos)
	for pu in powerups:
		if pu.life > 2.0 or fmod(pu.life, 0.2) > 0.1:
			_draw_powerup(pu.type, pu.pos)
	for u in units:
		_draw_unit(u)
	for d in drones:
		_draw_drone(d)

	for side in 2:
		_draw_paddle(side)

	match state:
		State.PLAY:
			for ball in balls:
				_draw_trail(ball)
			for ball in balls:
				_draw_ball(ball)
		State.SERVE:
			PixelFont.draw(self, banner, W / 2, 30, 1, BOSS_COL if is_boss() else MID, PixelFont.Align.CENTER)
			if fmod(serve_timer, 0.2) > 0.1:
				for ball in balls:
					_draw_ball(ball)
		State.ROUND_END:
			var text: String = "ROUND CLEAR!" if round_won else "ROUND LOST"
			var color: Color = SIDE_COL[0] if round_won else SIDE_COL[1]
			if fmod(transition, 0.3) > 0.08:
				PixelFont.draw(self, text, W / 2, 62, 3, color, PixelFont.Align.CENTER)


func _draw_drone(d: Dictionary) -> void:
	var color: Color = WHITE if d.flash > 0.0 else SIDE_COL[d.side].lerp(PU_INFO[PowerUp.WINGMAN].color, 0.5)
	var rect := Rect2(Vector2(d.x, d.y - DRONE_H / 2.0).round(), Vector2(DRONE_W, DRONE_H))
	draw_rect(rect, color)
	_draw_hp(Vector2(rect.position.x + DRONE_W / 2.0, rect.position.y - 3), d.hp, d.max_hp)


func _draw_unit(u: Dictionary) -> void:
	var color: Color = PU_INFO[PowerUp.TURRET].color if u.side == 0 else SIDE_COL[1]
	var reach: float = tuning.get_value("unit_range")
	if not u.alive:
		# Rubble plus a bar that fills as it rebuilds.
		var total: float = tuning.get_value("unit_respawn")
		draw_rect(Rect2(u.pos - Vector2(2, -1), Vector2(4, 2)), DIM)
		if not u.temp:
			draw_rect(Rect2(u.pos.x - 3, u.pos.y + 5, ceilf(6.0 * (1.0 - clampf(u.rebuild / total, 0.0, 1.0))), 1), DIM)
		return
	# Dotted ring showing how far the turret reaches.
	for i in 16:
		var a: float = TAU * i / 16.0 + blink * 0.6
		draw_rect(Rect2((u.pos + Vector2(cos(a), sin(a)) * reach).round(), Vector2.ONE), DIM)
	var rect := Rect2((u.pos - Vector2.ONE * UNIT_SIZE / 2.0).round(), Vector2.ONE * UNIT_SIZE)
	draw_rect(rect, WHITE if u.flash > 0.0 else color)
	draw_rect(rect.grow(-2), BG)
	_draw_hp(Vector2(u.pos.x, rect.position.y - 3), u.hp, u.max_hp)


## A row of tiny pips, one per hit point left.
func _draw_hp(center_top: Vector2, hp: int, max_hp: int) -> void:
	var x: float = roundf(center_top.x - (max_hp * 2 - 1) / 2.0)
	for i in max_hp:
		draw_rect(Rect2(x + i * 2, center_top.y, 1, 1), SPARK if i < hp else DIM)


## Poison meters below the game pips, shown once either side can poison.
func _draw_poison_meters() -> void:
	if poison[0] <= 0.0 and poison[1] <= 0.0 and level_of(0, "venom") == 0 and level_of(1, "venom") == 0:
		return
	var cap: float = tuning.get_value("poison_cap")
	for side in 2:
		var x: int = W / 2 - 48 if side == 0 else W / 2 + 32
		draw_rect(Rect2(x, 10, 16, 1), DIM)
		var fill: float = ceilf(16.0 * clampf(poison[side] / cap, 0.0, 1.0))
		if fill > 0.0:
			# Fill from the outside edge toward the score.
			draw_rect(Rect2(x + (16 - fill if side == 0 else 0), 10, fill, 1), upgrade_color("venom"))


## Games won this round as small squares beside each score.
func _draw_game_pips() -> void:
	for side in 2:
		for i in games_to_win():
			var x: int = (W / 2 - 34 - i * 5) if side == 0 else (W / 2 + 31 + i * 5)
			var rect := Rect2(x, 5, 3, 3)
			if i < run.games[side]:
				draw_rect(rect, SIDE_COL[side])
			else:
				draw_rect(rect, DIM)


func _draw_trail(ball: Ball) -> void:
	for i in ball.trail.size():
		var s: float = BALL - 1 - i * 0.5
		var c: Color = MID if i < 2 else DIM
		if ball.flame:
			c = upgrade_color("flame") if i < 2 else Color8(160, 48, 16)
		elif ball.slime:
			c = upgrade_color("slime") if i < 2 else Color8(48, 120, 32)
		elif ball.venom:
			c = upgrade_color("venom") if i < 2 else Color8(88, 48, 128)
		draw_rect(Rect2((ball.trail[i] + Vector2.ONE * (BALL - s) / 2.0).round(), Vector2(s, s).round()), c)


func _draw_ball(ball: Ball) -> void:
	var size := Vector2(BALL, BALL)
	if ball.squash > 0.0:
		size = Vector2(BALL - 2, BALL + 2) if absf(ball.vel.x) > absf(ball.vel.y) else Vector2(BALL + 2, BALL - 2)
	var center: Vector2 = ball.pos + Vector2(BALL, BALL) / 2.0
	var color: Color = WHITE
	if ball.flame and ball.slime:
		color = upgrade_color("flame") if fmod(blink, 0.2) < 0.1 else upgrade_color("slime")
	elif ball.flame:
		color = SPARK if fmod(blink, 0.12) < 0.06 else upgrade_color("flame")
	elif ball.slime:
		color = upgrade_color("slime")
	elif ball.venom:
		color = upgrade_color("venom")
	draw_rect(Rect2((center - size / 2.0).round(), size), color)


func _draw_paddle(side: int) -> void:
	var flash: bool = paddle_flash[side] > 0.0
	var kick: float = (2.0 if side == 1 else -2.0) if flash else 0.0
	var color: Color = WHITE if flash else SIDE_COL[side]
	if frozen[side] > 0.0:
		color = Color8(168, 216, 248) if fmod(blink, 0.16) < 0.12 else upgrade_color("venom")
	var rect := Rect2(Vector2(PADDLE_X[side] + kick, paddle_top(side)).round(), Vector2(PADDLE_W, paddle_height(side)))
	if effects[side].has("boost") and fmod(blink, 0.1) < 0.05:
		draw_rect(rect.grow(1), PU_INFO[PowerUp.BOOSTER].color)
	draw_rect(rect, color)
	# A 1px stripe in the effect's color while a paddle effect is active.
	if not effects[side].is_empty() and not flash:
		var stripe_x: float = rect.position.x + (PADDLE_W - 1 if side == 0 else 0)
		draw_rect(Rect2(stripe_x, rect.position.y, 1, rect.size.y), effect_color(effects[side].keys()[0]))
	if effects[side].has("burn") and rng.randf() < 0.4:
		particles.append({"pos": Vector2(rect.position.x + rng.randf_range(0, PADDLE_W), rect.position.y + rng.randf_range(0, rect.size.y)),
			"vel": Vector2(rng.randf_range(-8, 8), -30.0), "life": 0.3, "color": upgrade_color("flame")})


func upgrade_color(id: String) -> Color:
	return Upgrades.DEFS[id].color


func effect_color(name: String) -> Color:
	var info: Dictionary = EFFECT_INFO[name]
	return upgrade_color(info.upgrade) if info.has("upgrade") else PU_INFO[info.pu].color


func effect_icon(name: String) -> Array:
	var info: Dictionary = EFFECT_INFO[name]
	return Upgrades.DEFS[info.upgrade].icon if info.has("upgrade") else PU_INFO[info.pu].icon


## Outlined square with a pixel arrow; filled while held.
func _draw_touch_button(rect: Rect2, up: bool, held: bool) -> void:
	var color: Color = MID if held else DIM
	if held:
		draw_rect(rect, DIM)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1)), color)
	draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1, 0), Vector2(1, rect.size.y)), color)
	var center: Vector2 = (rect.position + rect.size / 2.0).floor()
	for row in 6:
		var half: int = row if up else 5 - row
		draw_rect(Rect2(center.x - half, center.y - 3 + row, half * 2 + 1, 1), WHITE if held else MID)


func _draw_powerup(type: int, pos: Vector2) -> void:
	# Solid color box with the icon cut out in the background color.
	draw_rect(Rect2(pos, Vector2(PU_SIZE, PU_SIZE)), PU_INFO[type].color)
	draw_icon(PU_INFO[type].icon, pos + Vector2.ONE, BG)


func _draw_gem(pos: Vector2) -> void:
	var rows: Array = ["00100", "01110", "11111", "01110", "00100"]
	draw_icon(rows, pos, GEM_COL)
	if fmod(blink, 0.6) < 0.15:
		draw_rect(Rect2(pos + Vector2(2, 1), Vector2.ONE), WHITE)


func draw_icon(rows: Array, pos: Vector2, color: Color, scale: int = 1) -> void:
	for row in 5:
		for col in 5:
			if rows[row][col] == "1":
				draw_rect(Rect2(pos.x + col * scale, pos.y + row * scale, scale, scale), color)


## Small icons with time bars in the HUD for each active paddle effect (left side starts after the pause button).
func _draw_effect_icons(side: int) -> void:
	var x: int = 16 if side == 0 else W - 9
	var step: int = 8 if side == 0 else -8
	for name in effects[side]:
		var color: Color = effect_color(name)
		draw_icon(effect_icon(name), Vector2(x, 2), color)
		var e: Dictionary = effects[side][name]
		draw_rect(Rect2(x, 9, ceilf(5.0 * clampf(e.t / e.total, 0.0, 1.0)), 1), color)
		x += step


func _draw_score(side: int, x: int) -> void:
	var pop: float = score_pop[side]
	var scale: int = 3 if pop > 0.0 else 2
	var y: int = 0 if pop > 0.0 else 2
	PixelFont.draw(self, str(scores[side]), x, y, scale, WHITE if pop > 0.15 else SIDE_COL[side], PixelFont.Align.CENTER)


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, W, H), BG)
	draw_rect(Rect2(0, 0, W, 9), DIM)
	PixelFont.draw(self, "DEBUG", 3, 2, 1, WHITE)
	PixelFont.draw(self, "F1 CLOSE", W - 3, 2, 1, MID, PixelFont.Align.RIGHT)

	var items := _menu_items()
	var rows: int = 18
	if menu_index < menu_scroll:
		menu_scroll = menu_index
	elif menu_index >= menu_scroll + rows:
		menu_scroll = menu_index - rows + 1
	for i in range(menu_scroll, mini(items.size(), menu_scroll + rows)):
		var item: Dictionary = items[i]
		var y: int = 12 + (i - menu_scroll) * 7
		var selected: bool = i == menu_index
		var color: Color = WHITE if selected else MID
		if selected:
			draw_rect(Rect2(0, y - 1, W, 7), DIM)
			PixelFont.draw(self, ">", 3, y, 1, SIDE_COL[0])
		var label_color: Color = color
		if selected and item.kind == "spawn":
			label_color = PU_INFO[item.type].color
		elif selected and item.kind == "upgrade":
			label_color = Upgrades.DEFS[item.id].color
		elif selected and item.kind == "relic":
			label_color = Relics.DEFS[item.id].color
		PixelFont.draw(self, item.label, 9, y, 1, label_color)
		if item.kind == "value":
			var text: String = tuning.format(item.key)
			if selected:
				text = "< " + text + " >"
			PixelFont.draw(self, text, W - 4, y, 1, SIDE_COL[0] if selected else color, PixelFont.Align.RIGHT)
		elif item.kind == "upgrade":
			PixelFont.draw(self, "LV %d" % run.stack(item.id), W - 4, y, 1, color, PixelFont.Align.RIGHT)
		elif item.kind == "relic":
			PixelFont.draw(self, "OWNED" if run.has_relic(item.id) else "-", W - 4, y, 1, color, PixelFont.Align.RIGHT)
		elif item.kind == "gems":
			PixelFont.draw(self, str(run.gems), W - 4, y, 1, GEM_COL, PixelFont.Align.RIGHT)
		elif item.kind == "cpu_upgrade":
			PixelFont.draw(self, str(run.cpu_stacks.values().reduce(func(a, b): return a + b, 0)), W - 4, y, 1, color, PixelFont.Align.RIGHT)
		elif item.kind == "poison_cpu":
			PixelFont.draw(self, "%d/%d" % [int(poison[1]), int(tuning.get_value("poison_cap"))], W - 4, y, 1, color, PixelFont.Align.RIGHT)

	if touch_seen:
		# Tappable button bar instead of the keyboard hint.
		var bw: int = W / MENU_BUTTONS.size()
		for i in MENU_BUTTONS.size():
			var rect := Rect2(i * bw, H - MENU_BAR_H, bw - 1, MENU_BAR_H)
			draw_rect(rect, DIM)
			PixelFont.draw(self, MENU_BUTTONS[i], int(rect.position.x + bw / 2), H - MENU_BAR_H + 4, 1, WHITE, PixelFont.Align.CENTER)
		return
	draw_rect(Rect2(0, H - 9, W, 9), DIM)
	var hint: String = "UP/DOWN PICK  LEFT/RIGHT CHANGE  SHIFT X5"
	if items[menu_index].kind != "value":
		hint = "UP/DOWN PICK  ENTER SELECT"
	PixelFont.draw(self, hint, W / 2, H - 7, 1, WHITE, PixelFont.Align.CENTER)


# ---------------------------------------------------------------- audio

func _make_blip(freq: float, duration: float) -> AudioStreamPlayer:
	var rate: int = 22050
	var count: int = int(rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	var period: float = rate / freq
	for i in count:
		var fade: float = 1.0 - float(i) / count
		var v: int = int((36 if fmod(i, period) < period / 2.0 else -36) * fade)
		data[i] = v & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	var player := AudioStreamPlayer.new()
	player.stream = wav
	add_child(player)
	return player


func _play(name: String) -> void:
	var player: AudioStreamPlayer = sfx.get(name)
	if player and player.is_inside_tree():
		player.play()
