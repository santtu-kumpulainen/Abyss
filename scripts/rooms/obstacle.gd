@tool
class_name Obstacle
extends StaticBody2D
## Solid room prop (grave, crate, rock...). The node origin is the prop's base:
## the sprite is drawn above it and a small rectangular footprint around it
## blocks characters and projectiles (world layer), so only the base of tall
## art is solid. Use a plain Sprite2D for decorations that should not block.

@export var texture: Texture2D:
	set(value):
		texture = value
		_apply()
## Optional sub-region of `texture` (e.g. one prop from a sheet). Empty = whole texture.
@export var region := Rect2():
	set(value):
		region = value
		_apply()
@export var sprite_scale: float = 1.0:
	set(value):
		sprite_scale = value
		_apply()
## Texture pixels the sprite's bottom edge sits below the origin (art often has
## transparent padding or a shadow under the base).
@export var bottom_padding: float = 0.0:
	set(value):
		bottom_padding = value
		_apply()
## Size of the solid footprint, centred on the origin.
@export var footprint := Vector2(32, 16):
	set(value):
		footprint = value
		_apply()

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	_sprite.texture = texture
	_sprite.region_enabled = region.has_area()
	_sprite.region_rect = region
	_sprite.scale = Vector2.ONE * sprite_scale
	var height: float = region.size.y if region.has_area() else (float(texture.get_height()) if texture else 0.0)
	_sprite.offset = Vector2(0.0, -height / 2.0 + bottom_padding)
	# The shape is local_to_scene in obstacle.tscn, so each instance owns a copy.
	(_shape.shape as RectangleShape2D).size = footprint
