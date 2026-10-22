extends Node2D
## GBA-style Pong at 240x160 with power-ups and a debug menu (F1 or `).
## Everything is drawn with flat rects from a small palette.

const Tuning := preload("res://scripts/tuning.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Ball := preload("res://scripts/ball.gd")

enum State { TITLE, SERVE, PLAY, OVER }
enum PowerUp { FAST_BALL, MULTI_BALL, BIG_PADDLE, FAST_PADDLE, SHRINK_FOE, SLOW_FOE }

const W := 240
const H := 160
const TOP := 14
const BOTTOM := 156
const PADDLE_W := 4
const PADDLE_X: Array[int] = [8, W - 8 - PADDLE_W]
const BALL := 4
const PU_SIZE := 7
const PU_LIFE := 9.0
const MULTI_SPREAD := 0.35

# 15-bit-friendly palette (every channel a multiple of 8).
const BG := Color8(8, 8, 24)
const BG_FLASH := Color8(40, 56, 112)
const DIM := Color8(40, 56, 112)
const MID := Color8(88, 120, 200)
const WHITE := Color8(248, 248, 248)
const SIDE_COL: Array[Color] = [Color8(248, 176, 48), Color8(248, 72, 112)]
const SPARK := Color8(248, 248, 160)

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
}
## Timed effects on a paddle: name -> [size multiplier, speed multiplier].
const EFFECTS := {
	"big": [1.5, 1.0], "small": [0.6, 1.0], "fast": [1.0, 1.5], "slow": [1.0, 0.6],
}
const EFFECT_ICON := {
	"big": PowerUp.BIG_PADDLE, "small": PowerUp.SHRINK_FOE, "fast": PowerUp.FAST_PADDLE, "slow": PowerUp.SLOW_FOE,
}

var tuning := Tuning.new()
var state: State = State.TITLE
var paddle_cy: Array[float] = [H / 2.0, H / 2.0]
var effects: Array[Dictionary] = [{}, {}]
var balls: Array[Ball] = []
var scores: Array[int] = [0, 0]
var serve_dir: int = 1
var serve_timer: float = 0.0
var cpu_aim_error: float = 0.0
var powerups: Array[Dictionary] = []
var pu_timer: float = 0.0

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

var sfx := {}


func _ready() -> void:
	rng.randomize()
	tuning.load_saved()
	sfx["paddle"] = _make_blip(880.0, 0.05)
	sfx["wall"] = _make_blip(440.0, 0.03)
	sfx["score"] = _make_blip(196.0, 0.2)
	sfx["serve"] = _make_blip(660.0, 0.04)
	sfx["power"] = _make_blip(1320.0, 0.09)
	sfx["menu"] = _make_blip(990.0, 0.02)


func _process(delta: float) -> void:
	blink += delta
	if not menu_open:
		if state == State.TITLE or state == State.OVER:
			if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
				start_match()
		simulate(delta, Input.get_axis("ui_up", "ui_down"))
	queue_redraw()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_F1 or key.keycode == KEY_QUOTELEFT:
		if not key.echo:
			_toggle_menu()
		get_viewport().set_input_as_handled()
	elif menu_open:
		_menu_key(key)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- simulation

## Advances the game by delta seconds. dir is the player's input: -1 up, 1 down, 0 none.
func simulate(delta: float, dir: float) -> void:
	_update_effects(delta)
	if hitstop > 0.0:
		hitstop -= delta
		return

	_move_paddle(0, dir * paddle_speed(0) * delta)
	_update_cpu(delta)

	match state:
		State.SERVE:
			_tick_paddle_effects(delta)
			serve_timer -= delta
			if serve_timer <= 0.0:
				_launch_ball()
		State.PLAY:
			_tick_paddle_effects(delta)
			_update_powerups(delta)
			for ball in balls.duplicate():
				_move_ball(ball, delta)


func start_match() -> void:
	scores = [0, 0]
	effects = [{}, {}]
	powerups.clear()
	pu_timer = tuning.get_value("pu_interval")
	serve_dir = 1 if rng.randf() < 0.5 else -1
	_begin_serve()


func paddle_height(side: int) -> float:
	var h: float = tuning.get_value("paddle_h")
	for name in effects[side]:
		h *= EFFECTS[name][0]
	return clampf(roundf(h), 4.0, BOTTOM - TOP)


func paddle_speed(side: int) -> float:
	var s: float = tuning.get_value("player_speed" if side == 0 else "cpu_speed")
	for name in effects[side]:
		s *= EFFECTS[name][1]
	return s


func paddle_top(side: int) -> float:
	return paddle_cy[side] - paddle_height(side) / 2.0


