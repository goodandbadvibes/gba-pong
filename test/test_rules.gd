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
	_test_long_paddle()
	_test_flame_burns_cpu_paddle_then_recovers()
	_test_slime_slows_cpu()
	_test_magnet_pulls_pickups()
	_test_gems_only_for_player()
	_test_power_hit()
	_test_offers_skip_maxed()
	# Wingmen and turrets
	_test_wingman_powerup_blocks_and_breaks()
	_test_wingman_patrols()
	_test_turret_hits_breaks_and_rebuilds()
	_test_temp_turret_is_not_rebuilt()
	_test_wingman_and_turret_upgrades_spawn()
	# Relics, shop, pause, suspend
	_test_hive_and_sync_pass_on_upgrades()
	_test_virulent_strengthens_status()
	_test_splitter()
	_test_momentum_streak()
	_test_second_wind()
	_test_shop_flow_and_tithe()
	_test_pause_blocks_play_and_toggles_sound()
	_test_suspend_and_continue()
	_test_main_menu_ends_run()
	# Run start, CPU upgrades, poison, booster, power-up ramp
	_test_run_starts_with_upgrade_pick()
	_test_cpu_gains_upgrades_per_level()
	_test_cpu_flame_burns_player()
	_test_venom_builds_poison_and_triggers()
	_test_poison_powerup()
	_test_booster_amplifies_then_ends()
	_test_overcharge_starts_games_boosted()
	_test_powerup_ramp()
	# Music
	_test_music_layers_and_tempo()
	_test_music_renders_a_loop()
	_test_music_tracks_and_game_tempo()
	_test_music_switches_instantly_when_cached()
	_test_music_prefetch_makes_switch_instant()
	_test_music_missing_loop_builds_fast()
	# Opponents, pause debug, music layers
	_test_each_level_has_a_named_opponent()
	_test_suspended_run_keeps_foe_and_drops_unknown_upgrades()
	_test_debug_menu_from_pause()
	_test_music_layers_build_within_a_level()
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
	var h: float = game.paddle_height(0)
	game.apply_powerup(game.PowerUp.BIG_PADDLE, 0)
	_expect(game.paddle_height(0) > h, "BIG PADDLE should grow the paddle")
	_step(game, 150)
	_expect(not game.effects[0].has("big") and game.paddle_height(0) == h, "effects should wear off after the effect time")
	game.free()


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
	game.run.add_shards(3)
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

func _test_long_paddle() -> void:
	var game := _game()
	var h: float = game.paddle_height(0)
	game.run.add("long")
	_expect(game.paddle_height(0) > h, "LONG PADDLE should make the paddle taller")
	_expect(game.paddle_height(1) == h, "LONG PADDLE should not affect the CPU")
	_expect(not game.Upgrades.DEFS.has("swift") and not game.PowerUp.has("FAST_PADDLE"), "paddle speed upgrades and power-ups are gone")
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
	_touch(game, Vector2(120.0, 90.0), true)
	_expect(game.state == game.State.UPGRADE and game.starting_pick, "tapping NEW RUN should open the starting upgrade pick")
	game.screen_lock = 0.0
	var Screens: GDScript = load("res://scripts/screens.gd")
	var first: Vector2 = Screens.card_rect(0, game.offers.size()).get_center()
	_touch(game, first, true)
	_expect(game.state == game.State.MAP and game.map_anim == 0.0, "taking the starting upgrade should open the map")
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


# ---------------------------------------------------------------- wingmen and turrets

func _test_wingman_powerup_blocks_and_breaks() -> void:
	var game := _game()
	game.tuning.set_value("drone_hp", 2.0)
	game.tuning.set_value("drone_speed", 10.0)
	game.apply_powerup(game.PowerUp.WINGMAN, 0)
	_expect(game.drones.size() == 1 and game.drones[0].temp, "the WINGMAN power-up should add a temporary wingman")
	var d: Dictionary = game.drones[0]
	for hit in 2:
		d.y = 80.0
		var ball := _playing(game, Vector2(d.x + 8.0, 78.0), Vector2(-150.0, 0.0))
		game.hitstop = 0.0
		_step(game, 4)
		_expect(ball.vel.x > 0.0 and ball.last_touch == 0, "hit %d: the wingman should send the ball back for the player" % (hit + 1))
	_expect(game.drones.is_empty(), "two hits should destroy a 2 HP wingman")
	game.free()


