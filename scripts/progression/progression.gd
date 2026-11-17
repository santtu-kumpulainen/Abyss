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
## Preferences: the ability bar's slot order (Issue #49, `ability_slots`) is
## saved with the progression; invalid saved orders fall back to the default.

signal unlocks_changed

const SAVE_PATH := "user://progression.cfg"
const TEST_SAVE_PATH := "user://progression_test.cfg"
## Records layout in the save: 1 (implicit) = one best_run for all
## difficulties; 2 = Issue #63 per-difficulty "records_<difficulty>" sections.
const RECORDS_FORMAT := 2

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
## Best run over all difficulties: {} or {level, time, reach_time, difficulty,
## biome, run_id, enemies, bosses}.
var best_run := {}
## Per-difficulty records (Issue #63): tier -> that difficulty's best run (same
## keys as best_run; "enemies" / "bosses" are -1 if unknown, e.g. migrated).
var records := {}
## Ability bar slot order: the consumable id in slot 1, 2 and 3 (keys follow
## the slots). Change it with set_ability_slots(). Quantities are never saved.
var ability_slots: Array[StringName] = default_ability_slots()
## A validated RunSave data dictionary the next Dungeon restores instead of
## starting a new run (set by the main menu's Continue; not saved). Taken
## (cleared) by take_pending_resume(), so Restart starts a fresh run.
var pending_resume := {}


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


## Returns and clears the pending resume ({} if none).
func take_pending_resume() -> Dictionary:
	var data := pending_resume
	pending_resume = {}
	return data


## Prepares resuming a saved run (a validated RunSave data dictionary): the
## next Dungeon restores it, and the selection is set to its difficulty, Pact
## and start level so Restart begins a new run with the same setup.
func prepare_resume(data: Dictionary) -> void:
	pending_resume = data
	var run: Dictionary = data["run"]
	selected_difficulty = int(run["difficulty"])
	selected_pact = StringName(run["pact"])
	selected_start_level = clampi(int(run["start_level"]), 1, maxi(highest_level, 1))


## Records progress of a (non-replay) run: raises highest_level and updates
## best_run (all difficulties) and records[tier] (Issue #63: that difficulty
## only) if `level` beats it, or if it is the same level reached sooner
## (`reach_time` = run time on arrival), or if it is the same run progressing
## (`run_id`, then total `time`, `enemies` and `bosses` are refreshed). A
## record on one difficulty never touches another's. `enemies` / `bosses`
## (defeated this run; -1 = unknown) are stored with the record. Saves when
## anything changed. Returns true if the overall best run or highest_level
## changed (as before Issue #63; a difficulty record alone returns false).
func record_run(run_id: int, level: int, time: float, reach_time: float, tier: int, biome: StringName,
		enemies: int = -1, bosses: int = -1) -> bool:
	var changed := false
	if level > highest_level:
		highest_level = level
		changed = true
	var best := _updated_record(best_run, run_id, level, time, reach_time, tier, biome, enemies, bosses)
	if not best.is_empty():
		best_run = best
		changed = true
	var tier_changed := false
	if Difficulty.is_valid(tier):
		var record := _updated_record(records.get(tier, {}), run_id, level, time, reach_time, tier, biome, enemies, bosses)
		if not record.is_empty():
			records[tier] = record
			tier_changed = true
	if changed or tier_changed:
		save_progress()
		unlocks_changed.emit()
	return changed


## The record replacing `old` after this run's progress, or {} if `old` stays.
static func _updated_record(old: Dictionary, run_id: int, level: int, time: float, reach_time: float,
		tier: int, biome: StringName, enemies: int, bosses: int) -> Dictionary:
	var better: bool = old.is_empty() or level > old["level"] \
			or (level == old["level"] and old["run_id"] != run_id and reach_time < old["reach_time"])
	var same_run: bool = not old.is_empty() and old["run_id"] == run_id and level >= old["level"]
	if not better and not same_run:
		return {}
	var keep_reach: float = old["reach_time"] if same_run and level == old["level"] else reach_time
	return {"level": level, "time": time, "reach_time": keep_reach, "difficulty": tier,
			"biome": biome, "run_id": run_id, "enemies": enemies, "bosses": bosses}


## "Level 5 - Cavern Depths - Hard - 12:34", or "No runs yet".
func best_run_text() -> String:
	if best_run.is_empty():
		return "No runs yet"
	return "Level %d - %s - %s - %s" % [best_run["level"], Biomes.biome_name(best_run["level"]),
			Difficulty.display_name(best_run["difficulty"]), RunState.format_time(best_run["time"])]


## Difficulty `tier`'s record ({} if none yet).
func record_for(tier: int) -> Dictionary:
	return records.get(tier, {})


## Forgets every run record (Issue #63): the per-difficulty records, best_run
## and highest_level (the practice start level limit). Difficulty unlocks and
## completion counts, preferences and the unfinished-run save are kept. Saves.
func reset_records() -> Error:
	records.clear()
	best_run = {}
	highest_level = 1
	selected_start_level = 1
	var err := save_progress()
	unlocks_changed.emit()
	return err


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


