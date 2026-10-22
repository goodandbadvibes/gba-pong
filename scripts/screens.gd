extends RefCounted
## Full-screen views between rounds: title, map, upgrade choice and run over.
## Each draw function takes the main game node and draws through it.

const Palette := preload("res://scripts/palette.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const Run := preload("res://scripts/run.gd")

const W := Palette.W
const H := Palette.H
const MAP_ANIM := 0.7
const CARD_W := 74
const CARD_H := 104
const CARD_GAP := 4
const CARD_Y := 32
const NODE_SPACING := 32
const NODE_Y := 64

const CENTER := PixelFont.Align.CENTER


static func draw_title(g: Node2D) -> void:
	PixelFont.draw(g, "GBA PONG", W / 2, 26, 3, Palette.WHITE, CENTER)
	PixelFont.draw(g, "A ROGUELITE PONG RUN", W / 2, 48, 1, Palette.MID, CENTER)
	PixelFont.draw(g, "BEST %d ROUNDS   GEMS %d" % [g.run.best_cleared, g.run.gems], W / 2, 68, 1, Palette.GEM, CENTER)
	if fmod(g.blink, 0.8) < 0.5:
		PixelFont.draw(g, "PRESS UP OR DOWN OR TAP", W / 2, 96, 1, Palette.PLAYER, CENTER)
	PixelFont.draw(g, "SWIPE TO MOVE ON TOUCH SCREENS", W / 2, 110, 1, Palette.DIM, CENTER)
	PixelFont.draw(g, "DEBUG: F1 OR TAP TOP CENTER", W / 2, 146, 1, Palette.DIM, CENTER)


static func draw_map(g: Node2D) -> void:
	var run: Run = g.run
	var boss_every: int = int(g.tuning.get_value("boss_every"))
	var boss: bool = Run.is_boss(run.level, boss_every)
	var title: String = ("BOSS LEVEL %d" if boss else "LEVEL %d") % run.level
	PixelFont.draw(g, title, W / 2, 8, 2, Palette.BOSS if boss else Palette.WHITE, CENTER)
	PixelFont.draw(g, "BEST %d   GEMS %d   RUN GEMS %d" % [run.best_cleared, run.gems, run.shards], W / 2, 25, 1, Palette.GEM, CENTER)

	# A row of seven nodes around the current level, cleared ones on the left.
	var first: int = maxi(1, run.level - 3)
	var x0: int = W / 2 - 3 * NODE_SPACING
	for i in 7:
		var lvl: int = first + i
		var x: int = x0 + i * NODE_SPACING
		if i < 6:
			for dx in range(x + 7, x + NODE_SPACING - 6, 4):
				g.draw_rect(Rect2(dx, NODE_Y, 2, 1), Palette.MID if lvl < run.level else Palette.DIM)
		var node_boss: bool = Run.is_boss(lvl, boss_every)
		var size: int = 11 if node_boss else 7
		var rect := Rect2(x - size / 2, NODE_Y - size / 2, size, size)
		var color: Color = Palette.BOSS if node_boss else Palette.MID
		if lvl < run.level:
			g.draw_rect(rect, color.darkened(0.3))
		elif lvl == run.level:
			g.draw_rect(rect.grow(1), Palette.WHITE if fmod(g.blink, 0.5) < 0.25 else Palette.PLAYER)
			g.draw_rect(rect, Palette.BG)
			g.draw_rect(rect.grow(-2), color)
		else:
			_outline(g, rect, Palette.BOSS if node_boss else Palette.DIM)
		PixelFont.draw(g, str(lvl), x, NODE_Y + 9, 1, Palette.WHITE if lvl == run.level else Palette.DIM, CENTER)

	# The player's marker slides from the previous node after a round win.
	var target_x: float = x0 + (run.level - first) * NODE_SPACING
	var t: float = 1.0 - clampf(g.map_anim / MAP_ANIM, 0.0, 1.0)
	var marker_x: float = lerpf(target_x - NODE_SPACING, target_x, 1.0 - pow(1.0 - t, 3.0)) if g.map_anim > 0.0 else target_x
	g.draw_rect(Rect2(roundf(marker_x) - 1, NODE_Y - 18, 3, 9), Palette.PLAYER)

	var cpu_pct: int = roundi(g.level_factor("cpu_lv") * 100.0)
	PixelFont.draw(g, "CPU SPEED %d%%   AIM ERROR %d" % [cpu_pct, roundi(g.cpu_error())], W / 2, 88, 1, Palette.MID, CENTER)
	PixelFont.draw(g, "BEST OF %d GAMES   FIRST TO %d POINTS" % [int(g.tuning.get_value("best_of")), int(g.tuning.get_value("points_per_game"))], W / 2, 97, 1, Palette.MID, CENTER)

	_draw_owned(g, 116)
	if g.map_anim <= 0.0 and fmod(g.blink, 0.8) < 0.5:
		PixelFont.draw(g, "PRESS UP OR DOWN OR TAP TO PLAY", W / 2, 146, 1, Palette.PLAYER, CENTER)


static func draw_upgrade(g: Node2D) -> void:
	PixelFont.draw(g, "ROUND CLEAR!", W / 2, 4, 2, Palette.PLAYER, CENTER)
	PixelFont.draw(g, "CHOOSE AN UPGRADE", W / 2, 20, 1, Palette.MID, CENTER)
	var count: int = g.offers.size()
	for i in count:
		var id: String = g.offers[i]
		var def: Dictionary = Upgrades.DEFS[id]
		var selected: bool = i == g.offer_index
		var rect: Rect2 = card_rect(i, count)
		if selected:
			rect.position.y -= 3
		g.draw_rect(rect, Palette.BG)
		_outline(g, rect, Palette.WHITE if selected else def.color)
		if selected:
			_outline(g, rect.grow(-1), def.color)
		var cx: int = int(rect.position.x + rect.size.x / 2)
		var y: int = int(rect.position.y)
		g.draw_icon(def.icon, Vector2(cx - 5, y + 5), def.color, 2)
		var line_y: int = y + 19
		for line in PixelFont.wrap(def.name, 17):
			PixelFont.draw(g, line, cx, line_y, 1, Palette.WHITE if selected else def.color, CENTER)
			line_y += 7
		line_y += 3
		for line in PixelFont.wrap(def.desc, 17):
			PixelFont.draw(g, line, cx, line_y, 1, Palette.WHITE if selected else Palette.MID, CENTER)
			line_y += 7
		var have: int = g.run.stack(id)
		PixelFont.draw(g, "LV %d > %d" % [have, have + 1], cx, int(rect.end.y) - 9, 1, def.color, CENTER)
	var hint: String = "TAP A CARD, TAP AGAIN TO TAKE" if g.touch_seen else "LEFT/RIGHT CHOOSE   ENTER TAKE"
	PixelFont.draw(g, hint, W / 2, 148, 1, Palette.MID, CENTER)


static func draw_run_over(g: Node2D) -> void:
	var result: Dictionary = g.run_result
	PixelFont.draw(g, "RUN OVER", W / 2, 8, 3, Palette.CPU, CENTER)
	PixelFont.draw(g, "REACHED LEVEL %d   ROUNDS CLEARED %d" % [g.run.level, g.run.cleared], W / 2, 34, 1, Palette.WHITE, CENTER)
	var rows := [
		["ROUNDS CLEARED", result.get("rounds", 0)],
		["BOSSES BEATEN", result.get("bosses", 0)],
		["GEM SHARDS", result.get("shards", 0)],
	]
	var y: int = 50
	for row in rows:
		PixelFont.draw(g, row[0], 60, y, 1, Palette.MID)
		PixelFont.draw(g, "+%d" % row[1], W - 60, y, 1, Palette.GEM, PixelFont.Align.RIGHT)
		y += 9
	g.draw_rect(Rect2(60, y, W - 120, 1), Palette.DIM)
	y += 4
	PixelFont.draw(g, "GEMS EARNED", 60, y, 1, Palette.WHITE)
	PixelFont.draw(g, "+%d" % result.get("total", 0), W - 60, y, 1, Palette.GEM, PixelFont.Align.RIGHT)
	y += 9
	PixelFont.draw(g, "TOTAL GEMS", 60, y, 1, Palette.WHITE)
	PixelFont.draw(g, str(g.run.gems), W - 60, y, 1, Palette.GEM, PixelFont.Align.RIGHT)
	if result.get("new_best", false):
		if fmod(g.blink, 0.4) < 0.25:
			PixelFont.draw(g, "NEW BEST!", W / 2, 106, 2, Palette.SPARK, CENTER)
	else:
		PixelFont.draw(g, "BEST %d ROUNDS" % g.run.best_cleared, W / 2, 108, 1, Palette.MID, CENTER)
	_draw_owned(g, 124)
	if fmod(g.blink, 0.8) < 0.5:
		PixelFont.draw(g, "PRESS UP OR DOWN OR TAP", W / 2, 148, 1, Palette.PLAYER, CENTER)


static func card_rect(index: int, count: int) -> Rect2:
	var total: int = count * CARD_W + (count - 1) * CARD_GAP
	var x: int = (W - total) / 2 + index * (CARD_W + CARD_GAP)
	return Rect2(x, CARD_Y, CARD_W, CARD_H)


## Index of the upgrade card under pos, or -1.
static func card_at(pos: Vector2, count: int) -> int:
	for i in count:
		if card_rect(i, count).grow(2).has_point(pos):
			return i
	return -1


## The run's upgrades as icons with their level, centered on one row.
static func _draw_owned(g: Node2D, y: int) -> void:
	var ids: Array = g.run.stacks.keys()
	if ids.is_empty():
		PixelFont.draw(g, "NO UPGRADES YET", W / 2, y + 1, 1, Palette.DIM, CENTER)
		return
	var step: int = 18
	var x: int = W / 2 - (ids.size() * step - 6) / 2
	for id in ids:
		var def: Dictionary = Upgrades.DEFS[id]
		g.draw_icon(def.icon, Vector2(x, y), def.color)
		PixelFont.draw(g, str(g.run.stack(id)), x + 7, y, 1, Palette.WHITE)
		x += step


static func _outline(g: Node2D, rect: Rect2, color: Color) -> void:
	g.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	g.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 1), Vector2(rect.size.x, 1)), color)
	g.draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), color)
	g.draw_rect(Rect2(Vector2(rect.end.x - 1, rect.position.y), Vector2(1, rect.size.y)), color)
