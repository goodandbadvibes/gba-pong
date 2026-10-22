extends RefCounted
## One roguelite run (level, games in the current round, upgrades, relics) plus the saved
## best run and gem wallet. Gems are credited as they are earned so the shop can spend them mid-run.
## A run can be suspended to the save file and continued later.

const SAVE_PATH := "user://save.cfg"
const GEMS_PER_ROUND := 2
const GEMS_PER_BOSS := 5
const GEMS_TITHE := 2

## Off in tests, so they neither load nor overwrite the player's save.
var persist: bool = true

var level: int = 1
var cleared: int = 0
var bosses: int = 0
var shards: int = 0
var tithe: int = 0
var stacks: Dictionary = {}
var relics: Array[String] = []
var games: Array[int] = [0, 0]
## Games won in a row (MOMENTUM relic).
var streak: int = 0
var second_wind_used: bool = false
var shop_pending: bool = false

var best_cleared: int = 0
var gems: int = 0
var suspended: Dictionary = {}


func start() -> void:
	level = 1
	cleared = 0
	bosses = 0
	shards = 0
	tithe = 0
	stacks = {}
	relics.clear()
	games.assign([0, 0])
	streak = 0
	second_wind_used = false
	shop_pending = false
	suspended = {}
	save()


func stack(id: String) -> int:
	return stacks.get(id, 0)


func add(id: String) -> void:
	stacks[id] = stack(id) + 1


func has_relic(id: String) -> bool:
	return relics.has(id)


static func is_boss(lvl: int, every: int) -> bool:
	return every > 0 and lvl % every == 0


## Records a cleared round, credits its gems and moves to the next level.
func clear_round(boss_every: int, shop_every: int) -> void:
	var earned: int = GEMS_PER_ROUND
	if is_boss(level, boss_every):
		bosses += 1
		earned += GEMS_PER_BOSS
	if has_relic("tithe"):
		tithe += GEMS_TITHE
		earned += GEMS_TITHE
	gems += earned
	cleared += 1
	level += 1
	shop_pending = shop_every > 0 and cleared % shop_every == 0
	save()


func add_shards(value: int) -> void:
	shards += value
	gems += value


func buy(id: String, cost: int) -> bool:
	if has_relic(id) or gems < cost:
		return false
	gems -= cost
	relics.append(id)
	save()
	return true


func reward() -> Dictionary:
	var rounds: int = cleared * GEMS_PER_ROUND
	var boss: int = bosses * GEMS_PER_BOSS
	return {"rounds": rounds, "bosses": boss, "shards": shards, "tithe": tithe,
		"total": rounds + boss + shards + tithe}


## Ends the run: updates the best and saves (gems were already credited). Returns the reward plus "new_best".
func finish() -> Dictionary:
	var result: Dictionary = reward()
	result["new_best"] = cleared > best_cleared
	best_cleared = maxi(best_cleared, cleared)
	suspended = {}
	save()
	return result


func to_dict() -> Dictionary:
	return {"level": level, "cleared": cleared, "bosses": bosses, "shards": shards, "tithe": tithe,
		"stacks": stacks.duplicate(), "relics": relics.duplicate(), "streak": streak,
		"second_wind_used": second_wind_used, "shop_pending": shop_pending}


func from_dict(d: Dictionary) -> void:
	level = int(d.get("level", 1))
	cleared = int(d.get("cleared", 0))
	bosses = int(d.get("bosses", 0))
	shards = int(d.get("shards", 0))
	tithe = int(d.get("tithe", 0))
	stacks = Dictionary(d.get("stacks", {})).duplicate()
	relics.assign(d.get("relics", []))
	streak = int(d.get("streak", 0))
	second_wind_used = bool(d.get("second_wind_used", false))
	shop_pending = bool(d.get("shop_pending", false))
	games.assign([0, 0])


func suspend() -> void:
	suspended = to_dict()
	save()


func can_continue() -> bool:
	return not suspended.is_empty()


func resume() -> void:
	from_dict(suspended)
	suspended = {}
	save()


func reset_save() -> void:
	best_cleared = 0
	gems = 0
	suspended = {}
	save()


func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("save", "best_cleared", best_cleared)
	cfg.set_value("save", "gems", gems)
	cfg.set_value("save", "suspended", suspended)
	cfg.save(SAVE_PATH)


func load_saved() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_cleared = int(cfg.get_value("save", "best_cleared", 0))
		gems = int(cfg.get_value("save", "gems", 0))
		suspended = cfg.get_value("save", "suspended", {})
