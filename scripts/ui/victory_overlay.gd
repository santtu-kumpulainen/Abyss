class_name VictoryOverlay
extends CanvasLayer
## Boss reward screen, opened by the Dungeon after each level's boss dies.
## Pauses the game (this layer keeps processing) and offers one relic from the
## level's biome pool (Biomes.relic_pool). Confirming a choice unpauses the
## game and starts the next dungeon level (Dungeon.advance_level()); the run
## itself only ends through Game Over. Relic buttons name the synergies they
## would complete.

## Opened, waiting for a relic choice.
signal relic_choice_shown
## Relic chosen and the next level started.
signal level_continued

var is_open := false
var dungeon: Dungeon

@onready var _subtitle: Label = %Subtitle
@onready var _relic_choices: VBoxContainer = %RelicChoices


func _ready() -> void:
	hide()


## Shows the relic choice and pauses the game. Only the first call per boss does anything.
func open(p_dungeon: Dungeon) -> void:
	if is_open:
		return
	is_open = true
	dungeon = p_dungeon
	get_tree().paused = true
	var level := dungeon.run_state.dungeon_level
	_subtitle.text = "Level %d cleared! Choose one relic:" % level
	for child in _relic_choices.get_children():
		_relic_choices.remove_child(child)
		child.queue_free()
	for id in Biomes.relic_pool(level):
		var data: Dictionary = RunState.RELICS[id]
		var button := Button.new()
		button.name = String(id)
		button.text = "%s  -  %s" % [data["name"], data["effect"]]
		var completes: Array = dungeon.run_state.synergies_completed_by(id).map(
				func(s: StringName) -> String: return Pacts.SYNERGIES[s]["name"])
		if not completes.is_empty():
			button.text += "  [completes synergy: %s]" % ", ".join(completes)
		button.custom_minimum_size = Vector2(360, 40)
		button.add_theme_font_size_override(&"font_size", 20)
		button.pressed.connect(choose_relic.bind(id))
		_relic_choices.add_child(button)
	show()
	(_relic_choices.get_child(0) as Button).grab_focus()
	relic_choice_shown.emit()


## Chooses relic `id` through the run's RunState, closes the screen and starts
## the next level. Returns false if the choice was rejected (not open, a relic
## was already chosen for this boss, or `id` is not offered).
func choose_relic(id: StringName) -> bool:
	if not is_open or dungeon == null or not _relic_choices.has_node(NodePath(String(id))):
		return false
	if not dungeon.run_state.choose_relic(id):
		return false
	is_open = false
	hide()
	get_tree().paused = false
	dungeon.advance_level()
	level_continued.emit()
	return true
