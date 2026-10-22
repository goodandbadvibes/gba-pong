extends SceneTree
## Rule checks for scenes/main.gd, driven through simulate() and _input() without rendering.

const Ball := preload("res://scripts/ball.gd")
const Upgrades := preload("res://scripts/upgrades.gd")

var failures: int = 0


func _initialize() -> void:
	# Court rules
	_test_paddle_hit_reverses_and_speeds_up()
	_test_wall_bounce()
	_test_point_scores_and_serves()
	_test_balls_never_leave_court()
	_test_tuning_changes_paddle_speed()
	# Power-ups
	_test_pickup_goes_to_last_toucher()
	_test_untouched_ball_ignores_pickups()
	_test_hitbox_setting()
	_test_shrink_hits_the_foe()
	_test_multi_ball_respects_max()
	_test_goal_with_balls_left_keeps_playing()
	_test_effects_expire()
	# Games, rounds and the run
	_test_game_win_resets_points()
	_test_round_win_offers_upgrades_and_advances_map()
	_test_round_loss_ends_run_and_banks_gems()
	_test_difficulty_scales_with_level_and_boss()
	# Upgrades
	_test_long_and_swift()
	_test_flame_burns_cpu_paddle_then_recovers()
	_test_slime_slows_cpu()
	_test_magnet_pulls_pickups()
	_test_gems_only_for_player()
	_test_power_hit()
	_test_offers_skip_maxed()
	# Touch
	_test_tap_flow_title_map_round()
	_test_swipe_moves_paddle()
	_test_slow_effect_scales_swipe()
	_test_touch_buttons()
	_test_tap_top_opens_menu_and_bar_buttons_work()
	_test_upgrade_cards_by_touch()
	print("test_rules: %s" % ("FAILED" if failures else "all passed"))
	quit(1 if failures else 0)


# ---------------------------------------------------------------- helpers

func _new_game() -> Node2D:
	var game: Node2D = load("res://scenes/main.gd").new()
	game.persist_tuning = false
	root.add_child(game)
	game.tuning.reset()
	game.tuning.set_value("powerups", 0.0)
	game.tuning.set_value("gem_interval", 30.0)
	return game


## A game in a round (SERVE state) at level 1.
func _game() -> Node2D:
	var game := _new_game()
	game.start_run()
	game.start_round()
	return game


func _playing(game: Node2D, pos: Vector2, vel: Vector2, last_touch: int = -1) -> Ball:
	var ball := Ball.new()
	ball.pos = pos
	ball.vel = vel
	ball.last_touch = last_touch
	game.balls.assign([ball])
	game.state = game.State.PLAY
	return ball


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func _step(game: Node2D, frames: int, dir: float = 0.0) -> void:
	for i in frames:
		game.simulate(1.0 / 60.0, dir)


func _score_point(game: Node2D, scorer: int) -> void:
	if scorer == 1:
		game.paddle_cy[0] = 30.0
		_playing(game, Vector2(2.0, 140.0), Vector2(-200.0, 0.0))
	else:
		game.paddle_cy[1] = 30.0
		_playing(game, Vector2(game.W - 2.0, 140.0), Vector2(200.0, 0.0))
	_step(game, 5)


# ---------------------------------------------------------------- court rules

func _test_paddle_hit_reverses_and_speeds_up() -> void:
	var game := _game()
	game.paddle_cy[0] = 72.0
	var ball := _playing(game, Vector2(14.0, 70.0), Vector2(-120.0, 0.0))
	_step(game, 3)
	_expect(ball.vel.x > 0.0, "ball should bounce off the player paddle")
	_expect(ball.vel.length() > 120.0, "ball should speed up after a paddle hit")
	_expect(ball.last_touch == 0, "the player should be the last toucher")
	game.free()


func _test_wall_bounce() -> void:
	var game := _game()
	var ball := _playing(game, Vector2(120.0, game.TOP + 1.0), Vector2(50.0, -100.0))
	_step(game, 2)
	_expect(ball.vel.y > 0.0, "ball should bounce off the top wall")
	game.free()


func _test_point_scores_and_serves() -> void:
	var game := _game()
	_score_point(game, 1)
	_expect(game.scores == [0, 1], "CPU should score when the ball passes the player, got %s" % [game.scores])
	_expect(game.state == game.State.SERVE, "a point should lead to a serve")
	game.free()


