class_name VictoryOverlay
extends CanvasLayer
## Victory screen, opened once by the Dungeon after the boss dies. Pauses the
## game (this layer keeps processing), offers one relic from RunState.RELICS,
## then shows the run summary with New Run (reloads the dungeon scene) and
## Main Menu (`main_menu_scene`) buttons. Both unpause the game first.

## Opened, waiting for a relic choice.
signal relic_choice_shown
## Relic chosen, summary and actions visible.
signal summary_shown

## Scene loaded by Main Menu (a path, so the menu and dungeon can reference each other).
@export_file("*.tscn") var main_menu_scene: String = "res://scenes/ui/main_menu.tscn"

var is_open := false
var dungeon: Dungeon

@onready var _subtitle: Label = %Subtitle
@onready var _relic_choices: VBoxContainer = %RelicChoices
@onready var _summary: Label = %SummaryLabel
@onready var _actions: Control = %Actions
@onready var _new_run_button: Button = %NewRunButton
@onready var _main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	hide()
	_summary.hide()
	_actions.hide()
	_new_run_button.pressed.connect(new_run)
	_main_menu_button.pressed.connect(main_menu)


## Shows the relic choice and pauses the game. Only the first call does anything.
func open(p_dungeon: Dungeon) -> void:
	if is_open:
		return
	is_open = true
	dungeon = p_dungeon
	get_tree().paused = true
	_subtitle.text = "The Abyss Warden has fallen. Choose one relic:"
	for id: StringName in RunState.RELICS:
		var data: Dictionary = RunState.RELICS[id]
		var button := Button.new()
		button.name = String(id)
		button.text = "%s  -  %s" % [data["name"], data["effect"]]
		button.custom_minimum_size = Vector2(360, 40)
		button.add_theme_font_size_override(&"font_size", 20)
		button.pressed.connect(choose_relic.bind(id))
		_relic_choices.add_child(button)
	show()
	(_relic_choices.get_child(0) as Button).grab_focus()
	relic_choice_shown.emit()


## Chooses relic `id` through the run's RunState, then shows the summary.
## Returns false if the choice was rejected (e.g. a relic was already chosen).
func choose_relic(id: StringName) -> bool:
	if dungeon == null or not dungeon.run_state.choose_relic(id):
		return false
	_relic_choices.hide()
	_subtitle.text = "Run complete!"
	_summary.text = summary_text(dungeon.run_summary())
	_summary.show()
	_actions.show()
	_new_run_button.grab_focus()
	summary_shown.emit()
	return true


func new_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene)


## Formats Dungeon.run_summary() as lines of text.
static func summary_text(summary: Dictionary) -> String:
	var items: Array = summary["items"].map(func(id: StringName) -> String: return RunState.ITEMS[id]["name"])
	var upgrades: Array = summary["upgrades"].map(func(id: StringName) -> String: return RunState.UPGRADES[id]["name"])
	var relic: StringName = summary["relic"]
	return "\n".join([
		"Mage level: %d" % summary["level"],
		"Rooms cleared: %d / %d" % [summary["rooms_cleared"], summary["rooms_total"]],
		"Enemies defeated: %d" % summary["enemies_defeated"],
		"Items: %s" % (", ".join(items) if not items.is_empty() else "none"),
		"Anvil upgrades: %s" % (", ".join(upgrades) if not upgrades.is_empty() else "none"),
		"Relic: %s" % (RunState.RELICS[relic]["name"] if not relic.is_empty() else "none"),
	])
