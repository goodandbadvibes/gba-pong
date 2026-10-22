extends RefCounted
## Roguelite upgrades: one to start each run, then one after each round won. They last for the whole
## run and stack up to "max". The CPU also gains one per level (CPU_EXCLUDED ones never).

const Content := preload("res://scripts/content.gd")

## Loaded from content/upgrades.cfg: id -> {name, max, color, desc, icon, and effect numbers}.
static var DEFS: Dictionary = Content.table("upgrades")


## An effect number for an upgrade from the content file.
static func num(id: String, key: String, fallback: float) -> float:
	return Content.num(DEFS, id, key, fallback)


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