func _move_paddle(side: int, amount: float) -> void:
	var half: float = paddle_height(side) / 2.0
	paddle_cy[side] = clampf(paddle_cy[side] + amount, TOP + half, BOTTOM - half)


func _begin_serve() -> void:
	state = State.SERVE
	serve_timer = tuning.get_value("serve_delay")
	var ball := Ball.new()
	ball.pos = Vector2((W - BALL) / 2.0, (H - BALL) / 2.0)
	balls = [ball]


func _launch_ball() -> void:
	state = State.PLAY
	var angle: float = rng.randf_range(-0.4, 0.4)
	balls[0].vel = Vector2(cos(angle) * serve_dir, sin(angle)) * tuning.get_value("ball_start")
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


## Handles walls, paddles, power-ups and goals. Returns true when this ball's motion should stop.
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
		_paddle_hit(ball, 0)
		return true
	if ball.vel.x > 0.0 and _overlaps_paddle(ball, 1):
		ball.pos.x = PADDLE_X[1] - BALL
		_paddle_hit(ball, 1)
		return true

	_check_pickups(ball)

	if ball.pos.x + BALL < 0.0:
		_goal(ball, 1)
		return true
	if ball.pos.x > W:
		_goal(ball, 0)
		return true
	return false


func _overlaps_paddle(ball: Ball, side: int) -> bool:
	var top: float = paddle_top(side)
	return ball.pos.x < PADDLE_X[side] + PADDLE_W and ball.pos.x + BALL > PADDLE_X[side] \
		and ball.pos.y < top + paddle_height(side) and ball.pos.y + BALL > top


func _paddle_hit(ball: Ball, side: int) -> void:
	var half: float = paddle_height(side) / 2.0
	var offset: float = clampf((ball.pos.y + BALL / 2.0 - paddle_cy[side]) / half, -1.0, 1.0)
	var speed: float = minf(ball.vel.length() + tuning.get_value("ball_accel"), maxf(tuning.get_value("ball_max"), ball.vel.length()))
	var angle: float = offset * deg_to_rad(tuning.get_value("bounce_angle"))
	var dir_x: float = 1.0 if side == 0 else -1.0
	ball.vel = Vector2(cos(angle) * dir_x, sin(angle)) * speed
	ball.last_touch = side
	ball.squash = 0.08
	if side == 0:
		var err: float = tuning.get_value("cpu_error")
		cpu_aim_error = rng.randf_range(-err, err)
	hitstop = tuning.get_value("hitstop")
	_shake(2.0)
	paddle_flash[side] = 0.1
	_burst(ball.pos + Vector2.ONE * BALL / 2.0, Vector2(dir_x, 0.0), 8, SPARK)
	_play("paddle")


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
	if scores[scorer] >= int(tuning.get_value("win_score")):
		state = State.OVER
		balls.clear()
		powerups.clear()
	elif balls.is_empty():
		_begin_serve()


# ---------------------------------------------------------------- power-ups

func _update_powerups(delta: float) -> void:
	for i in range(powerups.size() - 1, -1, -1):
		var pu: Dictionary = powerups[i]
		pu.life -= delta
		if pu.life <= 0.0:
			powerups.remove_at(i)
	if tuning.get_value("powerups") < 1.0:
		return
	pu_timer -= delta
	if pu_timer <= 0.0:
		pu_timer = tuning.get_value("pu_interval") * rng.randf_range(0.7, 1.3)
		if powerups.size() < int(tuning.get_value("pu_max")):
			spawn_powerup(rng.randi_range(0, PowerUp.size() - 1))


