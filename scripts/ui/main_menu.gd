class_name MainMenu
extends Control
## Minimal main menu: Start Run loads `dungeon_scene` as a fresh run (its
## RunState is created with the scene), Quit closes the game.

@export var dungeon_scene: PackedScene

@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	# A previous run may have ended paused (victory screen).
	get_tree().paused = false
	_start_button.pressed.connect(start_run)
	_quit_button.pressed.connect(get_tree().quit)
	_start_button.grab_focus()


func start_run() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_packed(dungeon_scene)
