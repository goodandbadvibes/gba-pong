extends RefCounted
## Relics: powerful run-long modifiers bought with gems in the shop. Each can be owned once per run.

const DEFS := {
	"hive": {"name": "HIVE MIND", "price": 12, "color": Color8(248, 200, 72),
		"desc": "YOUR TURRETS USE YOUR UPGRADES: FLAME, SLIME AND POWER HIT.",
		"icon": ["01110", "10101", "11111", "10101", "01110"]},
	"sync": {"name": "WING SYNC", "price": 12, "color": Color8(120, 200, 248),
		"desc": "YOUR WINGMEN USE YOUR UPGRADES: FLAME, SLIME AND POWER HIT.",
		"icon": ["10001", "11011", "01110", "11011", "10001"]},
	"virulent": {"name": "VIRULENT", "price": 14, "color": Color8(176, 248, 72),
		"desc": "BURN AND SLIME LAST 50% LONGER AND HIT 50% HARDER.",
		"icon": ["00100", "01110", "10101", "01110", "00100"]},
	"splitter": {"name": "SPLITTER", "price": 15, "color": Color8(248, 248, 248),
		"desc": "EACH HIT FROM YOUR PADDLE HAS A CHANCE TO SPLIT OFF AN EXTRA BALL.",
		"icon": ["10001", "01010", "00100", "01010", "10001"]},
	"momentum": {"name": "MOMENTUM", "price": 12, "color": Color8(248, 136, 72),
		"desc": "+6% PADDLE SIZE AND SPEED FOR EACH GAME WON IN A ROW. LOSING A GAME RESETS IT.",
		"icon": ["00100", "00110", "11111", "00110", "00100"]},
	"plating": {"name": "THICK PLATING", "price": 8, "color": Color8(168, 168, 200),
		"desc": "YOUR WINGMEN AND TURRETS TAKE ONE MORE HIT.",
		"icon": ["11111", "10001", "10101", "10001", "11111"]},
	"repair": {"name": "QUICK REPAIR", "price": 8, "color": Color8(96, 232, 168),
		"desc": "DESTROYED TURRETS COME BACK TWICE AS FAST.",
		"icon": ["00100", "00100", "11111", "00100", "00100"]},
	"second": {"name": "SECOND WIND", "price": 20, "color": Color8(248, 120, 168),
		"desc": "ONCE PER RUN, LOSING A ROUND DOES NOT END THE RUN.",
		"icon": ["01010", "11111", "11111", "01110", "00100"]},
	"tithe": {"name": "GEM TITHE", "price": 10, "color": Color8(96, 232, 232),
		"desc": "+2 GEMS FOR EVERY ROUND YOU CLEAR.",
		"icon": ["00100", "01110", "11111", "01110", "00100"]},
}


## Picks up to count relics the run does not own yet.
static func offers(rng: RandomNumberGenerator, owned: Array, count: int = 3) -> Array[String]:
	var pool: Array[String] = []
	for id in DEFS:
		if not owned.has(id):
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, count)


static func price(id: String, percent: float) -> int:
	return maxi(1, roundi(DEFS[id].price * percent / 100.0))
