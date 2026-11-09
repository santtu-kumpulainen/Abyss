class_name RunHud
extends CanvasLayer
## Shows the run's level, XP progress and currency, e.g. "Lv 2   XP 30/100   Gold 15",
## or "Lv 3 (MAX)   Gold 15" at the level cap, and the collected run items
## (and lasting treasure bonuses) with their effects below it. show_message() briefly shows a centred
## announcement (e.g. level-up unlocks). The top-right status block shows the
## run's dungeon level / biome, timers, difficulty, Pact (benefit / drawback)
## and active synergies. Below the level line, the objective line shows the
## level's Ancient Seal progress and what still keeps the boss gate shut.

## Seconds a message stays fully visible before fading out.
@export var message_duration: float = 3.0

@onready var _label: Label = %RunLabel
@onready var _message: Label = %MessageLabel
@onready var _items: Label = %ItemsLabel
@onready var _status: Label = %StatusLabel
@onready var _objective: Label = %ObjectiveLabel

var _run_state: RunState
var _message_tween: Tween
var _shown_second := -1


## Displays `run_state` and follows its changes.
func set_run_state(run_state: RunState) -> void:
	if _run_state and _run_state.changed.is_connected(_refresh):
		_run_state.changed.disconnect(_refresh)
	_run_state = run_state
	_run_state.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	# The timer line only changes once a second.
	if _run_state and int(_run_state.run_time) != _shown_second:
		_refresh()


## Level, timers, difficulty, Pact and active synergy lines for the status block.
static func status_text(run_state: RunState) -> String:
	var lines: Array[String] = [
		"Level %d - %s%s" % [run_state.dungeon_level, Biomes.biome_name(run_state.dungeon_level),
				" (practice)" if run_state.is_replay else ""],
		"Time %s (level %s)" % [RunState.format_time(run_state.run_time), RunState.format_time(run_state.level_time)],
		"Difficulty: %s" % Difficulty.display_name(run_state.difficulty),
		"Pact: %s" % Pacts.pact_text(run_state.pact),
	]
	for id: StringName in run_state.active_synergies():
		lines.append("Synergy - %s" % Pacts.synergy_text(id))
	if run_state.gold_damage_bonus() > 0.0:
		lines.append("Greed's Reward bonus: +%d%% damage" % roundi(run_state.gold_damage_bonus() * 100.0))
	return "
".join(lines)


## Objective line: Ancient Seals x/3 and what the boss gate still needs.
static func objective_text(run_state: RunState) -> String:
	var seals := "Ancient Seals %d/%d" % [run_state.seals_collected(), RunState.SEALS_REQUIRED]
	if not run_state.seals_complete():
		return "%s - break them to open the Warden's gate" % seals
	if not run_state.is_max_level():
		return "%s - reach Lv %d to open the Warden's gate" % [seals, run_state.max_level()]
	return "%s - the Warden's gate is open" % seals


## " x2" for stacks of two or more, "" for a single copy.
static func _stack_text(count: int) -> String:
	return " x%d" % count if count > 1 else ""


func _refresh() -> void:
	_shown_second = int(_run_state.run_time)
	_status.text = status_text(_run_state)
	_objective.text = objective_text(_run_state)
	var item_lines: Array[String] = []
	for id: StringName in _run_state.collected:
		item_lines.append("%s%s (%s)" % [RunState.ITEMS[id]["name"], _stack_text(_run_state.collected[id]), RunState.ITEMS[id]["effect"]])
	# Treasures with lasting stat bonuses are listed like items.
	for id: StringName in _run_state.treasures:
		var data: Dictionary = RunState.TREASURES[id]
		if RunState.STAT_KEYS.any(func(key: String) -> bool: return data.has(key)):
			item_lines.append("%s%s (%s)" % [data["name"], _stack_text(_run_state.treasures[id]), data["effect"]])
	_items.text = "
".join(item_lines)
	_items.visible = not item_lines.is_empty()
	if _run_state.is_max_level():
		_label.text = "Lv %d (MAX)   Gold %d" % [_run_state.level, _run_state.currency]
		return
	_label.text = "Lv %d   XP %d/%d   Gold %d" % [
		_run_state.level, _run_state.xp, _run_state.xp_to_next_level(), _run_state.currency]


## Shows `text` centred near the top, then fades it out.
func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_message.show()
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(message_duration)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)
	_message_tween.tween_callback(_message.hide)
