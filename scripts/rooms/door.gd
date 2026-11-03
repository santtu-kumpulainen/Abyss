class_name Door
extends StaticBody2D
## Room exit. Locked: solid wall (world layer) shown in `locked_color`.
## Unlocked: collision disabled so characters can pass, shown in `open_color`.

@export var locked: bool = false:
	set(value):
		locked = value
		if is_node_ready():
			_apply()

@export var locked_color := Color(0.75, 0.2, 0.2, 1.0)
@export var open_color := Color(0.2, 0.6, 0.3, 0.35)

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _visual: ColorRect = $ColorRect


func _ready() -> void:
	_apply()


func _apply() -> void:
	# Deferred: lock/unlock can happen during physics callbacks.
	_shape.set_deferred(&"disabled", not locked)
	_visual.color = locked_color if locked else open_color
