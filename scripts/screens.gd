extends RefCounted
## Full-screen views and overlays: title menu, map, upgrade choice, relic shop, run over and pause.
## Each draw function takes the main game node and draws through it.

const Palette := preload("res://scripts/palette.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const Relics := preload("res://scripts/relics.gd")
const Run := preload("res://scripts/run.gd")

const W := Palette.W
const H := Palette.H
const MAP_ANIM := 0.7
const CARD_W := 74
const CARD_H := 104
const CARD_GAP := 4
const CARD_Y := 28
const NODE_SPACING := 32
const NODE_Y := 58
const TITLE_MENU_Y := 88
const PAUSE_BOX := Rect2(50, 22, 140, 116)
const PAUSE_ROW_Y := 40
const ROW_H := 12
const LEAVE_BUTTON := Rect2(W / 2 - 30, 136, 60, 12)

const CENTER := PixelFont.Align.CENTER
const RIGHT := PixelFont.Align.RIGHT


# ---------------------------------------------------------------- title

static func draw_title(g: Node2D) -> void:
	PixelFont.draw(g, "GBA PONG", W / 2, 22, 3, Palette.WHITE, CENTER)
	PixelFont.draw(g, "A ROGUELITE PONG RUN", W / 2, 44, 1, Palette.MID, CENTER)
	PixelFont.draw(g, "BEST %d ROUNDS   GEMS %d" % [g.run.best_cleared, g.run.gems], W / 2, 62, 1, Palette.GEM, CENTER)
	var items: Array = g.title_items()
	for i in items.size():
		var selected: bool = i == g.title_index
		var y: int = TITLE_MENU_Y + i * ROW_H
		if selected:
			g.draw_rect(Rect2(W / 2 - 64, y - 3, 128, 11), Palette.DIM)
			PixelFont.draw(g, ">", W / 2 - 60, y, 1, Palette.PLAYER)
		PixelFont.draw(g, items[i].label, W / 2, y, 1, Palette.WHITE if selected else Palette.MID, CENTER)
	var hint: String = "TAP TO CHOOSE" if g.touch_seen else "UP/DOWN CHOOSE   ENTER START"
	PixelFont.draw(g, hint, W / 2, 126, 1, Palette.DIM, CENTER)
	PixelFont.draw(g, "SWIPE TO MOVE ON TOUCH SCREENS", W / 2, 136, 1, Palette.DIM, CENTER)
	PixelFont.draw(g, "DEBUG: F1 OR TAP TOP CENTER", W / 2, 148, 1, Palette.DIM, CENTER)


static func title_item_at(pos: Vector2, count: int) -> int:
	for i in count:
		if Rect2(W / 2 - 64, TITLE_MENU_Y + i * ROW_H - 3, 128, 11).has_point(pos):
			return i
	return -1


# ---------------------------------------------------------------- map

static func draw_map(g: Node2D) -> void:
	var run: Run = g.run
	var boss_every: int = int(g.tuning.get_value("boss_every"))
	var boss: bool = Run.is_boss(run.level, boss_every)
	var title: String = ("BOSS LEVEL %d" if boss else "LEVEL %d") % run.level
	PixelFont.draw(g, title, W / 2, 4, 2, Palette.BOSS if boss else Palette.WHITE, CENTER)
	PixelFont.draw(g, "VS " + g.foe_name(), W / 2, 19, 1, g.foe_color(), CENTER)
	PixelFont.draw(g, "BEST %d   GEMS %d" % [run.best_cleared, run.gems], W / 2, 28, 1, Palette.GEM, CENTER)

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
	if run.shop_pending:
		# The shop sits just before the current node.
		var shop_x: int = int(target_x - NODE_SPACING / 2)
		g.draw_icon(Relics.DEFS.tithe.icon, Vector2(shop_x - 2, NODE_Y - 10), Palette.GEM)

	var cpu_pct: int = roundi(g.level_factor("cpu_lv") * 100.0)
	PixelFont.draw(g, "CPU SPEED %d%%   AIM ERROR %d" % [cpu_pct, roundi(g.cpu_error())], W / 2, 80, 1, Palette.MID, CENTER)
	PixelFont.draw(g, "BEST OF %d GAMES   FIRST TO %d POINTS" % [g.round_best_of(), int(g.tuning.get_value("points_per_game"))], W / 2, 89, 1, Palette.MID, CENTER)

	PixelFont.draw(g, "YOURS", 6, 101, 1, Palette.DIM)
	_draw_owned(g, 100)
	PixelFont.draw(g, "RELICS", 6, 114, 1, Palette.DIM)
	_draw_relics_row(g, 113)
	PixelFont.draw(g, "FOE", 6, 127, 1, g.foe_color().darkened(0.3))
	_draw_owned(g, 126, run.cpu_stacks)
	if g.map_anim <= 0.0 and fmod(g.blink, 0.8) < 0.5:
		var prompt: String = "PRESS OR TAP TO ENTER THE SHOP" if run.shop_pending else "PRESS UP OR DOWN OR TAP TO PLAY"
		PixelFont.draw(g, prompt, W / 2, 146, 1, Palette.GEM if run.shop_pending else Palette.PLAYER, CENTER)


# ---------------------------------------------------------------- upgrade and shop cards

static func draw_upgrade(g: Node2D) -> void:
	PixelFont.draw(g, "NEW RUN" if g.starting_pick else "ROUND CLEAR!", W / 2, 2, 2, Palette.PLAYER, CENTER)
	PixelFont.draw(g, "CHOOSE A STARTING UPGRADE" if g.starting_pick else "CHOOSE AN UPGRADE", W / 2, 17, 1, Palette.MID, CENTER)
	var count: int = g.offers.size()
	for i in count:
		var id: String = g.offers[i]
		var have: int = g.run.stack(id)
		_draw_card(g, card_rect(i, count), Upgrades.DEFS[id], i == g.offer_index, "LV %d > %d" % [have, have + 1], Upgrades.DEFS[id].color)
	var hint: String = "TAP A CARD, TAP AGAIN TO TAKE" if g.touch_seen else "LEFT/RIGHT CHOOSE   ENTER TAKE"
	PixelFont.draw(g, hint, W / 2, 148, 1, Palette.MID, CENTER)


static func draw_shop(g: Node2D) -> void:
	PixelFont.draw(g, "RELIC SHOP", W / 2, 2, 2, Palette.GEM, CENTER)
	PixelFont.draw(g, "GEMS %d" % g.run.gems, W / 2, 17, 1, Palette.GEM, CENTER)
	var count: int = g.shop_offers.size()
	for i in count:
		var id: String = g.shop_offers[i]
		var def: Dictionary = Relics.DEFS[id]
		var owned: bool = g.run.has_relic(id)
		var cost: int = g.relic_price(id)
		var label: String = "OWNED" if owned else "%d GEMS" % cost
		var label_color: Color = Palette.DIM if owned else (Palette.GEM if g.run.gems >= cost else Palette.BOSS)
		_draw_card(g, card_rect(i, count), def, i == g.shop_index, label, label_color)
	var leave_selected: bool = g.shop_index >= count
	g.draw_rect(LEAVE_BUTTON, Palette.MID if leave_selected else Palette.DIM)
	PixelFont.draw(g, "LEAVE", W / 2, int(LEAVE_BUTTON.position.y) + 4, 1, Palette.WHITE, CENTER)
	var hint: String = "TAP TO PICK, AGAIN TO BUY" if g.touch_seen else "LEFT/RIGHT CHOOSE   ENTER BUY"
	PixelFont.draw(g, hint, W / 2, 151, 1, Palette.DIM, CENTER)


## Index of the shop card under pos, count for LEAVE, or -1.
static func shop_choice_at(pos: Vector2, count: int) -> int:
	if LEAVE_BUTTON.grow(2).has_point(pos):
		return count
	return card_at(pos, count)


static func _draw_card(g: Node2D, rect: Rect2, def: Dictionary, selected: bool, footer: String, footer_color: Color) -> void:
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
	PixelFont.draw(g, footer, cx, int(rect.end.y) - 9, 1, footer_color, CENTER)


static func card_rect(index: int, count: int) -> Rect2:
	var total: int = count * CARD_W + (count - 1) * CARD_GAP
	var x: int = (W - total) / 2 + index * (CARD_W + CARD_GAP)
	return Rect2(x, CARD_Y, CARD_W, CARD_H)


## Index of the card under pos, or -1.
static func card_at(pos: Vector2, count: int) -> int:
	for i in count:
		if card_rect(i, count).grow(2).has_point(pos):
			return i
	return -1


# ---------------------------------------------------------------- run over

static func draw_run_over(g: Node2D) -> void:
	var result: Dictionary = g.run_result
	PixelFont.draw(g, "RUN OVER", W / 2, 6, 3, Palette.CPU, CENTER)
	PixelFont.draw(g, "BEATEN BY %s ON LEVEL %d" % [g.foe_name(), g.run.level], W / 2, 30, 1, g.foe_color(), CENTER)
	var rows := [
		["ROUNDS CLEARED", result.get("rounds", 0)],
		["BOSSES BEATEN", result.get("bosses", 0)],
		["GEM SHARDS", result.get("shards", 0)],
		["GEM TITHE", result.get("tithe", 0)],
	]
	var y: int = 42
	for row in rows:
		PixelFont.draw(g, row[0], 60, y, 1, Palette.MID)
		PixelFont.draw(g, "+%d" % row[1], W - 60, y, 1, Palette.GEM, RIGHT)
		y += 8
	g.draw_rect(Rect2(60, y, W - 120, 1), Palette.DIM)
	y += 4
	PixelFont.draw(g, "GEMS EARNED", 60, y, 1, Palette.WHITE)
	PixelFont.draw(g, "+%d" % result.get("total", 0), W - 60, y, 1, Palette.GEM, RIGHT)
	y += 8
	PixelFont.draw(g, "GEMS NOW", 60, y, 1, Palette.WHITE)
	PixelFont.draw(g, str(g.run.gems), W - 60, y, 1, Palette.GEM, RIGHT)
	if result.get("new_best", false):
		if fmod(g.blink, 0.4) < 0.25:
			PixelFont.draw(g, "NEW BEST!", W / 2, 102, 2, Palette.SPARK, CENTER)
	else:
		PixelFont.draw(g, "BEST %d ROUNDS" % g.run.best_cleared, W / 2, 104, 1, Palette.MID, CENTER)
	_draw_owned(g, 120)
	_draw_relics_row(g, 130)
	if fmod(g.blink, 0.8) < 0.5:
		PixelFont.draw(g, "PRESS UP OR DOWN OR TAP", W / 2, 148, 1, Palette.PLAYER, CENTER)


# ---------------------------------------------------------------- pause

static func draw_pause(g: Node2D) -> void:
	if g.pause_view == "relics":
		_draw_relic_list(g)
		return
	g.draw_rect(PAUSE_BOX, Palette.BG)
	_outline(g, PAUSE_BOX, Palette.MID)
	PixelFont.draw(g, "PAUSED", W / 2, int(PAUSE_BOX.position.y) + 6, 2, Palette.WHITE, CENTER)
	var items: Array = g.pause_items()
	for i in items.size():
		var y: int = PAUSE_ROW_Y + i * ROW_H
		var selected: bool = i == g.pause_index
		if selected:
			g.draw_rect(Rect2(PAUSE_BOX.position.x + 4, y - 3, PAUSE_BOX.size.x - 8, 11), Palette.DIM)
		var color: Color = Palette.WHITE if selected else Palette.MID
		if items[i].id == "menu":
			color = Palette.CPU if selected else Palette.CPU.darkened(0.3)
		PixelFont.draw(g, items[i].label, W / 2, y, 1, color, CENTER)


static func pause_item_at(pos: Vector2, count: int) -> int:
	for i in count:
		if Rect2(PAUSE_BOX.position.x + 4, PAUSE_ROW_Y + i * ROW_H - 3, PAUSE_BOX.size.x - 8, 11).has_point(pos):
			return i
	return -1


static func _draw_relic_list(g: Node2D) -> void:
	g.draw_rect(Rect2(0, 0, W, H), Palette.BG)
	PixelFont.draw(g, "RELICS", W / 2, 4, 2, Palette.GEM, CENTER)
	var relics: Array = g.run.relics
	if relics.is_empty():
		PixelFont.draw(g, "NO RELICS YET. BUY THEM IN THE SHOP", W / 2, 60, 1, Palette.MID, CENTER)
		PixelFont.draw(g, "EVERY %d LEVELS." % int(g.tuning.get_value("shop_every")), W / 2, 70, 1, Palette.MID, CENTER)
	var y: int = 22
	for id in relics:
		var def: Dictionary = Relics.DEFS[id]
		g.draw_icon(def.icon, Vector2(6, y), def.color)
		PixelFont.draw(g, def.name, 16, y, 1, def.color)
		for line in PixelFont.wrap(def.desc, 54):
			y += 7
			PixelFont.draw(g, line, 16, y, 1, Palette.MID)
		y += 10
	PixelFont.draw(g, "ANY KEY OR TAP TO GO BACK", W / 2, 150, 1, Palette.DIM, CENTER)


# ---------------------------------------------------------------- shared rows

## Upgrades as icons with their level: the player's by default, or another stacks dictionary (the CPU's).
static func _draw_owned(g: Node2D, y: int, stacks: Variant = null) -> void:
	var owned: Dictionary = g.run.stacks if stacks == null else stacks
	var ids: Array = owned.keys()
	if ids.is_empty():
		PixelFont.draw(g, "NONE YET", W / 2, y + 1, 1, Palette.DIM, CENTER)
		return
	var step: int = 17
	var x: int = W / 2 - (ids.size() * step - 6) / 2
	for id in ids:
		var def: Dictionary = Upgrades.DEFS[id]
		g.draw_icon(def.icon, Vector2(x, y), def.color)
		PixelFont.draw(g, str(owned[id]), x + 7, y, 1, Palette.WHITE)
		x += step


static func _draw_relics_row(g: Node2D, y: int) -> void:
	var relics: Array = g.run.relics
	if relics.is_empty():
		PixelFont.draw(g, "NONE YET", W / 2, y + 1, 1, Palette.DIM, CENTER)
		return
	var step: int = 10
	var x: int = W / 2 - (relics.size() * step - 5) / 2
	for id in relics:
		g.draw_icon(Relics.DEFS[id].icon, Vector2(x, y), Relics.DEFS[id].color)
		x += step


static func _outline(g: Node2D, rect: Rect2, color: Color) -> void:
	g.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	g.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 1), Vector2(rect.size.x, 1)), color)
	g.draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), color)
	g.draw_rect(Rect2(Vector2(rect.end.x - 1, rect.position.y), Vector2(1, rect.size.y)), color)
