class_name Mage
extends CharacterBody2D
## Playable Mage: WASD movement with 8-direction idle/walk animations, and a
## SpellCaster that fires its equipped Spell toward the mouse while "attack"
## is held. Animations are named "<action>_<direction>" (see mage.tres).
## Takes damage via take_damage(); on death input stops and `died` is emitted.

signal died

## Clockwise from east, matching Vector2.angle() in 45° steps.
const DIRECTIONS: Array[StringName] = [
	&"east", &"south_east", &"south", &"south_west",
	&"west", &"north_west", &"north", &"north_east",
]

## Movement speed in pixels per second.
@export var speed: float = 130.0

## Sprite scale. The feet stay at the node origin at any scale.
@export var sprite_scale: float = 0.5:
	set(value):
		sprite_scale = value
		if is_node_ready():
			_apply_scale()

## Height of the cast point above the feet, in unscaled sprite pixels.
@export var cast_height: float = 54.0:
	set(value):
		cast_height = value
		if is_node_ready():
			_apply_scale()

var facing: StringName = &"south"
## Run modifier applied on top of `speed` (set by the Dungeon from RunState).
var speed_multiplier := 1.0

@onready var caster: SpellCaster = $SpellCaster
@onready var health: Health = $Health
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_apply_scale()
	health.died.connect(_on_died)
	_play(&"idle")


func _physics_process(_delta: float) -> void:
	# get_vector() clamps length to 1, so diagonals are not faster.
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = input * speed * speed_multiplier
	move_and_slide()

	if input != Vector2.ZERO:
		facing = direction_name(input)

	if Input.is_action_pressed(&"attack"):
		var target := get_global_mouse_position()
		# No cast animation exists; when standing still, turn toward the aim.
		if caster.try_cast(target) and input == Vector2.ZERO:
			facing = direction_name(target - caster.global_position)

	_play(&"idle" if input == Vector2.ZERO else &"walk")


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	if not health.is_dead():
		_sprite.modulate = Color(1.0, 0.4, 0.4)
		create_tween().tween_property(_sprite, ^"modulate", Color.WHITE, 0.15)


func is_dead() -> bool:
	return health.is_dead()


## Maps a vector to one of the eight direction names.
static func direction_name(v: Vector2) -> StringName:
	return DIRECTIONS[wrapi(roundi(v.angle() / (PI / 4.0)), 0, DIRECTIONS.size())]


func _play(action: StringName) -> void:
	var anim := StringName("%s_%s" % [action, facing])
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
	else:
		push_warning("Mage animation not found: %s" % anim)


func _on_died() -> void:
	# No death animation or game-over flow yet: stop and dim.
	velocity = Vector2.ZERO
	set_physics_process(false)
	_play(&"idle")
	_sprite.modulate = Color(0.5, 0.5, 0.5, 0.7)
	died.emit()


func _apply_scale() -> void:
	_sprite.scale = Vector2.ONE * sprite_scale
	caster.position = Vector2(0.0, -cast_height * sprite_scale)
