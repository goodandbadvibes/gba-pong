extends RefCounted
## Roguelite upgrades: one to start each run, then one after each round won. They last for the whole
## run and stack up to "max". The CPU also gains one per level (CPU_EXCLUDED ones never).

const DEFS := {
	"flame": {"name": "FLAME BALL", "max": 3, "color": Color8(248, 128, 32),
		"desc": "BALLS YOU HIT CATCH FIRE. A BURNING HIT SHRINKS THE FOE PADDLE UNTIL THE BURN ENDS.",
		"icon": ["00100", "01100", "01110", "11111", "01110"]},
	"slime": {"name": "SLIME BALL", "max": 3, "color": Color8(120, 232, 72),
		"desc": "BALLS YOU HIT TURN SLIMY. A SLIMY HIT SLOWS THE FOE PADDLE UNTIL IT WEARS OFF.",
		"icon": ["01110", "11111", "11111", "10101", "10101"]},
	"magnet": {"name": "MAGNET BALL", "max": 3, "color": Color8(200, 200, 216),
		"desc": "BALLS YOU HIT PULL IN POWER UPS AND GEMS NEARBY.",
		"icon": ["11011", "11011", "10001", "10001", "01110"]},
	"long": {"name": "LONG PADDLE", "max": 4, "color": Color8(88, 216, 104),
		"desc": "YOUR PADDLE IS 15% TALLER PER LEVEL.",
		"icon": ["01110", "00100", "00100", "00100", "01110"]},
	"power": {"name": "POWER HIT", "max": 4, "color": Color8(248, 216, 72),
		"desc": "BALLS YOU HIT FLY 12% FASTER PER LEVEL.",
		"icon": ["10001", "01010", "11111", "01010", "10001"]},
	"lucky": {"name": "LUCKY FIND", "max": 3, "color": Color8(232, 120, 232),
		"desc": "POWER UPS AND GEMS SHOW UP MORE OFTEN AND GEMS ARE WORTH MORE.",
		"icon": ["01010", "10101", "01110", "00100", "00100"]},
	"wingman": {"name": "WINGMAN", "max": 3, "color": Color8(152, 184, 248),
		"desc": "EVERY GAME STARTS WITH AN EXTRA PADDLE PER LEVEL THAT PATROLS ON ITS OWN.",
		"icon": ["10100", "10101", "10101", "10101", "00101"]},
	"venom": {"name": "VENOM BALL", "max": 3, "color": Color8(176, 96, 248),
		"desc": "BALLS YOU HIT ARE POISONOUS. ENOUGH POISON LEAVES A PATCH ON THE FOE TRACK THAT SLOWS ITS PADDLE.",
		"icon": ["01110", "10101", "11111", "01110", "01010"]},
	"overcharge": {"name": "OVERCHARGE", "max": 3, "color": Color8(248, 248, 120),
		"desc": "EVERY GAME STARTS WITH A BOOSTER: ALL YOUR MODIFIERS HIT HARDER FOR 2 SEC PER LEVEL.",
		"icon": ["00110", "01100", "11111", "00110", "01100"]},
	"factory": {"name": "BALL FACTORY", "max": 3, "color": Color8(232, 232, 232),
		"desc": "EVERY GAME STARTS WITH A BALL GENERATOR ON YOUR SIDE: 2 BALLS, +1 PER EXTRA LEVEL.",
		"icon": ["11111", "10101", "11111", "10001", "11111"]},
	"turret": {"name": "TURRET", "max": 3, "color": Color8(248, 200, 72),
		"desc": "A TURRET PER LEVEL SPEEDS UP YOUR BALLS THAT PASS THROUGH IT. FOE BALLS DAMAGE IT. IT REBUILDS ITSELF.",
		"icon": ["00100", "01110", "11011", "01110", "00100"]},
}


## Upgrades the CPU never gets (it collects no gems, so luck would only help the player).
const CPU_EXCLUDED := ["lucky"]


## Picks up to count different upgrades that are not maxed out yet.
static func offers(rng: RandomNumberGenerator, stacks: Dictionary, count: int = 3, excluded: Array = []) -> Array[String]:
	var pool: Array[String] = []
	for id in DEFS:
		if stacks.get(id, 0) < DEFS[id].max and not excluded.has(id):
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, count)
