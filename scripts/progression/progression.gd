class_name ProgressionStore
extends Node
## Autoload "Progression" (access it with ProgressionStore.instance(), which
## also works in --script test runs where the global name cannot be compiled): permanent progression (difficulty unlocks and
## completion counts, saved to `save_path`) plus the selection for the next run
## (difficulty and Pact, kept in memory only). The Dungeon reads the selection
## when it is created, so Restart / New Run reuse it; RunState holds all
## run-specific state and is recreated with the scene.
##
## Victories are recorded through record_victory(); nothing else unlocks a
## tier. Run records: record_run() keeps the best endless run (highest dungeon
## level, then the earliest time reaching it) and the highest level reached,
## which bounds the start level a replay run may select. Replay runs never
## record anything. In headless runs (the test suites) progression starts fresh and
## saves to TEST_SAVE_PATH, so tests never touch the player's real file.

signal unlocks_changed

const SAVE_PATH := "user://progression.cfg"
const TEST_SAVE_PATH := "user://progression_test.cfg"

var save_path := SAVE_PATH
## Completed runs per tier (tier -> count).
var completions := {}
## Selection for the next run (not saved).
var selected_difficulty: int = Difficulty.Tier.NORMAL
var selected_pact: StringName = &""
## Dungeon level the next run starts at (1 = fresh run; higher = replay run,
## limited to highest_level; not saved).
var selected_start_level: int = 1
## Highest dungeon level reached in a non-replay run.
var highest_level: int = 1
## Best run: {} or {level, time, reach_time, difficulty, biome, run_id}.
var best_run := {}
## Permanent anvil upgrades unlocked for every future run (id -> true), e.g. Twin Cast.
var unlocked_upgrades := {}


static var _fallback: ProgressionStore
var _initialized := false


func _ready() -> void:
	_setup()


## The "Progression" autoload, or (if it is missing, e.g. a test runner that
## starts before autoloads) a shared stand-in that behaves the same.
static func instance(tree: SceneTree) -> ProgressionStore:
	var node: ProgressionStore = null
	if tree:
		node = tree.root.get_node_or_null(^"Progression") as ProgressionStore
	if node:
		node._setup()
		return node
	if _fallback == null:
		_fallback = ProgressionStore.new()
		_fallback._setup()
	return _fallback


func _setup() -> void:
	if _initialized:
		return
	_initialized = true
	if DisplayServer.get_name() == "headless":
		save_path = TEST_SAVE_PATH
		clear_progress()
	else:
		load_progress()


## A tier is unlocked if it has no requirement or its required tier was completed.
func is_unlocked(tier: int) -> bool:
	if not Difficulty.is_valid(tier):
		return false
	var requires: int = Difficulty.data(tier)["requires"]
	return requires < 0 or completion_count(requires) > 0


func completion_count(tier: int) -> int:
	return completions.get(tier, 0)


## Selects the next run's difficulty and Pact (&"" = none). Rejects locked
## tiers and unknown Pacts (the selection is then unchanged).
func select(tier: int, pact: StringName = &"", start_level: int = 1) -> bool:
	if not is_unlocked(tier) or (not pact.is_empty() and not Pacts.PACTS.has(pact)) 			or start_level < 1 or start_level > highest_level:
		return false
	selected_difficulty = tier
	selected_pact = pact
	selected_start_level = start_level
	return true


## Records progress of a (non-replay) run: raises highest_level and updates
## best_run if `level` beats it, or if it is the same level reached sooner
## (`reach_time` = run time on arrival), or if it is the same run progressing
## (`run_id`, then total `time` is refreshed). Saves when anything changed.
## Returns true if best_run changed.
func record_run(run_id: int, level: int, time: float, reach_time: float, tier: int, biome: StringName) -> bool:
	var changed := false
	if level > highest_level:
		highest_level = level
		changed = true
	var better: bool = best_run.is_empty() or level > best_run["level"] 			or (level == best_run["level"] and best_run["run_id"] != run_id and reach_time < best_run["reach_time"])
	var same_run: bool = not best_run.is_empty() and best_run["run_id"] == run_id and level >= best_run["level"]
	if better or same_run:
		var keep_reach: float = best_run["reach_time"] if same_run and level == best_run["level"] else reach_time
		best_run = {"level": level, "time": time, "reach_time": keep_reach, "difficulty": tier,
				"biome": biome, "run_id": run_id}
		changed = true
	if changed:
		save_progress()
		unlocks_changed.emit()
	return changed