func _test_wingman_patrols() -> void:
	var game := _game()
	game.spawn_drone(0, false)
	var d: Dictionary = game.drones[0]
	var ys: Array[float] = []
	for i in 300:
		game.simulate(1.0 / 60.0, 0.0)
		ys.append(d.y)
	_expect(ys.max() - ys.min() > 40.0, "a wingman should patrol up and down")
	_expect(ys.min() >= game.TOP + game.DRONE_H / 2.0 - 0.01 and ys.max() <= game.BOTTOM - game.DRONE_H / 2.0 + 0.01, "a wingman should stay on the court")
	game.free()


func _test_turret_hits_breaks_and_rebuilds() -> void:
	var game := _game()
	game.tuning.set_value("unit_hp", 2.0)
	game.tuning.set_value("unit_respawn", 2.0)
	game.spawn_unit(0, false)
	var u: Dictionary = game.units[0]
	for hit in 2:
		u.hit_cd = 0.0
		game.hitstop = 0.0
		var ball := _playing(game, u.pos + Vector2(20.0, -2.0), Vector2(-150.0, 0.0))
		_step(game, 6)
		_expect(ball.vel.x > 0.0 and ball.last_touch == 0, "hit %d: the turret should hit the ball back" % (hit + 1))
	_expect(not u.alive and u.rebuild > 0.0, "two hits should destroy a 2 HP turret")
	game.balls.clear()
	game.state = game.State.SERVE
	game.serve_timer = 10.0
	_step(game, 150)
	_expect(u.alive and u.hp == u.max_hp, "the turret should rebuild after its cooldown")
	game.free()


func _test_temp_turret_is_not_rebuilt() -> void:
	var game := _game()
	game.tuning.set_value("unit_hp", 1.0)
	game.apply_powerup(game.PowerUp.TURRET, 0)
	var u: Dictionary = game.units[0]
	_playing(game, u.pos + Vector2(20.0, 0.0), Vector2(-150.0, 0.0))
	game.hitstop = 0.0
	_step(game, 6)
	_expect(game.units.is_empty(), "a turret from a power-up should be gone for good once destroyed")
	game.free()


func _test_wingman_and_turret_upgrades_spawn() -> void:
	var game := _game()
	game.run.add("wingman")
	game.run.add("wingman")
	game.run.add("turret")
	game.start_round()
	_expect(game.drones.filter(func(d): return d.side == 0).size() == 2, "WINGMAN level 2 should start the round with 2 wingmen")
	_expect(game.units.size() == 1 and not game.units[0].temp, "TURRET should place a lasting turret")
	game.drones.clear()
	game.tuning.set_value("points_per_game", 1.0)
	_score_point(game, 0)
	_expect(game.drones.size() == 2, "wingmen should be back for the next game")
	game.free()


# ---------------------------------------------------------------- relics, shop, pause

func _test_hive_and_sync_pass_on_upgrades() -> void:
	for relic in ["", "hive"]:
		var game := _game()
		game.run.add("flame")
		if relic != "":
			game.run.relics.append(relic)
		game.spawn_unit(0, false)
		var u: Dictionary = game.units[0]
		var ball := _playing(game, u.pos + Vector2(20.0, 0.0), Vector2(-150.0, 0.0))
		_step(game, 6)
		_expect(ball.flame == (relic == "hive"), "turret hit with relic [%s]: flame=%s" % [relic, ball.flame])
		game.free()
	for relic in ["", "sync"]:
		var game := _game()
		game.run.add("flame")
		if relic != "":
			game.run.relics.append(relic)
		game.tuning.set_value("drone_speed", 10.0)
		game.spawn_drone(0, false)
		var d: Dictionary = game.drones[0]
		d.y = 80.0
		var ball := _playing(game, Vector2(d.x + 8.0, 78.0), Vector2(-150.0, 0.0))
		_step(game, 4)
		_expect(ball.flame == (relic == "sync"), "wingman hit with relic [%s]: flame=%s" % [relic, ball.flame])
		game.free()


