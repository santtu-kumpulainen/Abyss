class_name Player
extends CharacterBody2D
## Player character. Visuals come from a swappable SpriteFrames resource whose
## animations are named "<action>_<direction>" (e.g. "idle_down", "walk_left").
## Movement, combat and progression are handled in later Issues.

## Animation set for the current visual level (see scenes/player/sprite_frames/).
@export var sprite_frames: SpriteFrames:
	set(value):
		sprite_frames = value
		if is_node_ready():
			_apply_sprite_frames()

## Facing direction: "down", "left", "right" or "up".
var facing: StringName = &"down"

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_apply_sprite_frames()
	play_action(&"idle")


## Plays "<action>_<facing>", e.g. play_action(&"walk") -> "walk_down".
func play_action(action: StringName) -> void:
	var anim := StringName("%s_%s" % [action, facing])
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
	else:
		push_warning("Player animation not found: %s" % anim)


func _apply_sprite_frames() -> void:
	if sprite_frames:
		var current := _sprite.animation
		_sprite.sprite_frames = sprite_frames
		if sprite_frames.has_animation(current):
			_sprite.play(current)
