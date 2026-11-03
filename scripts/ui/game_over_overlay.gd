class_name GameOverOverlay
extends CanvasLayer
## Game Over screen: hidden until `player` emits `died`, then shows the run's
## difficulty and Pact (when inside a Dungeon), a Restart button (focused, so
## Enter/Space work) that reloads the current scene from its saved state (the
## Dungeon reuses the selected difficulty and Pact) and a Main Menu button.
## Dying never unlocks a difficulty.

## The character whose `died` signal shows the overlay (e.g. the Mage).
@export var player: Node
## Scene loaded by Main Menu (a path, so the menu and dungeon can reference each other).
@export_file("*.tscn") var main_menu_scene: String = "res://scenes/ui/main_menu.tscn"

@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _run_info: Label = %RunInfo


func _ready() -> void:
	hide()
	_restart_button.pressed.connect(restart)
	_main_menu_button.pressed.connect(main_menu)
	if player == null or not player.has_signal(&"died"):
		push_warning("GameOverOverlay has no player with a 'died' signal: %s" % get_path())
		return
	player.died.connect(_on_player_died)


## Reloads the current scene, resetting every character, health bar and projectile.
func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene)


## "Difficulty: Hard   Pact: Avarice" plus a no-unlock note, or "" outside a Dungeon.
func run_info_text() -> String:
	var dungeon := get_parent() as Dungeon
	if dungeon == null:
		return ""
	return "Difficulty: %s   Pact: %s\nDefeat the Abyss Warden to unlock the next difficulty." % [
		Difficulty.display_name(dungeon.run_state.difficulty), Pacts.pact_name(dungeon.run_state.pact)]


func _on_player_died() -> void:
	_run_info.text = run_info_text()
	_run_info.visible = not _run_info.text.is_empty()
	show()
	_restart_button.grab_focus()