func _test_virulent_strengthens_status() -> void:
	var game := _game()
	game.run.add("flame")
	game.run.add("slime")
	var burn: float = game.burn_strength(0)
	var slime: float = game.slime_factor(0)
	game.run.relics.append("virulent")
	_expect(game.burn_strength(0) > burn and game.slime_factor(0) < slime, "VIRULENT should make burn and slime stronger")
	game.free()


func _test_splitter() -> void:
	var game := _game()
	game.run.relics.append("splitter")
	game.tuning.set_value("split_chance", 100.0)
	game.paddle_cy[0] = 72.0
	_playing(game, Vector2(14.0, 70.0), Vector2(-120.0, 0.0))
	_step(game, 3)
	_expect(game.balls.size() == 2, "SPLITTER at 100%% should split a ball off every paddle hit, got %d" % game.balls.size())
	game.free()


func _test_momentum_streak() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 9.0)
	var base: float = game.paddle_height(0)
	game.run.relics.append("momentum")
	_score_point(game, 0)
	_score_point(game, 0)
	_expect(game.run.streak == 2 and game.paddle_height(0) > base, "MOMENTUM should grow the paddle with each game won in a row")
	_score_point(game, 1)
	_expect(game.run.streak == 0 and game.paddle_height(0) == base, "losing a game should reset MOMENTUM")
	game.free()


func _test_second_wind() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 1.0)
	game.run.relics.append("second")
	_score_point(game, 1)
	_step(game, 120)
	_expect(game.state == game.State.MAP and game.run.second_wind_used and game.run.level == 1, "SECOND WIND should save the run once")
	game.start_round()
	_score_point(game, 1)
	_step(game, 120)
	_expect(game.state == game.State.RUN_OVER, "the second lost round should end the run")
	game.free()


func _test_shop_flow_and_tithe() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 1.0)
	game.tuning.set_value("shop_every", 2.0)
	game.tuning.set_value("boss_every", 0.0)
	game.run.gems = 0
	game.run.relics.append("tithe")
	for i in 2:
		game.start_round()
		_score_point(game, 0)
		_step(game, 120)
		game.pick_upgrade(0)
	_expect(game.run.gems == 8, "two rounds with GEM TITHE should give 2x(2+2) gems, got %d" % game.run.gems)
	_expect(game.run.shop_pending, "the shop should open after 2 levels")
	game.map_anim = 0.0
	game.screen_lock = 0.0
	game._screen_confirm()
	_expect(game.state == game.State.SHOP and game.shop_offers.size() == 3, "confirming the map should enter the shop")
	var expensive: String = ""
	for id in game.shop_offers:
		if game.relic_price(id) > 8:
			expensive = id
	if expensive != "":
		game.shop_choose(game.shop_offers.find(expensive))
		_expect(not game.run.has_relic(expensive) and game.run.gems == 8, "a relic that costs more than you have should not be bought")
	game.run.gems = 100
	var id: String = game.shop_offers[0]
	game.shop_choose(0)
	_expect(game.run.has_relic(id) and game.run.gems == 100 - game.relic_price(id), "buying should take the relic and its price")
	game.shop_choose(game.shop_offers.size())
	_expect(game.state == game.State.MAP and not game.run.shop_pending, "LEAVE should go back to the map")
	game.map_anim = 0.0
	game._screen_confirm()
	_expect(game.state == game.State.SERVE, "after the shop the map should start the next round")
	game.free()


func _pause_id(game: Node2D, id: String) -> int:
	var items: Array = game.pause_items()
	for i in items.size():
		if items[i].id == id:
			return i
	return -1


