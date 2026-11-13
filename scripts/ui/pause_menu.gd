class_name PauseMenu
extends CanvasLayer
## ESC pause menu (Issue #58): pauses the SceneTree and offers Resume, Restart
## and Main Menu. Runs while paused (process_mode ALWAYS). ESC ("ui_cancel")
## toggles it, but only opens during live play: not while the tree is already
## paused by something else (relic choice / victory), after the Mage died
## (Game Over owns the screen) or once the run's victory started. With an Anvil
## menu open, ESC first closes that menu (close_active_menu()). Restart and
## Main Menu unpause first, like GameOverOverlay, so no stale paused state or
## background gameplay survives the scene change.

## Scene loaded by Main Menu (a path, so the menu and dungeon can reference each other).
@export_file("*.tscn") var main_menu_scene: String = "res://scenes/ui/main_menu.tscn"

@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton

## True while this menu paused the game (guards against double open / close).
var _open := false
## Set once Restart / Main Menu was chosen, so nothing reopens during the scene change.
var _leaving := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_resume_button.pressed.connect(resume)
	_restart_button.pressed.connect(restart)
	_main_menu_button.pressed.connect(main_menu)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	if _open:
		resume()
		get_viewport().set_input_as_handled()
	elif close_active_menu() or open():
		get_viewport().set_input_as_handled()


## Closes an open in-room menu (an UpgradeStation / Anvil) instead of pausing,
## so the first ESC backs out of the shop and the next one pauses. Only while
## the game is not paused. Returns true if a menu was closed.
func close_active_menu() -> bool:
	var dungeon := get_parent() as Dungeon
	if _open or dungeon == null or dungeon.current_room == null or get_tree().paused:
		return false
	for node in dungeon.current_room.find_children("*", "UpgradeStation", true, false):
		var station := node as UpgradeStation
		if station.is_open:
			station.set_open(false)
			return true
	return false


func is_open() -> bool:
	return _open


## True when the game may be paused now (live play, nothing else owns the screen).
func can_open() -> bool:
	if _open or _leaving or not is_inside_tree() or get_tree().paused:
		return false
	var dungeon := get_parent() as Dungeon
	if dungeon:
		return not dungeon.victory and not dungeon.mage.is_dead() and not dungeon.is_transitioning()
	return true


## Pauses the game and shows the menu. Returns false if it cannot open now.
func open() -> bool:
	if not can_open():
		return false
	_open = true
	get_tree().paused = true
	show()
	_resume_button.grab_focus()
	return true


## Hides the menu and unpauses. Does nothing unless this menu is open.
func resume() -> void:
	if not _open:
		return
	_open = false
	hide()
	get_tree().paused = false


## Reloads the run from scratch (fresh RunState, same difficulty and Pact).
func restart() -> void:
	_leave()
	get_tree().reload_current_scene()


func main_menu() -> void:
	_leave()
	get_tree().change_scene_to_file(main_menu_scene)


func _leave() -> void:
	_leaving = true
	_open = false
	hide()
	get_tree().paused = false
