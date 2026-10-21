extends Node2D
## GBA-style Pong at 240x160. Everything is drawn with flat rects from a small palette.

enum State { TITLE, SERVE, PLAY, OVER }

const W := 240
const H := 160
const TOP := 14
const BOTTOM := 156
const PADDLE_W := 4
const PADDLE_H := 24
const PLAYER_X := 8
const CPU_X := W - 8 - PADDLE_W
const BALL := 4
const PLAYER_SPEED := 150.0
const CPU_SPEED := 98.0
const BALL_START := 110.0
const BALL_ACCEL := 9.0
const BALL_MAX := 250.0
const MAX_BOUNCE_ANGLE := deg_to_rad(55.0)
const WIN_SCORE := 7
const SERVE_DELAY := 0.7
const HITSTOP := 0.05

# 15-bit-friendly palette (every channel a multiple of 8).
const BG := Color8(8, 8, 24)
const BG_FLASH := Color8(40, 56, 112)
const DIM := Color8(40, 56, 112)
const MID := Color8(88, 120, 200)
const WHITE := Color8(248, 248, 248)
const PLAYER_COL := Color8(248, 176, 48)
const CPU_COL := Color8(248, 72, 112)
const SPARK := Color8(248, 248, 160)

const FONT := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
	"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"], "G": ["011", "100", "101", "101", "011"],
	"I": ["111", "010", "010", "010", "111"], "N": ["101", "111", "111", "101", "101"],
	"O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
	"R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
	"U": ["101", "101", "101", "101", "111"], "W": ["101", "101", "111", "111", "101"],
	"Y": ["101", "101", "010", "010", "010"], " ": ["000", "000", "000", "000", "000"],
}

var state: State = State.TITLE
var player_y: float = (H - PADDLE_H) / 2.0
var cpu_y: float = (H - PADDLE_H) / 2.0
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var scores: Array[int] = [0, 0]
var serve_dir: int = 1
var serve_timer: float = 0.0
var cpu_aim_error: float = 0.0

# Effects
var hitstop: float = 0.0
var shake: float = 0.0
var bg_flash: float = 0.0
var paddle_flash: Array[float] = [0.0, 0.0]
var score_pop: Array[float] = [0.0, 0.0]
var squash: float = 0.0
var trail: Array[Vector2] = []
var particles: Array[Dictionary] = []
var blink: float = 0.0
var rng := RandomNumberGenerator.new()

var sfx := {}


func _ready() -> void:
	rng.randomize()
	sfx["paddle"] = _make_blip(880.0, 0.05)
	sfx["wall"] = _make_blip(440.0, 0.03)
	sfx["score"] = _make_blip(196.0, 0.2)
	sfx["serve"] = _make_blip(660.0, 0.04)
	_reset_ball()


func _process(delta: float) -> void:
	var dir: float = Input.get_axis("ui_up", "ui_down")
	if state == State.TITLE or state == State.OVER:
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
			start_match()
	simulate(delta, dir)
	queue_redraw()


## Advances the game by delta seconds. dir is the player's input: -1 up, 1 down, 0 none.
func simulate(delta: float, dir: float) -> void:
	blink += delta
	_update_effects(delta)
	if hitstop > 0.0:
		hitstop -= delta
		return

	player_y = clampf(player_y + dir * PLAYER_SPEED * delta, TOP, BOTTOM - PADDLE_H)
	_update_cpu(delta)

	match state:
		State.SERVE:
			serve_timer -= delta
			if serve_timer <= 0.0:
				_launch_ball()
		State.PLAY:
			_move_ball(delta)


func start_match() -> void:
	scores = [0, 0]
	serve_dir = 1 if rng.randf() < 0.5 else -1
	_begin_serve()


func _begin_serve() -> void:
	state = State.SERVE
	serve_timer = SERVE_DELAY
	_reset_ball()


func _reset_ball() -> void:
	ball_pos = Vector2((W - BALL) / 2.0, (H - BALL) / 2.0)
	ball_vel = Vector2.ZERO
	trail.clear()


func _launch_ball() -> void:
	state = State.PLAY
	var angle: float = rng.randf_range(-0.4, 0.4)
	ball_vel = Vector2(cos(angle) * serve_dir, sin(angle)) * BALL_START
	_play("serve")


func _update_cpu(delta: float) -> void:
	var target: float = (H - PADDLE_H) / 2.0
	if state == State.PLAY and ball_vel.x > 0.0:
		target = ball_pos.y + BALL / 2.0 - PADDLE_H / 2.0 + cpu_aim_error
	var step: float = CPU_SPEED * delta
	cpu_y = clampf(cpu_y + clampf(target - cpu_y, -step, step), TOP, BOTTOM - PADDLE_H)


# Moves in small steps so a fast ball can't pass through a paddle.
func _move_ball(delta: float) -> void:
	var motion: Vector2 = ball_vel * delta
	var steps: int = maxi(1, ceili(motion.length() / 2.0))
	for i in steps:
		ball_pos += motion / steps
		if _collide():
			return
	trail.push_front(ball_pos)
	if trail.size() > 5:
		trail.pop_back()


## Handles walls, paddles and goals. Returns true when the rest of this frame's motion should stop.
func _collide() -> bool:
	if ball_pos.y < TOP:
		ball_pos.y = TOP
		ball_vel.y = absf(ball_vel.y)
		_wall_hit()
	elif ball_pos.y > BOTTOM - BALL:
		ball_pos.y = BOTTOM - BALL
		ball_vel.y = -absf(ball_vel.y)
		_wall_hit()

	if ball_vel.x < 0.0 and _overlaps_paddle(PLAYER_X, player_y):
		ball_pos.x = PLAYER_X + PADDLE_W
		_paddle_hit(0, player_y, 1.0)
		return true
	if ball_vel.x > 0.0 and _overlaps_paddle(CPU_X, cpu_y):
		ball_pos.x = CPU_X - BALL
		_paddle_hit(1, cpu_y, -1.0)
		return true

	if ball_pos.x + BALL < 0.0:
		_goal(1)
		return true
	if ball_pos.x > W:
		_goal(0)
		return true
	return false