func _test_pause_blocks_play_and_toggles_sound() -> void:
	var game := _game()
	game.set_paused(true)
	game.paddle_cy[0] = 80.0
	game.button_touches[5] = 1.0
	game._process(0.1)
	_expect(game.paddle_cy[0] == 80.0, "nothing should move while paused")
	var sound: float = game.tuning.get_value("sound")
	game.pause_choose(_pause_id(game, "sound"))
	_expect(game.tuning.get_value("sound") != sound, "the SOUND item should toggle sound")
	game.pause_choose(_pause_id(game, "resume"))
	_expect(not game.paused, "RESUME should unpause")
	AudioServer.set_bus_mute(0, false)
	game.free()


func _test_suspend_and_continue() -> void:
	var game := _game()
	game.run.level = 4
	game.run.cleared = 3
	game.run.add("magnet")
	game.run.relics.append("splitter")
	game.set_paused(true)
	game.pause_choose(_pause_id(game, "suspend"))
	_expect(game.state == game.State.TITLE and game.run.can_continue(), "SUSPEND should return to the title with a run to continue")
	_expect(game.title_items()[0].id == "continue", "the title should offer CONTINUE first")
	game.run.level = 1
	game.run.relics.clear()
	game.title_choose(0)
	_expect(game.state == game.State.MAP and game.run.level == 4 and game.run.stack("magnet") == 1 and game.run.has_relic("splitter"), "CONTINUE should restore the suspended run")
	_expect(not game.run.can_continue(), "a continued run should no longer be suspended")
	game.free()


func _test_main_menu_ends_run() -> void:
	var game := _game()
	game.run.cleared = 2
	game.run.best_cleared = 0
	game.set_paused(true)
	game.pause_choose(_pause_id(game, "menu"))
	_expect(game.state == game.State.TITLE and not game.run.can_continue() and game.run.best_cleared == 2, "MAIN MENU should end the run and keep the best")
	game.free()


# ---------------------------------------------------------------- music

func _music() -> Node:
	var Music: GDScript = load("res://scripts/music.gd")
	var Tuning: GDScript = load("res://scripts/tuning.gd")
	var music: Node = Music.new()
	music.tuning = Tuning.new()
	root.add_child(music)
	return music


func _test_music_layers_and_tempo() -> void:
	var music := _music()
	_expect(music.active_layers(0) == ["pulse"], "the title should only have the low pulse, got %s" % [music.active_layers(0)])
	_expect(music.active_layers(1) == ["pulse", "bass"], "level 1 adds bass")
	_expect(music.active_layers(4).size() == 5, "level 4 has all five layers")
	_expect(music.bpm_for(5) > music.bpm_for(1), "the beat should speed up with the level")
	music.tuning.set_value("layer_lead", 2.0)
	music.tuning.set_value("layer_bass", 0.0)
	_expect(music.active_layers(0) == ["pulse", "lead"], "ON forces a layer in and OFF keeps it out, got %s" % [music.active_layers(0)])
	music.tuning.set_value("music_intensity", 6.0)
	_expect(music.effective_intensity(1) == 6, "a set MUSIC INTENSITY overrides the level")
	music.free()


func _test_music_renders_a_loop() -> void:
	var music := _music()
	var wav: AudioStreamWAV = music.render_now(4)
	var expected: int = music.loop_samples(music.bpm_for(4))
	_expect(wav != null and wav.data.size() == expected and wav.loop_end == expected, "the loop should be exactly two bars long")
	_expect(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.format == AudioStreamWAV.FORMAT_8_BITS, "the loop should be 8-bit and looping")
	var loud: int = 0
	for i in range(0, wav.data.size(), 97):
		var v: int = wav.data[i]
		if v > 127:
			v -= 256
		if absi(v) > 4:
			loud += 1
	_expect(loud > 50, "the loop should not be silent")
	var calm: AudioStreamWAV = music.render_now(1)
	_expect(calm.data.size() > wav.data.size(), "a calmer level should loop slower (longer)")
	music.free()


# ---------------------------------------------------------------- run start, CPU upgrades