func _test_balls_never_leave_court() -> void:
	var game := _game()
	game.tuning.set_value("powerups", 1.0)
	game.tuning.set_value("pu_interval", 1.0)
	game.tuning.set_value("gem_interval", 2.0)
	game.run.add("magnet")
	game.run.add("flame")
	game.start_round()
	var points: int = 0
	for frame in 60 * 90:
		game.simulate(1.0 / 60.0, sin(frame * 0.05))
		if not game.in_round() and game.state != game.State.ROUND_END:
			points += 1
			game.start_round()
		for ball in game.balls:
			if ball.pos.y < game.TOP - 0.01 or ball.pos.y > game.BOTTOM - game.BALL + 0.01:
				_expect(false, "ball left the court vertically at y=%s" % ball.pos.y)
				game.free()
				return
		_expect(game.balls.size() <= int(game.tuning.get_value("max_balls")), "more balls than max_balls")
	_expect(points > 0 or game.scores[0] + game.scores[1] > 0, "90 seconds of play should score")
	game.free()


func _test_tuning_changes_paddle_speed() -> void:
	var game := _game()
	game.tuning.set_value("player_speed", 300.0)
	game.paddle_cy[0] = 40.0
	_step(game, 10, 1.0)
	_expect(is_equal_approx(game.paddle_cy[0], 40.0 + 300.0 * 10.0 / 60.0), "player paddle should move at the tuned speed, got %s" % game.paddle_cy[0])
	game.free()


# ---------------------------------------------------------------- power-ups

func _test_pickup_goes_to_last_toucher() -> void:
	var game := _game()
	var base: float = game.paddle_height(0)
	_playing(game, Vector2(100.0, 80.0), Vector2(120.0, 0.0), 0)
	game.spawn_powerup(game.PowerUp.BIG_PADDLE, Vector2(104.0, 79.0))
	_step(game, 3)
	_expect(game.powerups.is_empty(), "the ball should collect the power-up")
	_expect(game.effects[0].has("big"), "BIG PADDLE should go to the player who last touched the ball")
	_expect(game.paddle_height(0) > base, "the player's paddle should grow")
	_expect(game.effects[1].is_empty(), "the CPU should get nothing")
	game.free()


func _test_untouched_ball_ignores_pickups() -> void:
	var game := _game()
	_playing(game, Vector2(100.0, 80.0), Vector2(120.0, 0.0), -1)
	game.spawn_powerup(game.PowerUp.BIG_PADDLE, Vector2(104.0, 79.0))
	_step(game, 3)
	_expect(game.powerups.size() == 1, "a ball nobody has hit yet should pass through power-ups")
	game.free()


func _test_hitbox_setting() -> void:
	# The ball passes 6px above a power-up: a 7px hitbox misses, a 20px one catches it.
	for box in [7.0, 20.0]:
		var game := _game()
		game.tuning.set_value("pu_hitbox", box)
		_playing(game, Vector2(80.0, 70.0), Vector2(120.0, 0.0), 1)
		game.spawn_powerup(game.PowerUp.SLOW_FOE, Vector2(100.0, 80.0))
		_step(game, 30)
		var caught: bool = game.powerups.is_empty()
		_expect(caught == (box > 10.0), "hitbox %d: caught=%s" % [box, caught])
		game.free()


func _test_shrink_hits_the_foe() -> void:
	var game := _game()
	var base: float = game.paddle_height(1)
	game.apply_powerup(game.PowerUp.SHRINK_FOE, 0)
	_expect(game.paddle_height(1) < base, "SHRINK FOE from the player should shrink the CPU paddle")
	_expect(game.effects[0].is_empty(), "SHRINK FOE should not affect its collector")
	game.free()


func _test_multi_ball_respects_max() -> void:
	var game := _game()
	game.tuning.set_value("max_balls", 4.0)
	var ball := _playing(game, Vector2(100.0, 80.0), Vector2(120.0, 0.0), 1)
	game.apply_powerup(game.PowerUp.MULTI_BALL, 1, ball)
	_expect(game.balls.size() == 3, "MULTI BALL should add two balls, got %d" % game.balls.size())
	game.apply_powerup(game.PowerUp.MULTI_BALL, 1, ball)
	_expect(game.balls.size() == 4, "MULTI BALL should stop at max_balls, got %d" % game.balls.size())
	_expect(game.balls.all(func(b: Ball) -> bool: return b.last_touch == 1), "new balls should keep the last toucher")
	game.free()