func _overlaps_paddle(px: float, py: float) -> bool:
	return ball_pos.x < px + PADDLE_W and ball_pos.x + BALL > px \
		and ball_pos.y < py + PADDLE_H and ball_pos.y + BALL > py


func _paddle_hit(side: int, py: float, dir_x: float) -> void:
	var offset: float = clampf((ball_pos.y + BALL / 2.0 - (py + PADDLE_H / 2.0)) / (PADDLE_H / 2.0), -1.0, 1.0)
	var speed: float = minf(ball_vel.length() + BALL_ACCEL, BALL_MAX)
	var angle: float = offset * MAX_BOUNCE_ANGLE
	ball_vel = Vector2(cos(angle) * dir_x, sin(angle)) * speed
	if side == 0:
		cpu_aim_error = rng.randf_range(-10.0, 10.0)
	hitstop = HITSTOP
	shake = maxf(shake, 2.0)
	squash = 0.08
	paddle_flash[side] = 0.1
	_burst(ball_pos + Vector2(BALL / 2.0, BALL / 2.0), Vector2(dir_x, 0.0), 8, SPARK)
	_play("paddle")


func _wall_hit() -> void:
	shake = maxf(shake, 1.0)
	_burst(ball_pos + Vector2(BALL / 2.0, BALL / 2.0), Vector2(0.0, signf(ball_vel.y)), 4, MID)
	_play("wall")


func _goal(scorer: int) -> void:
	scores[scorer] += 1
	score_pop[scorer] = 0.3
	shake = 5.0
	bg_flash = 0.08
	var edge_x: float = 0.0 if scorer == 1 else float(W)
	_burst(Vector2(edge_x, ball_pos.y), Vector2(1.0 if scorer == 1 else -1.0, 0.0), 18, PLAYER_COL if scorer == 0 else CPU_COL)
	_play("score")
	serve_dir = -1 if scorer == 0 else 1
	if scores[scorer] >= WIN_SCORE:
		state = State.OVER
		_reset_ball()
	else:
		_begin_serve()


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
	squash = maxf(0.0, squash - delta)
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

	_draw_score(scores[0], W / 2 - 22, PLAYER_COL, score_pop[0])
	_draw_score(scores[1], W / 2 + 16, CPU_COL, score_pop[1])

	_draw_paddle(PLAYER_X, player_y, PLAYER_COL, paddle_flash[0], -1)
	_draw_paddle(CPU_X, cpu_y, CPU_COL, paddle_flash[1], 1)

	for p in particles:
		var size: float = 2.0 if p.life > 0.2 else 1.0
		draw_rect(Rect2(p.pos.round(), Vector2(size, size)), p.color)

	match state:
		State.PLAY:
			for i in trail.size():
				var s: float = BALL - 1 - i * 0.5
				var c: Color = MID if i < 2 else DIM
				draw_rect(Rect2((trail[i] + Vector2.ONE * (BALL - s) / 2.0).round(), Vector2(s, s).round()), c)
			_draw_ball()
		State.SERVE:
			if fmod(serve_timer, 0.2) > 0.1:
				_draw_ball()
		State.TITLE:
			_draw_text("GBA PONG", W / 2, 50, 3, WHITE)
			if fmod(blink, 0.8) < 0.5:
				_draw_text("PRESS UP OR DOWN", W / 2, 100, 1, MID)
		State.OVER:
			var won: bool = scores[0] > scores[1]
			_draw_text("YOU WIN" if won else "CPU WINS", W / 2, 55, 2, PLAYER_COL if won else CPU_COL)
			if fmod(blink, 0.8) < 0.5:
				_draw_text("PRESS UP OR DOWN", W / 2, 100, 1, MID)


func _draw_ball() -> void:
	var size := Vector2(BALL, BALL)
	if squash > 0.0:
		size = Vector2(BALL - 2, BALL + 2) if absf(ball_vel.x) > absf(ball_vel.y) else Vector2(BALL + 2, BALL - 2)
	var center: Vector2 = ball_pos + Vector2(BALL, BALL) / 2.0
	draw_rect(Rect2((center - size / 2.0).round(), size), WHITE)


func _draw_paddle(x: float, y: float, color: Color, flash: float, kick_dir: int) -> void:
	var kick: float = kick_dir * 2.0 if flash > 0.0 else 0.0
	draw_rect(Rect2(Vector2(x + kick, y).round(), Vector2(PADDLE_W, PADDLE_H)), WHITE if flash > 0.0 else color)


func _draw_score(value: int, x: int, color: Color, pop: float) -> void:
	var scale: int = 3 if pop > 0.0 else 2
	var y: int = 2 if pop > 0.0 else 3
	_draw_text(str(value), x + 3, y, scale, WHITE if pop > 0.15 else color)


## Draws centered text with the 3x5 pixel font, each font pixel scale x scale screen pixels.
func _draw_text(text: String, center_x: int, y: int, scale: int, color: Color) -> void:
	var width: int = text.length() * 4 * scale - scale
	var x: int = center_x - width / 2
	for ch in text:
		var glyph: Array = FONT.get(ch, FONT[" "])
		for row in 5:
			for col in 3:
				if glyph[row][col] == "1":
					draw_rect(Rect2(x + col * scale, y + row * scale, scale, scale), color)
		x += 4 * scale


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