func _test_run_starts_with_upgrade_pick() -> void:
	var game := _new_game()
	game.start_run()
	_expect(game.state == game.State.UPGRADE and game.starting_pick and game.offers.size() == 3, "a run should start with a pick of 3 upgrades")
	var picked: String = game.offers[2]
	game.pick_upgrade(2)
	_expect(game.state == game.State.MAP and game.map_anim == 0.0 and game.run.stack(picked) == 1 and not game.starting_pick, "the starting pick should lead to the map at level 1")
	_expect(game.run.cpu_stacks.is_empty(), "the first opponent has no upgrades")
	game.free()


func _test_cpu_gains_upgrades_per_level() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 1.0)
	for lvl in 3:
		game.start_round()
		_score_point(game, 0)
		_step(game, 120)
		game.pick_upgrade(0)
	var total: int = game.run.cpu_stacks.values().reduce(func(a, b): return a + b, 0)
	_expect(total == 3, "after clearing 3 levels the CPU should have 3 upgrades, got %d" % total)
	_expect(not game.run.cpu_stacks.has("lucky"), "the CPU never gets LUCKY FIND")
	game.tuning.set_value("cpu_upgrades", 0.0)
	game.start_round()
	_score_point(game, 0)
	_step(game, 120)
	var after: int = game.run.cpu_stacks.values().reduce(func(a, b): return a + b, 0)
	_expect(after == 3, "CPU UPGRADES PER LEVEL 0 should stop them")
	game.free()


func _test_cpu_flame_burns_player() -> void:
	var game := _game()
	game.run.cpu_add("flame")
	var ball := _playing(game, Vector2(game.PADDLE_X[1] - 5.0, game.paddle_cy[1] - 2.0), Vector2(150.0, 0.0))
	_step(game, 8)
	_expect(ball.flame and ball.last_touch == 1, "a CPU with FLAME BALL should set balls on fire")
	game.paddle_cy[0] = 80.0
	ball.pos = Vector2(game.PADDLE_X[0] + game.PADDLE_W + 2.0, 78.0)
	ball.vel = Vector2(-150.0, 0.0)
	_step(game, 8)
	_expect(game.effects[0].has("burn") and game.effects[0].burn.src == 1, "the CPU's burning ball should burn the player's paddle")
	_expect(not ball.flame, "the player's return should put the ball out (no FLAME BALL)")
	game.free()


# ---------------------------------------------------------------- poison and booster

func _test_venom_builds_poison_and_triggers() -> void:
	var game := _game()
	game.run.add("venom")
	game.tuning.set_value("poison_cap", 4.0)
	game.tuning.set_value("poison_area_size", 30.0)
	game.tuning.set_value("poison_area_time", 2.0)
	game.tuning.set_value("poison_area_slow", 0.5)
	var speed: float = game.paddle_speed(1)
	for hit in 2:
		game.paddle_cy[0] = 72.0
		var ball := _playing(game, Vector2(14.0, 70.0), Vector2(-120.0, 0.0))
		_step(game, 6)
		_expect(ball.venom, "a ball hit with VENOM BALL should be poisonous")
		ball.pos = Vector2(game.PADDLE_X[1] - 5.0, game.paddle_cy[1] - 2.0)
		ball.vel = Vector2(150.0, 0.0)
		_step(game, 8)
		if hit == 0:
			_expect(is_equal_approx(game.poison[1], 2.0), "one poisonous hit should add 2 poison, got %s" % game.poison[1])
	_expect(game.poison[1] == 0.0 and game.poison_areas.size() == 1 and game.poison_areas[0].side == 1, "reaching the cap should leave a poison patch on the CPU's track")
	var patch_y: float = game.poison_areas[0].y
	game.paddle_cy[1] = patch_y
	_expect(game.in_poison(1) and is_equal_approx(game.paddle_speed(1), speed * 0.5), "the CPU paddle should move at half speed on the patch")
	game.paddle_cy[1] = patch_y + 40.0 if patch_y < 80.0 else patch_y - 40.0
	_expect(not game.in_poison(1) and is_equal_approx(game.paddle_speed(1), speed), "off the patch the paddle should move normally")
	game.balls.clear()
	game.state = game.State.SERVE
	game.serve_timer = 10.0
	_step(game, 150)
	_expect(game.poison_areas.is_empty(), "the patch should vanish after POISON PATCH TIME")
	game.free()