func _test_goal_with_balls_left_keeps_playing() -> void:
	var game := _game()
	game.paddle_cy[0] = 30.0
	var leaving := _playing(game, Vector2(2.0, 140.0), Vector2(-200.0, 0.0))
	var staying := Ball.new()
	staying.pos = Vector2(120.0, 80.0)
	staying.vel = Vector2(60.0, 0.0)
	game.balls.append(staying)
	_step(game, 5)
	_expect(game.scores == [0, 1], "the leaving ball should score")
	_expect(game.state == game.State.PLAY and game.balls.size() == 1, "play should continue while a ball remains")
	_expect(not game.balls.has(leaving), "the scored ball should be removed")
	game.free()


func _test_effects_expire() -> void:
	var game := _game()
	game.tuning.set_value("pu_duration", 2.0)
	_playing(game, Vector2(120.0, 80.0), Vector2(10.0, 0.0))
	game.apply_powerup(game.PowerUp.FAST_PADDLE, 0)
	_expect(game.paddle_speed(0) > game.tuning.get_value("player_speed"), "QUICK PADDLE should speed up the paddle")
	_step(game, 150)
	_expect(not game.effects[0].has("fast"), "effects should wear off after the effect time")
	game.free()


# ---------------------------------------------------------------- games, rounds, run

func _test_game_win_resets_points() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 2.0)
	_score_point(game, 0)
	_score_point(game, 0)
	_expect(game.run.games == [1, 0], "two points should win a game, games=%s" % [game.run.games])
	_expect(game.scores == [0, 0], "points should reset after a game")
	_expect(game.state == game.State.SERVE, "the next game should start with a serve")
	game.free()


func _test_round_win_offers_upgrades_and_advances_map() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 5.0)
	for i in 3:
		_score_point(game, 0)
	_expect(game.state == game.State.ROUND_END and game.round_won, "3 games in a best of 5 should win the round")
	_expect(game.run.level == 2 and game.run.cleared == 1, "winning should move to level 2")
	_step(game, 120)
	_expect(game.state == game.State.UPGRADE, "a won round should offer upgrades")
	_expect(game.offers.size() == 3, "three upgrades should be offered, got %d" % game.offers.size())
	var picked: String = game.offers[1]
	game.pick_upgrade(1)
	_expect(game.run.stack(picked) == 1, "picking should add the upgrade")
	_expect(game.state == game.State.MAP, "after picking, the map should show")
	game.free()


func _test_round_loss_ends_run_and_banks_gems() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 1.0)
	game.tuning.set_value("boss_every", 2.0)
	game.run.best_cleared = 0
	game.run.gems = 10
	# Clear levels 1 and 2 (2 is a boss), collect 3 shards, then lose level 3.
	for lvl in 2:
		_score_point(game, 0)
		_step(game, 120)
		game.pick_upgrade(0)
		game.start_round()
	game.run.shards = 3
	_score_point(game, 1)
	_step(game, 120)
	_expect(game.state == game.State.RUN_OVER, "losing a round should end the run")
	var r: Dictionary = game.run_result
	_expect(r.rounds == 4 and r.bosses == 5 and r.shards == 3 and r.total == 12, "reward should be 2+2 rounds, 5 boss, 3 shards: %s" % r)
	_expect(game.run.gems == 22, "gems should be banked, got %d" % game.run.gems)
	_expect(r.new_best and game.run.best_cleared == 2, "2 cleared rounds should be a new best")
	game.start_run()
	_expect(game.run.level == 1 and game.run.stacks.is_empty() and game.run.gems == 22, "a new run resets progress but keeps gems")
	game.free()


func _test_difficulty_scales_with_level_and_boss() -> void:
	var game := _game()
	game.tuning.set_value("boss_every", 5.0)
	var l1_speed: float = game.paddle_speed(1)
	var l1_error: float = game.cpu_error()
	game.run.level = 4
	var l4_speed: float = game.paddle_speed(1)
	_expect(l4_speed > l1_speed, "CPU should be faster at level 4")
	_expect(game.cpu_error() < l1_error, "CPU should aim better at level 4")
	game.run.level = 5
	_expect(game.is_boss() and game.paddle_speed(1) > l4_speed * 1.2, "level 5 boss should be much stronger")
	game.tuning.set_value("cpu_lv", 0.0)
	game.tuning.set_value("boss_bonus", 0.0)
	_expect(is_equal_approx(game.paddle_speed(1), game.tuning.get_value("cpu_speed")), "difficulty settings at 0 should leave the CPU at base speed")
	game.free()


# ---------------------------------------------------------------- upgrades

