extends RefCounted
## Opponent identities: every level brings a new named opponent with its own color.
## Boss levels draw from their own list and are always boss red.

const NAMES := [
	"BIT BARON", "PIXEL PUNK", "VOLT VIPER", "SYNTH SNAKE", "GLITCH GOLEM", "CHIP CHAMP",
	"LAG LORD", "NEON NOMAD", "DATA DUKE", "BYTE BANDIT", "SPRITE SHADE", "RETRO REX",
	"WAVE WITCH", "MODEM MOTH", "CACHE CRAB", "HEX HOUND",
]
const BOSSES := ["THE MAINFRAME", "KERNEL KING", "OVERCLOCK", "BLUE SCREEN", "NULL EMPRESS"]
## Kept clear of the player's orange so the two sides never look alike.
const COLORS := [
	Color8(248, 72, 112), Color8(120, 200, 248), Color8(168, 104, 248), Color8(88, 216, 104),
	Color8(248, 120, 200), Color8(96, 232, 232), Color8(232, 232, 96), Color8(200, 160, 248),
	Color8(160, 232, 168), Color8(248, 200, 216),
]
const BOSS_COLOR := Color8(248, 56, 56)


## A new opponent for a level, never the same name or color as the previous one.
static func roll(rng: RandomNumberGenerator, boss: bool, previous: Dictionary = {}) -> Dictionary:
	var names: Array = BOSSES if boss else NAMES
	var name: String = names[rng.randi_range(0, names.size() - 1)]
	while names.size() > 1 and name == previous.get("name", ""):
		name = names[rng.randi_range(0, names.size() - 1)]
	var color: Color = BOSS_COLOR
	if not boss:
		color = COLORS[rng.randi_range(0, COLORS.size() - 1)]
		while color == previous.get("color", Color.BLACK):
			color = COLORS[rng.randi_range(0, COLORS.size() - 1)]
	return {"name": name, "color": color}