func _test_poison_powerup() -> void:
	var game := _game()
	game.tuning.set_value("poison_pu", 4.0)
	game.apply_powerup(game.PowerUp.POISON, 0)
	_expect(is_equal_approx(game.poison[1], 4.0) and game.poison[0] == 0.0, "the POISON power-up should poison the collector's foe")
	game.free()


func _test_booster_amplifies_then_ends() -> void:
	var game := _game()
	game.run.add("long")
	game.tuning.set_value("booster_time", 2.0)
	game.tuning.set_value("booster_mult", 2.0)
	var h: float = game.paddle_height(0)
	game.apply_powerup(game.PowerUp.BOOSTER, 0)
	_expect(game.paddle_height(0) > h, "a booster should make LONG PADDLE stronger")
	game.apply_powerup(game.PowerUp.BIG_PADDLE, 0)
	var big_boosted: float = game.paddle_height(0)
	game.state = game.State.SERVE
	game.serve_timer = 10.0
	_step(game, 150)
	_expect(not game.effects[0].has("boost"), "the booster should end after BOOSTER TIME")
	_expect(game.paddle_height(0) < big_boosted, "effects should drop back once the booster ends")
	game.free()


func _test_overcharge_starts_games_boosted() -> void:
	var game := _game()
	game.run.add("overcharge")
	game.start_round()
	_expect(game.effects[0].has("boost") and is_equal_approx(game.effects[0].boost.t, 2.0), "OVERCHARGE should start each game with a 2 s booster")
	game.free()


func _test_powerup_ramp() -> void:
	var game := _game()
	game.tuning.set_value("pu_ramp_after", 30.0)
	game.tuning.set_value("pu_ramp_mult", 2.0)
	var normal: float = game._pu_interval()
	game.round_time = 31.0
	_expect(is_equal_approx(game._pu_interval(), normal / 2.0), "after 30 s power-ups should come twice as often")
	game.tuning.set_value("pu_ramp_after", 0.0)
	_expect(is_equal_approx(game._pu_interval(), normal), "NEVER should turn the ramp off")
	game.free()


# ---------------------------------------------------------------- music tracks

func _test_music_tracks_and_game_tempo() -> void:
	var music := _music()
	_expect(music.track_bpm("game", 3, 2) > music.track_bpm("game", 3, 0), "the beat should speed up with each game in a level")
	_expect(music.track_bpm("game", 4, 0) > music.track_bpm("game", 3, 0), "and with each level")
	_expect(music.track_bpm("map", 3, 2) == music.tuning.get_value("map_bpm"), "the map track has its own tempo")
	music.tuning.set_value("layer_arp", 0.0)
	_expect(music.layers_for("shop", 0).has("arp") and not music.layers_for("game", 9).has("arp"), "layer settings only shape the game track")
	for track in ["map", "shop"]:
		var wav: AudioStreamWAV = music.render_now(1, track)
		var loud: int = 0
		for i in range(0, wav.data.size(), 97):
			var v: int = wav.data[i]
			if v > 127:
				v -= 256
			if absi(v) > 4:
				loud += 1
		_expect(loud > 50, "the %s track should not be silent" % track)
		_expect(wav.data.size() == music.loop_samples(music.track_bpm(track, 1)), "the %s loop should be two bars" % track)
	music.free()


# ---------------------------------------------------------------- music switching

func _test_music_switches_instantly_when_cached() -> void:
	var music := _music()
	music.render_now(1, "map")
	var map_key: String = music.current_key
	music.play_for(1, "game")
	_expect(music.current_key == "" and music.wanted_key != "", "a loop that is not ready should silence the old music at once")
	music.play_for(1, "map")
	_expect(music.current_key == map_key and music.wanted_key == "", "going back to a cached loop should switch instantly")
	music.free()


