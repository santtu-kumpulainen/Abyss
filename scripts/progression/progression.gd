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
## tier. In headless runs (the test suites) progression starts fresh and
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
func select(tier: int, pact: StringName = &"") -> bool:
	if not is_unlocked(tier) or (not pact.is_empty() and not Pacts.PACTS.has(pact)):
		return false
	selected_difficulty = tier
	selected_pact = pact
	return true


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
	return config.save(save_path)


## Loads `save_path` (missing file = fresh progression). Invalid values are ignored.
func load_progress() -> void:
	completions.clear()
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	for tier: int in Difficulty.TIERS:
		var count = config.get_value("completions", Difficulty.display_name(tier).to_lower(), 0)
		if count is int and count > 0:
			completions[tier] = count
	unlocks_changed.emit()


## Forgets all progress in memory and resets the selection (does not save).
func clear_progress() -> void:
	completions.clear()
	selected_difficulty = Difficulty.Tier.NORMAL
	selected_pact = &""
	unlocks_changed.emit()
