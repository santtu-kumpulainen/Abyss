class_name Player
extends CharacterBody2D
## Player character. Visuals come from a swappable SpriteFrames resource whose
## animations are named "<action>_<direction>" (e.g. "idle_down", "walk_left").
## Combat and progression are handled in later Issues.

## Movement speed in pixels per second.
@export var speed: float = 130.0

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


func _physics_process(_delta: float) -> void:
	# get_vector() clamps length to 1, so diagonals are not faster.
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = input * speed
	move_and_slide()

	if input == Vector2.ZERO:
		play_action(&"idle")
	else:
		facing = _direction_from_vector(input)
		play_action(&"walk")


## Maps a movement vector to "left"/"right"/"up"/"down"; horizontal wins ties.
static func _direction_from_vector(v: Vector2) -> StringName:
	if absf(v.x) >= absf(v.y):
		return &"right" if v.x > 0.0 else &"left"
	return &"down" if v.y > 0.0 else &"up"


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