## Saves everything. The pre-#63 keys ("records/highest_level", "best_run")
## are still written, so an older build reads the file too; per-difficulty
## records go to one "records_<difficulty>" section each.
func save_progress() -> Error:
	var config := ConfigFile.new()
	for tier: int in Difficulty.TIERS:
		config.set_value("completions", Difficulty.display_name(tier).to_lower(), completion_count(tier))
	config.set_value("records", "highest_level", highest_level)
	config.set_value("records", "format", RECORDS_FORMAT)
	config.set_value("preferences", "ability_slots", PackedStringArray(ability_slots))
	_store_record(config, "best_run", best_run)
	for tier: int in records:
		_store_record(config, _record_section(tier), records[tier])
	return config.save(save_path)


## Loads `save_path` (missing file = fresh progression). Invalid values are ignored,
## and so is the legacy "unlocked_upgrades" section (Twin Cast used to be a
## permanent unlock; it is bought per run since Issue #47 and dropped on the next save).
## Records from before Issue #63 (one best_run for all difficulties) are
## migrated: the best run becomes its difficulty's record, nothing is lost.
func load_progress() -> void:
	completions.clear()
	highest_level = 1
	best_run = {}
	records.clear()
	ability_slots = default_ability_slots()
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	var highest = config.get_value("records", "highest_level", 1)
	if highest is int and highest > 1:
		highest_level = highest
	if config.has_section_key("preferences", "ability_slots"):
		ability_slots = parse_ability_slots(config.get_value("preferences", "ability_slots"))
	best_run = _load_record(config, "best_run")
	if not best_run.is_empty():
		highest_level = maxi(highest_level, best_run["level"])
	for tier: int in Difficulty.TIERS:
		var record := _load_record(config, _record_section(tier))
		if not record.is_empty() and record["difficulty"] == tier:
			records[tier] = record
			highest_level = maxi(highest_level, record["level"])
	# Migration (and repair): the overall best run always counts for its difficulty.
	if not best_run.is_empty():
		var tier: int = best_run["difficulty"]
		if records.get(tier, {}).is_empty() or records[tier]["level"] < best_run["level"]:
			records[tier] = best_run.duplicate()
	for tier: int in Difficulty.TIERS:
		var count = config.get_value("completions", Difficulty.display_name(tier).to_lower(), 0)
		if count is int and count > 0:
			completions[tier] = count
	unlocks_changed.emit()


static func _record_section(tier: int) -> String:
	return "records_" + Difficulty.display_name(tier).to_lower()


static func _store_record(config: ConfigFile, section: String, record: Dictionary) -> void:
	for key: String in record:
		config.set_value(section, key, record[key] if key != "biome" else String(record[key]))


## A record section as a dictionary, or {} if it is missing or invalid.
## "enemies" / "bosses" are optional (older records): -1 = unknown.
static func _load_record(config: ConfigFile, section: String) -> Dictionary:
	var level = config.get_value(section, "level", 0)
	var time = config.get_value(section, "time", 0.0)
	var reach = config.get_value(section, "reach_time", 0.0)
	var tier = config.get_value(section, "difficulty", -1)
	var biome = config.get_value(section, "biome", "")
	var run_id = config.get_value(section, "run_id", 0)
	var enemies = config.get_value(section, "enemies", -1)
	var bosses = config.get_value(section, "bosses", -1)
	if not (level is int and level >= 1 and (time is float or time is int) and (reach is float or reach is int) \
			and tier is int and Difficulty.is_valid(tier) and biome is String and run_id is int):
		return {}
	return {"level": level, "time": float(time), "reach_time": float(reach), "difficulty": tier,
			"biome": StringName(biome), "run_id": run_id,
			"enemies": enemies if enemies is int and enemies >= 0 else -1,
			"bosses": bosses if bosses is int and bosses >= 0 else -1}


## Forgets all progress in memory and resets the selection (does not save).
func clear_progress() -> void:
	completions.clear()
	highest_level = 1
	best_run = {}
	records.clear()
	ability_slots = default_ability_slots()
	selected_start_level = 1
	selected_difficulty = Difficulty.Tier.NORMAL
	selected_pact = &""
	pending_resume = {}
	unlocks_changed.emit()


## Default ability bar order: RunState.CONSUMABLES in catalog order
## (Health Potion, Speed Potion, Home Teleport).
static func default_ability_slots() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(RunState.CONSUMABLES.keys())
	return ids


## True if `value` is an array holding every consumable id exactly once (as
## strings): no missing, unknown, duplicate or outdated ids, no other types.
static func is_valid_ability_slots(value: Variant) -> bool:
	var defaults := default_ability_slots()
	if not (value is Array or value is PackedStringArray) or value.size() != defaults.size():
		return false
	var seen: Array[StringName] = []
	for entry: Variant in value:
		if not (entry is String or entry is StringName):
			return false
		var id := StringName(entry)
		if not defaults.has(id) or seen.has(id):
			return false
		seen.append(id)
	return true


## `value` as a slot order if is_valid_ability_slots(), otherwise the default order.
static func parse_ability_slots(value: Variant) -> Array[StringName]:
	if not is_valid_ability_slots(value):
		return default_ability_slots()
	var order: Array[StringName] = []
	for entry: Variant in value:
		order.append(StringName(entry))
	return order


## Sets and saves the ability bar order. Returns false (changing nothing) if
## `order` is not valid (see is_valid_ability_slots()).
func set_ability_slots(order: Array) -> bool:
	if not is_valid_ability_slots(order):
		return false
	ability_slots = parse_ability_slots(order)
	save_progress()
	return true
