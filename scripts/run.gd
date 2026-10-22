extends RefCounted
## One roguelite run (level, games in the current round, upgrades) plus the saved best and gem total.

const SAVE_PATH := "user://save.cfg"
const GEMS_PER_ROUND := 2
const GEMS_PER_BOSS := 5

## Off in tests, so they neither load nor overwrite the player's save.
var persist: bool = true

var level: int = 1
var cleared: int = 0
var bosses: int = 0
var shards: int = 0
var stacks: Dictionary = {}
var games: Array[int] = [0, 0]

var best_cleared: int = 0
var gems: int = 0


func start() -> void:
	level = 1
	cleared = 0
	bosses = 0
	shards = 0
	stacks = {}
	games.assign([0, 0])


func stack(id: String) -> int:
	return stacks.get(id, 0)


func add(id: String) -> void:
	stacks[id] = stack(id) + 1


static func is_boss(lvl: int, every: int) -> bool:
	return every > 0 and lvl % every == 0


## Records a cleared round and moves to the next level.
func clear_round(boss_every: int) -> void:
	if is_boss(level, boss_every):
		bosses += 1
	cleared += 1
	level += 1


func reward() -> Dictionary:
	var rounds: int = cleared * GEMS_PER_ROUND
	var boss: int = bosses * GEMS_PER_BOSS
	return {"rounds": rounds, "bosses": boss, "shards": shards, "total": rounds + boss + shards}


## Ends the run: banks the gems, updates the best and saves. Returns the reward plus "new_best".
func finish() -> Dictionary:
	var result: Dictionary = reward()
	result["new_best"] = cleared > best_cleared
	best_cleared = maxi(best_cleared, cleared)
	gems += result.total
	save()
	return result


func reset_save() -> void:
	best_cleared = 0
	gems = 0
	save()


func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("save", "best_cleared", best_cleared)
	cfg.set_value("save", "gems", gems)
	cfg.save(SAVE_PATH)


func load_saved() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_cleared = int(cfg.get_value("save", "best_cleared", 0))
		gems = int(cfg.get_value("save", "gems", 0))