func _test_music_prefetch_makes_switch_instant() -> void:
	var music := _music()
	music.render_now(0, "map")
	music.prefetch(3, "game", 1)
	music.prefetch(0, "shop")
	var frames: int = 0
	while not (music.is_cached(3, "game", 1) and music.is_cached(0, "shop")) and frames < 2000:
		music._process(1.0 / 60.0)
		frames += 1
	_expect(music.is_cached(3, "game", 1) and music.is_cached(0, "shop"), "prefetched loops should get built in the background")
	_expect(music.current_key == music.spec(0, "map").key, "prefetching should not interrupt the playing loop")
	music.play_for(0, "shop")
	_expect(music.current_key == music.spec(0, "shop").key, "a prefetched loop should start the moment its screen opens")
	music.free()


func _test_music_missing_loop_builds_fast() -> void:
	var music := _music()
	music.play_for(6, "game", 2)
	var frames: int = 0
	while music.current_key == "" and frames < 600:
		music._process(1.0 / 60.0)
		frames += 1
	_expect(music.current_key == music.spec(6, "game", 2).key, "the wanted loop should start once built")
	_expect(frames <= 45, "an urgent loop should be ready within 45 frames, took %d" % frames)
	music.free()


# ---------------------------------------------------------------- opponents, pause debug, music layers

func _test_each_level_has_a_named_opponent() -> void:
	var game := _new_game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 1.0)
	game.tuning.set_value("boss_every", 3.0)
	game.start_run()
	game.pick_upgrade(0)
	var first: Dictionary = game.run.foe.duplicate()
	_expect(first.has("name") and first.name != "" and game.foe_color() == first.color, "level 1 should have a named opponent with a color")
	_expect(game.foe_color() != game.Palette.PLAYER, "the opponent never uses the player's orange")
	for lvl in 2:
		game.start_round()
		_score_point(game, 0)
		_step(game, 120)
		game.pick_upgrade(0)
	_expect(game.run.level == 3 and game.is_boss(), "level 3 should be a boss here")
	_expect(game.Foes.BOSSES.has(game.foe_name()) and game.foe_color() == game.Foes.BOSS_COLOR, "a boss level should bring a boss opponent in boss red, got %s" % game.foe_name())
	game.free()


func _test_suspended_run_keeps_foe_and_drops_unknown_upgrades() -> void:
	var game := _game()
	game.run.foe = {"name": "BIT BARON", "color": Color8(120, 200, 248)}
	game.run.stacks = {"long": 2}
	game.run.suspend()
	game.run.suspended["stacks"]["swift"] = 2
	game.run.suspended["cpu_stacks"] = {"swift": 1, "flame": 1}
	game.run.foe = {}
	game.title_choose(0)
	_expect(game.foe_name() == "BIT BARON", "a continued run should keep its opponent")
	_expect(game.run.stacks == {"long": 2} and game.run.cpu_stacks == {"flame": 1}, "upgrades that no longer exist should be dropped, got %s / %s" % [game.run.stacks, game.run.cpu_stacks])
	game.free()


func _test_debug_menu_from_pause() -> void:
	var game := _game()
	game.set_paused(true)
	game.pause_choose(_pause_id(game, "debug"))
	_expect(game.menu_open and game.paused, "DEBUG MENU in the pause menu should open the debug menu over it")
	game._toggle_menu()
	_expect(not game.menu_open and game.paused, "closing the debug menu should return to the pause menu")
	game.free()


func _test_music_layers_build_within_a_level() -> void:
	var game := _game()
	game.tuning.set_value("points_per_game", 1.0)
	game.tuning.set_value("best_of", 5.0)
	game.tuning.set_value("boss_every", 0.0)
	var first: int = game.music_intensity()
	_score_point(game, 0)
	_score_point(game, 1)
	_expect(game.music_intensity() == first + 2, "each game played should add a music layer (%d -> %d)" % [first, game.music_intensity()])
	game.run.level = 7
	game.start_round()
	_expect(game.music_intensity() == first, "a new level starts the layers over")
	game.free()
