extends SceneTree
## Rule checks for scenes/main.gd, driven through simulate() without rendering.

var failures: int = 0


func _initialize() -> void:
	_test_paddle_hit_reverses_and_speeds_up()
	_test_wall_bounce()
	_test_goal_scores_and_serves()
	_test_ball_never_leaves_court()
	_test_match_ends_at_win_score()
	print("test_rules: %s" % ("FAILED" if failures else "all passed"))
	quit(1 if failures else 0)


func _game() -> Node2D:
	var game: Node2D = load("res://scenes/main.gd").new()
	root.add_child(game)
	game.start_match()
	game.state = game.State.PLAY
	return game


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func _step(game: Node2D, frames: int, dir: float = 0.0) -> void:
	for i in frames:
		game.simulate(1.0 / 60.0, dir)


func _test_paddle_hit_reverses_and_speeds_up() -> void:
	var game := _game()
	game.player_y = 60.0
	game.ball_pos = Vector2(14.0, 70.0)
	game.ball_vel = Vector2(-120.0, 0.0)
	_step(game, 3)
	_expect(game.ball_vel.x > 0.0, "ball should bounce off the player paddle")
	_expect(game.ball_vel.length() > 120.0, "ball should speed up after a paddle hit")
	game.queue_free()


func _test_wall_bounce() -> void:
	var game := _game()
	game.ball_pos = Vector2(120.0, game.TOP + 1.0)
	game.ball_vel = Vector2(50.0, -100.0)
	_step(game, 2)
	_expect(game.ball_vel.y > 0.0, "ball should bounce off the top wall")
	_expect(game.ball_pos.y >= game.TOP, "ball should stay below the top wall")
	game.queue_free()


func _test_goal_scores_and_serves() -> void:
	var game := _game()
	game.player_y = 14.0
	game.ball_pos = Vector2(2.0, 140.0)
	game.ball_vel = Vector2(-200.0, 0.0)
	_step(game, 5)
	_expect(game.scores == [0, 1], "CPU should score when the ball passes the player, got %s" % [game.scores])
	_expect(game.state == game.State.SERVE, "a goal should lead to a serve")
	game.queue_free()


func _test_ball_never_leaves_court() -> void:
	var game := _game()
	game.start_match()
	for frame in 60 * 60:
		game.simulate(1.0 / 60.0, sin(frame * 0.05))
		if game.state == game.State.OVER:
			game.start_match()
		if game.ball_pos.y < game.TOP - 0.01 or game.ball_pos.y > game.BOTTOM - game.BALL + 0.01:
			_expect(false, "ball left the court vertically at y=%s" % game.ball_pos.y)
			break
	_expect(game.scores[0] + game.scores[1] > 0, "a minute of play should produce at least one goal")
	game.queue_free()


func _test_match_ends_at_win_score() -> void:
	var game := _game()
	game.scores.assign([game.WIN_SCORE - 1, 0])
	game.cpu_y = 14.0
	game.ball_pos = Vector2(game.W - 2.0, 140.0)
	game.ball_vel = Vector2(200.0, 0.0)
	_step(game, 5)
	_expect(game.state == game.State.OVER, "reaching the win score should end the match")
	game.queue_free()