## Places a power-up somewhere in the middle of the court.
func spawn_powerup(type: int, at: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if at.x < 0.0:
		at = Vector2(rng.randf_range(60.0, W - 60.0 - PU_SIZE), rng.randf_range(TOP + 10.0, BOTTOM - 10.0 - PU_SIZE))
	powerups.append({"type": type, "pos": at.round(), "life": PU_LIFE})
	_burst(at + Vector2.ONE * PU_SIZE / 2.0, Vector2.ZERO, 6, PU_INFO[type].color)


func _check_pickups(ball: Ball) -> void:
	if ball.last_touch < 0:
		return
	for i in range(powerups.size() - 1, -1, -1):
		var pu: Dictionary = powerups[i]
		if Rect2(ball.pos, Vector2(BALL, BALL)).intersects(Rect2(pu.pos, Vector2(PU_SIZE, PU_SIZE))):
			powerups.remove_at(i)
			apply_powerup(pu.type, ball.last_touch, ball)


## Gives a power-up to side (0 player, 1 CPU). ball is the ball that collected it, if any.
func apply_powerup(type: int, side: int, ball: Ball = null) -> void:
	var foe: int = 1 - side
	var duration: float = tuning.get_value("pu_duration")
	match type:
		PowerUp.FAST_BALL:
			if ball:
				ball.vel *= 1.35
		PowerUp.MULTI_BALL:
			if ball:
				for turn in [-MULTI_SPREAD, MULTI_SPREAD]:
					if balls.size() >= int(tuning.get_value("max_balls")):
						break
					var extra := Ball.new()
					extra.pos = ball.pos
					extra.vel = ball.vel.rotated(turn)
					extra.last_touch = ball.last_touch
					balls.append(extra)
		PowerUp.BIG_PADDLE:
			effects[side]["big"] = duration
		PowerUp.FAST_PADDLE:
			effects[side]["fast"] = duration
		PowerUp.SHRINK_FOE:
			effects[foe]["small"] = duration
		PowerUp.SLOW_FOE:
			effects[foe]["slow"] = duration
	for s in 2:
		_move_paddle(s, 0.0)
	var color: Color = PU_INFO[type].color
	var at: Vector2 = ball.pos if ball else Vector2(W / 2.0, H / 2.0)
	_burst(at, Vector2.ZERO, 14, color)
	popups.append({"text": PU_INFO[type].label, "pos": at + Vector2(0, -6), "life": 0.8, "color": color})
	paddle_flash[side] = 0.15
	hitstop = maxf(hitstop, tuning.get_value("hitstop"))
	_shake(2.0)
	_play("power")


func _tick_paddle_effects(delta: float) -> void:
	for side in 2:
		for name in effects[side].keys():
			effects[side][name] -= delta
			if effects[side][name] <= 0.0:
				effects[side].erase(name)
		_move_paddle(side, 0.0)


# ---------------------------------------------------------------- effects

func _shake(amount: float) -> void:
	shake = maxf(shake, amount * tuning.get_value("shake"))


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
	for type in PowerUp.values():
		items.append({"kind": "spawn", "type": type, "label": "SPAWN " + PU_INFO[type].label.trim_suffix("!")})
	items.append({"kind": "reset", "label": "RESET ALL TO DEFAULTS"})
	items.append({"kind": "close", "label": "CLOSE"})
	return items


func _toggle_menu() -> void:
	menu_open = not menu_open
	if not menu_open:
		tuning.save()
		for side in 2:
			_move_paddle(side, 0.0)
	_play("menu")


func _menu_key(key: InputEventKey) -> void:
	var items := _menu_items()
	var item: Dictionary = items[menu_index]
	var steps: int = 5 if key.shift_pressed else 1
	match key.keycode:
		KEY_UP:
			menu_index = wrapi(menu_index - 1, 0, items.size())
		KEY_DOWN:
			menu_index = wrapi(menu_index + 1, 0, items.size())
		KEY_LEFT, KEY_RIGHT:
			if item.kind == "value":
				tuning.nudge(item.key, steps if key.keycode == KEY_RIGHT else -steps)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			match item.kind:
				"spawn":
					spawn_powerup(item.type)
					_toggle_menu()
					return
				"reset":
					tuning.reset()
				"close":
					_toggle_menu()
					return
		KEY_ESCAPE:
			_toggle_menu()
			return
		_:
			return
	_play("menu")


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var offset := Vector2.ZERO
	if shake > 0.0:
		offset = Vector2(rng.randi_range(-1, 1), rng.randi_range(-1, 1)) * ceilf(shake)
	draw_set_transform(offset)

	draw_rect(Rect2(-8, -8, W + 16, H + 16), BG_FLASH if bg_flash > 0.0 else BG)
	draw_rect(Rect2(0, TOP - 2, W, 2), DIM)
	draw_rect(Rect2(0, BOTTOM, W, 2), DIM)
	if state == State.SERVE or state == State.PLAY:
		for y in range(TOP + 2, BOTTOM, 8):
			draw_rect(Rect2(W / 2 - 1, y, 2, 4), DIM)

	_draw_score(0, W / 2 - 19)
	_draw_score(1, W / 2 + 19)
	_draw_effect_icons(0)
	_draw_effect_icons(1)

	for pu in powerups:
		if pu.life > 2.0 or fmod(pu.life, 0.2) > 0.1:
			_draw_powerup(pu.type, pu.pos)

	for side in 2:
		_draw_paddle(side)

	for p in particles:
		var size: float = 2.0 if p.life > 0.2 else 1.0
		draw_rect(Rect2(p.pos.round(), Vector2(size, size)), p.color)

	match state:
		State.PLAY:
			for ball in balls:
				_draw_trail(ball)
			for ball in balls:
				_draw_ball(ball)
		State.SERVE:
			if fmod(serve_timer, 0.2) > 0.1:
				for ball in balls:
					_draw_ball(ball)
		State.TITLE:
			PixelFont.draw(self, "GBA PONG", W / 2, 46, 3, WHITE, PixelFont.Align.CENTER)
			if fmod(blink, 0.8) < 0.5:
				PixelFont.draw(self, "PRESS UP OR DOWN", W / 2, 96, 1, MID, PixelFont.Align.CENTER)
			PixelFont.draw(self, "F1 DEBUG", W / 2, 140, 1, DIM, PixelFont.Align.CENTER)
		State.OVER:
			var won: bool = scores[0] > scores[1]
			PixelFont.draw(self, "YOU WIN" if won else "CPU WINS", W / 2, 55, 2, SIDE_COL[0] if won else SIDE_COL[1], PixelFont.Align.CENTER)
			if fmod(blink, 0.8) < 0.5:
				PixelFont.draw(self, "PRESS UP OR DOWN", W / 2, 96, 1, MID, PixelFont.Align.CENTER)

	for popup in popups:
		# Keep the whole label on screen even when the pickup happened near an edge.
		var half: int = PixelFont.width(popup.text) / 2 + 2
		var x: int = clampi(int(popup.pos.x), half, W - half)
		PixelFont.draw(self, popup.text, x, maxi(int(popup.pos.y), TOP + 1), 1, popup.color, PixelFont.Align.CENTER)

	draw_set_transform(Vector2.ZERO)
	if menu_open:
		_draw_menu()


func _draw_trail(ball: Ball) -> void:
	for i in ball.trail.size():
		var s: float = BALL - 1 - i * 0.5
		var c: Color = MID if i < 2 else DIM
		draw_rect(Rect2((ball.trail[i] + Vector2.ONE * (BALL - s) / 2.0).round(), Vector2(s, s).round()), c)


func _draw_ball(ball: Ball) -> void:
	var size := Vector2(BALL, BALL)
	if ball.squash > 0.0:
		size = Vector2(BALL - 2, BALL + 2) if absf(ball.vel.x) > absf(ball.vel.y) else Vector2(BALL + 2, BALL - 2)
	var center: Vector2 = ball.pos + Vector2(BALL, BALL) / 2.0
	draw_rect(Rect2((center - size / 2.0).round(), size), WHITE)


func _draw_paddle(side: int) -> void:
	var flash: bool = paddle_flash[side] > 0.0
	var kick: float = (2.0 if side == 1 else -2.0) if flash else 0.0
	var color: Color = WHITE if flash else SIDE_COL[side]
	var rect := Rect2(Vector2(PADDLE_X[side] + kick, paddle_top(side)).round(), Vector2(PADDLE_W, paddle_height(side)))
	draw_rect(rect, color)
	# A 1px stripe in the effect's color while a paddle effect is active.
	if not effects[side].is_empty() and not flash:
		var effect: String = effects[side].keys()[0]
		var stripe_x: float = rect.position.x + (PADDLE_W - 1 if side == 0 else 0)
		draw_rect(Rect2(stripe_x, rect.position.y, 1, rect.size.y), PU_INFO[EFFECT_ICON[effect]].color)


func _draw_powerup(type: int, pos: Vector2) -> void:
	var color: Color = PU_INFO[type].color
	# Solid color box with the icon cut out in the background color.
	draw_rect(Rect2(pos, Vector2(PU_SIZE, PU_SIZE)), color)
	_draw_icon(type, pos + Vector2.ONE, BG)


func _draw_icon(type: int, pos: Vector2, color: Color) -> void:
	var icon: Array = PU_INFO[type].icon
	for row in 5:
		for col in 5:
			if icon[row][col] == "1":
				draw_rect(Rect2(pos.x + col, pos.y + row, 1, 1), color)


## Small icons with time bars in the HUD for each active paddle effect.
func _draw_effect_icons(side: int) -> void:
	var x: int = 4 if side == 0 else W - 9
	var step: int = 8 if side == 0 else -8
	var total: float = tuning.get_value("pu_duration")
	for name in effects[side]:
		var type: int = EFFECT_ICON[name]
		var color: Color = PU_INFO[type].color
		_draw_icon(type, Vector2(x, 2), color)
		draw_rect(Rect2(x, 9, ceilf(5.0 * clampf(effects[side][name] / total, 0.0, 1.0)), 1), color)
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
		if item.kind == "spawn":
			label_color = PU_INFO[item.type].color if selected else MID
		PixelFont.draw(self, item.label, 9, y, 1, label_color)
		if item.kind == "value":
			var text: String = tuning.format(item.key)
			if selected:
				text = "< " + text + " >"
			PixelFont.draw(self, text, W - 4, y, 1, SIDE_COL[0] if selected else color, PixelFont.Align.RIGHT)

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
