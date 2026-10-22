extends RefCounted
## Relics: powerful run-long modifiers bought with gems in the shop. Each can be owned once per run.
## Names, prices, texts, icons and effect numbers live in content/relics.cfg.

const Content := preload("res://scripts/content.gd")

## Loaded from content/relics.cfg: id -> {name, price, color, desc, icon, and effect numbers}.
static var DEFS: Dictionary = Content.table("relics")


## An effect number for a relic from the content file.
static func num(id: String, key: String, fallback: float) -> float:
	return Content.num(DEFS, id, key, fallback)


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
