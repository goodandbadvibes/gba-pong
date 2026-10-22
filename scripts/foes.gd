extends RefCounted
## Opponent identities: every level brings a new named opponent with its own color.
## Boss levels draw from their own list and are always boss red. Names and colors: content/opponents.cfg.

const Content := preload("res://scripts/content.gd")

## Loaded from content/opponents.cfg.
static var _data: Dictionary = Content.table("opponents")
static var NAMES: Array = _data.get("opponents", {}).get("names", ["CPU"])
static var COLORS: Array = _data.get("opponents", {}).get("colors", [Color8(248, 72, 112)])
static var BOSSES: Array = _data.get("bosses", {}).get("names", ["BOSS"])
static var BOSS_COLOR: Color = _data.get("bosses", {}).get("color", Color8(248, 56, 56))


## A new opponent for a level, never the same name or color as the previous one.
static func roll(rng: RandomNumberGenerator, boss: bool, previous: Dictionary = {}) -> Dictionary:
	var names: Array = BOSSES if boss else NAMES
	var name: String = names[rng.randi_range(0, names.size() - 1)]
	while names.size() > 1 and name == previous.get("name", ""):
		name = names[rng.randi_range(0, names.size() - 1)]
	var color: Color = BOSS_COLOR
	if not boss:
		color = COLORS[rng.randi_range(0, COLORS.size() - 1)]
		while COLORS.size() > 1 and color == previous.get("color", Color.BLACK):
			color = COLORS[rng.randi_range(0, COLORS.size() - 1)]
	return {"name": name, "color": color}
