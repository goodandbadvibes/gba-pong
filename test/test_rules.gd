extends SceneTree
## Rule checks for scenes/main.gd, driven through simulate() without rendering.

const Ball := preload("res://scripts/ball.gd")

var failures: int = 0


func _initialize() -> void:
	_test_paddle_hit_reverses_and_speeds_up()
	_test_wall_bounce()
	_test_goal_scores_and_serves()
	_test_balls_never_leave_court()
	_test_match_ends_at_win_score()
	_test_tuning_changes_paddle_speed()
	_test_pickup_goes_to_last_toucher()
	_test_untouched_ball_ignores_pickups()
	_test_shrink_hits_the_foe()
	_test_multi_ball_respects_max()
	_test_goal_with_balls_left_keeps_playing()
	_test_effects_expire()
	print("test_rules: %s" % ("FAILED" if failures else "all passed"))
	quit(1 if failures else 0)


func _game() -> Node2D:
	var game: Node2D = load("res://scenes/main.gd").new()
	root.add_child(game)
	game.tuning.reset()
	game.tuning.set_value("powerups", 0.0)
	game.start_match()
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


func _test_goal_scores_and_serves() -> void:
	var game := _game()
	game.paddle_cy[0] = 30.0
	_playing(game, Vector2(2.0, 140.0), Vector2(-200.0, 0.0))
	_step(game, 5)
	_expect(game.scores == [0, 1], "CPU should score when the ball passes the player, got %s" % [game.scores])
	_expect(game.state == game.State.SERVE, "a goal should lead to a serve")
	game.free()


func _test_balls_never_leave_court() -> void:
	var game := _game()
	game.tuning.set_value("powerups", 1.0)
	game.tuning.set_value("pu_interval", 1.0)
	game.start_match()
	var picked: int = 0
	for frame in 60 * 90:
		var before: int = game.powerups.size()
		game.simulate(1.0 / 60.0, sin(frame * 0.05))
		if game.state == game.State.OVER:
			game.start_match()
		for ball in game.balls:
			if ball.pos.y < game.TOP - 0.01 or ball.pos.y > game.BOTTOM - game.BALL + 0.01:
				_expect(false, "ball left the court vertically at y=%s" % ball.pos.y)
				game.free()
				return
		_expect(game.balls.size() <= int(game.tuning.get_value("max_balls")), "more balls than max_balls")
		if game.powerups.size() < before:
			picked += 1
	_expect(game.scores[0] + game.scores[1] > 0, "90 seconds of play should produce a goal")
	_expect(picked > 0, "90 seconds with power-ups every second should pick one up or expire one")
	game.free()


func _test_match_ends_at_win_score() -> void:
	var game := _game()
	game.tuning.set_value("win_score", 3.0)
	game.scores.assign([2, 0])
	game.paddle_cy[1] = 30.0
	_playing(game, Vector2(game.W - 2.0, 140.0), Vector2(200.0, 0.0))
	_step(game, 5)
	_expect(game.state == game.State.OVER, "reaching the tuned win score should end the match")
	game.free()


func _test_tuning_changes_paddle_speed() -> void:
	var game := _game()
	game.tuning.set_value("player_speed", 300.0)
	game.paddle_cy[0] = 40.0
	_step(game, 10, 1.0)
	_expect(is_equal_approx(game.paddle_cy[0], 40.0 + 300.0 * 10.0 / 60.0), "player paddle should move at the tuned speed, got %s" % game.paddle_cy[0])
	game.free()


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
