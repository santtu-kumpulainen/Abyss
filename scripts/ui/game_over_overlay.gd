class_name GameOverOverlay
extends CanvasLayer
## Game Over screen: hidden until `player` emits `died`, then shows a Restart
## button (focused, so Enter/Space work) that reloads the current scene from
## its saved state.

## The character whose `died` signal shows the overlay (e.g. the Mage).
@export var player: Node

@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	hide()
	_restart_button.pressed.connect(restart)
	if player == null or not player.has_signal(&"died"):
		push_warning("GameOverOverlay has no player with a 'died' signal: %s" % get_path())
		return
	player.died.connect(_on_player_died)


## Reloads the current scene, resetting every character, health bar and projectile.
func restart() -> void:
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	show()
	_restart_button.grab_focus()
