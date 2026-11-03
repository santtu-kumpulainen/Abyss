class_name Enemy
extends CharacterBody2D
## Basic melee enemy: chases the nearest node in `target_group` within
## `detection_radius`, stops at `attack_range` and deals contact damage once per
## `attack_cooldown`. Takes damage via take_damage() and is freed at 0 health.
## Visuals come from a SpriteFrames resource with "<action>_<direction>"
## animations (idle/walk x down/left/right/up), or plain "<action>" animations
## when `side_view` is set.

signal died

## Movement speed in pixels per second.
@export var speed: float = 80.0
## Distance at which the enemy notices a target.
@export var detection_radius: float = 260.0
## Distance (between origins) at which the enemy stops and attacks.
@export var attack_range: float = 28.0
## Damage dealt per contact attack.
@export var contact_damage: float = 10.0
## Seconds between contact attacks.
@export var attack_cooldown: float = 1.0
## Group searched for targets.
@export var target_group: StringName = &"player"
## XP granted to the run when this enemy is defeated.
@export var xp_reward: int = 1
## Currency granted to the run when this enemy is defeated.
@export var currency_reward: int = 5
## Elite enemies (e.g. Blood Monster, boss) are affected by elite modifiers
## such as Hunter's Mark.
@export var elite := false

@export var sprite_frames: SpriteFrames:
	set(value):
		sprite_frames = value
		if is_node_ready():
			_sprite.sprite_frames = value

## Sprite scale; feet stay at the node origin (set the sprite offset in the scene).
@export var sprite_scale: float = 0.45:
	set(value):
		sprite_scale = value
		if is_node_ready():
			_sprite.scale = Vector2.ONE * value

## Side-view art (one set of animations drawn facing right, e.g. the Tiny RPG
## packs): animations are named "<action>" and the sprite is mirrored when the
## enemy faces left. Up/down keep the last horizontal facing.
@export var side_view := false

## Facing direction: "down", "left", "right" or "up".
var facing: StringName = &"down"
var target: Node2D
## True once apply_scaling() has run (it only works once per instance).
var scaled := false
## Multiplier on damage taken (set by apply_scaling()).
var damage_taken_multiplier := 1.0

var _attack_cooldown_left := 0.0

@onready var health: Health = $Health
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if sprite_frames:
		_sprite.sprite_frames = sprite_frames
	_sprite.scale = Vector2.ONE * sprite_scale
	health.died.connect(_on_died)
	_play(&"idle")


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	target = _find_target()
	velocity = Vector2.ZERO

	if target:
		var to_target := target.global_position - global_position
		facing = direction_name(to_target)
		if to_target.length() > attack_range:
			velocity = to_target.normalized() * speed
		elif _attack_cooldown_left <= 0.0:
			_attack_cooldown_left = attack_cooldown
			target.take_damage(contact_damage)

	move_and_slide()
	_play(&"walk" if velocity != Vector2.ZERO else &"idle")


## Applies run scaling once (call after _ready, before the enemy is damaged):
## max/current HP x `health_mult`, every damage source x `damage_mult`, move
## speed and attack rate x `pace_mult`, damage taken x `vulnerability`.
## Returns false (and changes nothing) if this enemy was already scaled.
func apply_scaling(health_mult: float, damage_mult: float, pace_mult: float = 1.0, vulnerability: float = 1.0) -> bool:
	if scaled:
		return false
	scaled = true
	health.scale_max_health(health_mult)
	damage_taken_multiplier = vulnerability
	speed *= pace_mult
	attack_cooldown /= maxf(pace_mult, 0.01)
	_scale_attacks(damage_mult, pace_mult)
	return true


## Scales this enemy's damage (subclasses add their own attacks).
func _scale_attacks(damage_mult: float, _pace_mult: float) -> void:
	contact_damage *= damage_mult


func take_damage(amount: float) -> void:
	health.take_damage(amount * damage_taken_multiplier)
	if not health.is_dead():
		_flash()


## Maps a vector to "left"/"right"/"up"/"down" using the dominant axis;
## horizontal wins ties.
static func direction_name(v: Vector2) -> StringName:
	if absf(v.x) >= absf(v.y):
		return &"right" if v.x > 0.0 else &"left"
	return &"down" if v.y > 0.0 else &"up"


## Nearest living, damageable target within detection_radius, or null.
func _find_target() -> Node2D:
	var best: Node2D = null
	var best_dist := detection_radius
	for node in get_tree().get_nodes_in_group(target_group):
		var candidate := node as Node2D
		if candidate == null or not candidate.has_method(&"take_damage"):
			continue
		if candidate.has_method(&"is_dead") and candidate.is_dead():
			continue
		var dist := global_position.distance_to(candidate.global_position)
		if dist <= best_dist:
			best = candidate
			best_dist = dist
	return best


func _play(action: StringName) -> void:
	var anim := StringName("%s_%s" % [action, facing])
	if side_view:
		anim = action
		if facing == &"left" or facing == &"right":
			_sprite.flip_h = facing == &"left"
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
	else:
		push_warning("Enemy animation not found: %s" % anim)


func _flash() -> void:
	_sprite.modulate = Color(1.0, 0.4, 0.4)
	create_tween().tween_property(_sprite, ^"modulate", Color.WHITE, 0.15)


func _on_died() -> void:
	died.emit()
	queue_free()