func is_upgrade_unlocked(id: StringName) -> bool:
	return unlocked_upgrades.has(id)


## Unlocks permanent upgrade `id` for all future runs and saves. Returns false if
## it is not a permanent upgrade or was already unlocked.
func unlock_upgrade(id: StringName) -> bool:
	if not RunState.UPGRADES.has(id) or not RunState.UPGRADES[id].get("permanent", false) or unlocked_upgrades.has(id):
		return false
	unlocked_upgrades[id] = true
	save_progress()
	unlocks_changed.emit()
	return true


## "Level 5 - Cavern Depths - Hard - 12:34", or "No runs yet".
func best_run_text() -> String:
	if best_run.is_empty():
		return "No runs yet"
	return "Level %d - %s - %s - %s" % [best_run["level"], Biomes.biome_name(best_run["level"]),
			Difficulty.display_name(best_run["difficulty"]), RunState.format_time(best_run["time"])]


## Records a won run on `tier` and saves. Returns the tier this newly
## unlocked, or -1.
func record_victory(tier: int) -> int:
	if not Difficulty.is_valid(tier):
		return -1
	var next := Difficulty.next_tier(tier)
	var was_locked := next >= 0 and not is_unlocked(next)
	completions[tier] = completion_count(tier) + 1
	save_progress()
	unlocks_changed.emit()
	return next if was_locked else -1


func save_progress() -> Error:
	var config := ConfigFile.new()
	for tier: int in Difficulty.TIERS:
		config.set_value("completions", Difficulty.display_name(tier).to_lower(), completion_count(tier))
	config.set_value("records", "highest_level", highest_level)
	for id: StringName in unlocked_upgrades:
		config.set_value("unlocked_upgrades", String(id), true)
	for key: String in best_run:
		config.set_value("best_run", key, best_run[key] if key != "biome" else String(best_run[key]))
	return config.save(save_path)


## Loads `save_path` (missing file = fresh progression). Invalid values are ignored.
func load_progress() -> void:
	completions.clear()
	highest_level = 1
	best_run = {}
	unlocked_upgrades = {}
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	for id: StringName in RunState.UPGRADES:
		if RunState.UPGRADES[id].get("permanent", false) and config.get_value("unlocked_upgrades", String(id), false) == true:
			unlocked_upgrades[id] = true
	var highest = config.get_value("records", "highest_level", 1)
	if highest is int and highest > 1:
		highest_level = highest
	_load_best_run(config)
	for tier: int in Difficulty.TIERS:
		var count = config.get_value("completions", Difficulty.display_name(tier).to_lower(), 0)
		if count is int and count > 0:
			completions[tier] = count
	unlocks_changed.emit()


func _load_best_run(config: ConfigFile) -> void:
	var level = config.get_value("best_run", "level", 0)
	var time = config.get_value("best_run", "time", 0.0)
	var reach = config.get_value("best_run", "reach_time", 0.0)
	var tier = config.get_value("best_run", "difficulty", -1)
	var biome = config.get_value("best_run", "biome", "")
	var run_id = config.get_value("best_run", "run_id", 0)
	if level is int and level >= 1 and (time is float or time is int) and (reach is float or reach is int) 			and tier is int and Difficulty.is_valid(tier) and biome is String and run_id is int:
		best_run = {"level": level, "time": float(time), "reach_time": float(reach), "difficulty": tier,
				"biome": StringName(biome), "run_id": run_id}
		highest_level = maxi(highest_level, level)


## Forgets all progress in memory and resets the selection (does not save).
func clear_progress() -> void:
	completions.clear()
	highest_level = 1
	best_run = {}
	unlocked_upgrades = {}
	selected_start_level = 1
	selected_difficulty = Difficulty.Tier.NORMAL
	selected_pact = &""
	unlocks_changed.emit()
