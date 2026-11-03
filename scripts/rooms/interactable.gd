class_name Interactable
extends Area2D
## Base for small room objects the Mage uses with "interact" (E), like the
## anvil: while a "player" body is within `interact_radius` a prompt label
## (prompt_text()) is shown above the object, and pressing E calls interact()
## when can_interact(). Builds its own collision shape and prompt, so scenes
## only need the node with a subclass script. Subclasses draw themselves.

signal interacted

## Interaction range in pixels.
@export var interact_radius: float = 56.0
## Prompt height above the object's origin.
@export var prompt_height: float = 72.0

var player_near := false

var _prompt: Label


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interact_radius
	shape.shape = circle
	add_child(shape)
	_prompt = Label.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-150.0, -prompt_height)
	_prompt.size = Vector2(300.0, 24.0)
	_prompt.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.55))
	_prompt.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override(&"outline_size", 4)
	_prompt.add_theme_font_size_override(&"font_size", 16)
	add_child(_prompt)
	body_entered.connect(_on_body.bind(true))
	body_exited.connect(_on_body.bind(false))
	refresh()


func _exit_tree() -> void:
	# Leaving the room (transition/restart) clears the "near" state.
	player_near = false
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if player_near and event.is_action_pressed(&"interact") and can_interact():
		get_viewport().set_input_as_handled()
		interact()


## True when interact() would do something.
func can_interact() -> bool:
	return true


## Uses the object. Returns true if something happened.
func interact() -> bool:
	interacted.emit()
	return true


## Prompt shown while the player is near ("" hides it).
func prompt_text() -> String:
	return ""


## Updates the prompt and redraws.
func refresh() -> void:
	if _prompt:
		_prompt.text = prompt_text()
		_prompt.visible = player_near and not _prompt.text.is_empty()
	queue_redraw()


## The Room this object belongs to (nearest Room ancestor), or null.
func find_room() -> Room:
	var node := get_parent()
	while node and not node is Room:
		node = node.get_parent()
	return node as Room


func _on_body(body: Node2D, entered: bool) -> void:
	if body.is_in_group(&"player"):
		player_near = entered
		refresh()