func _test_long_and_swift() -> void:
	var game := _game()
	var h: float = game.paddle_height(0)
	var s: float = game.paddle_speed(0)
	game.run.add("long")
	game.run.add("swift")
	_expect(game.paddle_height(0) > h, "LONG PADDLE should make the paddle taller")
	_expect(game.paddle_speed(0) > s, "SWIFT PADDLE should make the paddle faster")
	_expect(game.paddle_height(1) == h, "LONG PADDLE should not affect the CPU")
	game.free()


func _test_flame_burns_cpu_paddle_then_recovers() -> void:
	var game := _game()
	game.run.add("flame")
	game.tuning.set_value("burn_time", 2.0)
	game.paddle_cy[0] = 72.0
	var ball := _playing(game, Vector2(14.0, 70.0), Vector2(-120.0, 0.0))
	_step(game, 3)
	_expect(ball.flame, "a ball hit with FLAME BALL should be on fire")
	var full: float = game.paddle_height(1)
	game.paddle_cy[1] = ball.pos.y + 2.0
	ball.pos = Vector2(game.PADDLE_X[1] - 5.0, game.paddle_cy[1] - 2.0)
	ball.vel = Vector2(150.0, 0.0)
	_step(game, 8)  # the player's hit leaves a few frames of hitstop first
	_expect(game.effects[1].has("burn"), "a burning ball should set the CPU paddle on fire")
	_expect(not ball.flame, "the CPU's return should put the ball out")
	game.state = game.State.SERVE
	game.serve_timer = 10.0
	_step(game, 60)
	var mid: float = game.paddle_height(1)
	_expect(mid < full, "the burning paddle should shrink over time (%s -> %s)" % [full, mid])
	_step(game, 90)
	_expect(not game.effects[1].has("burn") and game.paddle_height(1) == full, "the paddle should recover when the burn ends")
	game.free()


func _test_slime_slows_cpu() -> void:
	var game := _game()
	game.run.add("slime")
	var speed: float = game.paddle_speed(1)
	var ball := _playing(game, Vector2(game.PADDLE_X[1] - 5.0, game.paddle_cy[1]), Vector2(150.0, 0.0), 0)
	ball.slime = true
	_step(game, 3)
	_expect(game.effects[1].has("slime"), "a slimy ball should slime the CPU paddle")
	_expect(game.paddle_speed(1) < speed * 0.7, "slime should slow the CPU paddle")
	game.free()


func _test_magnet_pulls_pickups() -> void:
	var game := _game()
	game.run.add("magnet")
	game.tuning.set_value("magnet_range", 60.0)
	game.tuning.set_value("pu_hitbox", 3.0)
	_playing(game, Vector2(100.0, 40.0), Vector2(1.0, 0.0), 0)
	game.spawn_gem(Vector2(100.0, 80.0))
	var start_y: float = game.gems[0].pos.y
	_step(game, 10)
	_expect(game.gems.is_empty() or game.gems[0].pos.y < start_y - 5.0, "MAGNET BALL should pull the gem toward the ball")
	game.free()


func _test_gems_only_for_player() -> void:
	var game := _game()
	_playing(game, Vector2(100.0, 80.0), Vector2(120.0, 0.0), 1)
	game.spawn_gem(Vector2(104.0, 79.0))
	_step(game, 3)
	_expect(game.gems.size() == 1 and game.run.shards == 0, "a ball the CPU hit should not collect gems")
	game.balls[0].last_touch = 0
	game.balls[0].pos = Vector2(100.0, 79.0)
	_step(game, 3)
	_expect(game.gems.is_empty() and game.run.shards == 1, "a ball the player hit should collect the gem")
	game.free()


func _test_power_hit() -> void:
	var speeds: Array[float] = []
	for stacks in 2:
		var game := _game()
		for i in stacks:
			game.run.add("power")
		game.paddle_cy[0] = 72.0
		var ball := _playing(game, Vector2(14.0, 70.0), Vector2(-120.0, 0.0))
		_step(game, 3)
		speeds.append(ball.vel.length())
		game.free()
	_expect(speeds[1] > speeds[0] * 1.1, "POWER HIT should send the ball back faster (%s)" % [speeds])


func _test_offers_skip_maxed() -> void:
	var rng := RandomNumberGenerator.new()
	var stacks := {}
	for id in Upgrades.DEFS:
		if id != "flame" and id != "magnet":
			stacks[id] = Upgrades.DEFS[id].max
	var offers := Upgrades.offers(rng, stacks)
	offers.sort()
	_expect(offers == ["flame", "magnet"], "only upgrades below max should be offered, got %s" % [offers])


# ---------------------------------------------------------------- touch

func _touch(game: Node2D, pos: Vector2, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	game._input(event)


func _drag(game: Node2D, pos: Vector2, relative: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	game._input(event)


func _test_tap_flow_title_map_round() -> void:
	var game := _new_game()
	_touch(game, Vector2(60.0, 100.0), true)
	_expect(game.state == game.State.MAP, "a tap on the title should start a run on the map")
	game.screen_lock = 0.0
	_touch(game, Vector2(60.0, 100.0), true)
	_expect(game.state == game.State.SERVE, "a tap on the map should start the round")
	game.free()


func _test_swipe_moves_paddle() -> void:
	var game := _game()
	game.tuning.set_value("swipe_speed", 2.0)
	game.paddle_cy[0] = 60.0
	_touch(game, Vector2(60.0, 100.0), true)
	_drag(game, Vector2(60.0, 110.0), Vector2(0.0, 10.0))
	_step(game, 1)
	_expect(is_equal_approx(game.paddle_cy[0], 80.0), "a 10px swipe at speed 2 should move the paddle 20px, got %s" % game.paddle_cy[0])
	_touch(game, Vector2(60.0, 110.0), false)
	_drag(game, Vector2(60.0, 120.0), Vector2(0.0, 10.0))
	_step(game, 1)
	_expect(is_equal_approx(game.paddle_cy[0], 80.0), "dragging after lifting the finger should do nothing")
	game.free()


func _test_slow_effect_scales_swipe() -> void:
	var game := _game()
	game.tuning.set_value("swipe_speed", 1.0)
	game.paddle_cy[0] = 60.0
	game.apply_powerup(game.PowerUp.SLOW_FOE, 1)
	_touch(game, Vector2(60.0, 100.0), true)
	_drag(game, Vector2(60.0, 110.0), Vector2(0.0, 10.0))
	_step(game, 6)  # past the pickup's hitstop freeze; the swipe is applied once play resumes
	_expect(is_equal_approx(game.paddle_cy[0], 66.0), "SLOW FOE should scale swipes to 0.6x, got %s" % game.paddle_cy[0])
	game.free()


func _test_touch_buttons() -> void:
	var game := _game()
	game.tuning.set_value("touch_buttons", 1.0)
	game.paddle_cy[0] = 80.0
	_touch(game, game.TOUCH_DOWN.get_center(), true, 1)
	_expect(game.button_touches.get(1) == 1.0, "holding the down button should register as down")
	game._process(1.0 / 60.0)
	_expect(game.paddle_cy[0] > 80.0, "holding the down button should move the paddle down")
	_touch(game, game.TOUCH_DOWN.get_center(), false, 1)
	_expect(game.button_touches.is_empty(), "releasing should stop the button")
	game.tuning.set_value("touch_buttons", 0.0)
	_touch(game, game.TOUCH_DOWN.get_center(), true, 2)
	_expect(game.button_touches.is_empty(), "with on-screen buttons off, that spot is just a swipe")
	game.free()


func _test_tap_top_opens_menu_and_bar_buttons_work() -> void:
	var game := _game()
	_touch(game, Vector2(game.W / 2.0, 5.0), true)
	_expect(game.menu_open, "tapping the top center should open the debug menu")
	_touch(game, Vector2(game.W / 2.0, 5.0), false)
	var before: float = game.tuning.get_value("points_per_game")
	var plus_x: float = (game.W / 6.0) * 3.5
	_touch(game, Vector2(plus_x, game.H - 4.0), true)
	_expect(game.tuning.get_value("points_per_game") > before, "the + button should raise the selected value")
	_touch(game, Vector2(9.0, 12.0 + 7.0 * 2 + 2.0), true)
	_expect(game.menu_index == 2, "tapping a row should select it, got %d" % game.menu_index)
	var close_x: float = (game.W / 6.0) * 5.5
	_touch(game, Vector2(close_x, game.H - 4.0), true)
	_expect(not game.menu_open, "the CLOSE button should close the menu")
	game.free()


func _test_upgrade_cards_by_touch() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 1.0)
	_score_point(game, 0)
	_step(game, 120)
	game.screen_lock = 0.0
	var Screens: GDScript = load("res://scripts/screens.gd")
	var second: Vector2 = Screens.card_rect(1, 3).get_center()
	_touch(game, second, true)
	_expect(game.state == game.State.UPGRADE and game.offer_index == 1, "the first tap should select a card")
	var picked: String = game.offers[1]
	_touch(game, second, true)
	_expect(game.state == game.State.MAP and game.run.stack(picked) == 1, "a second tap should take it")
	game.free()
