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
@export var speed: float = 95.0
## Most walking speed run scaling may give this enemy (0 = LevelScaling.MAX_PURSUER_SPEED,
## which is below the Mage's base speed). Only enemies meant to out-run the Mage
## (the Demon) set their own cap.
@export var speed_cap: float = 0.0
## > 0: walks at this ratio of its target's base walking speed
## (Mage.base_walk_speed(): permanent speed bonuses, never the Speed Potion or a
## slow) instead of `speed`; run speed scaling does not apply then. `speed` stays
## the fallback for targets without base_walk_speed(). Used by the Demon (0.9).
@export var player_speed_ratio: float = 0.0
## Distance at which the enemy notices a target.
@export var detection_radius: float = 260.0
## Distance (between origins) at which the enemy stops and attacks.
@export var attack_range: float = 32.0
## Damage dealt per contact attack.
@export var contact_damage: float = 12.0
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
## Played where this enemy dies (optional), on top of its corpse.
@export var death_effect: EffectSheet
## Offset of death_effect from the feet (e.g. up to the body centre).
@export var death_effect_offset := Vector2.ZERO
## World width of death_effect (0 = the sheet's own scale).
@export var death_effect_diameter: float = 0.0

@export_group("Hit feedback")
## Knockback when damaged (Issue #51 Stage 3): speed along the hit direction for
## `knockback_duration` s. `knockback_falloff` 0 keeps the speed constant
## (80 px/s x 0.10 s = 8 px), 1 fades it linearly to 0. Collides with walls,
## obstacles and other bodies (move_and_collide). Never while
## can_be_knocked_back() is false (committed attack phases, minibosses, boss).
@export var knockback_speed: float = 80.0
@export var knockback_duration: float = 0.10
@export_range(0.0, 1.0) var knockback_falloff: float = 0.0
## White hit flash strength (0..1) and its fade time.
@export var hit_flash_strength: float = 0.85
@export var hit_flash_time: float = 0.12
## Sprite scale pop on a hit (1 = none); eases back to sprite_scale.
@export var hit_pop_scale: float = 1.12
@export_group("")

## True once apply_scaling() has run (it only works once per instance).
var scaled := false
## Multiplier on damage taken (set by apply_scaling()).
var damage_taken_multiplier := 1.0
## Summoned mid-fight (e.g. by a Miniboss): grants no XP, gold or kill heal.
var summoned := false
## True from the moment of death (Issue #51 Stage 4): the enemy has left combat
## and is freed at the end of the frame; death runs only once.
var dying := false

var _attack_cooldown_left := 0.0
var _knock_velocity := Vector2.ZERO
var _knock_left := 0.0

@onready var health: Health = $Health
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if sprite_frames:
		_sprite.sprite_frames = sprite_frames
	_sprite.scale = Vector2.ONE * sprite_scale
	health.died.connect(_handle_death)
	_play(&"idle")


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	target = _find_target()
	velocity = Vector2.ZERO

	if target:
		_pursue()

	move_and_slide()
	_knockback_step(delta)
	_play(&"walk" if velocity != Vector2.ZERO else &"idle")


## Faces and walks towards `target`, dealing contact damage on cooldown once
## within attack_range (the basic melee behaviour; subclasses reuse it).
func _pursue() -> void:
	var to_target := target.global_position - global_position
	facing = direction_name(to_target)
	if to_target.length() > attack_range:
		velocity = to_target.normalized() * walk_speed()
	elif _attack_cooldown_left <= 0.0:
		_attack_cooldown_left = attack_cooldown
		target.take_damage(contact_damage)
		HitFeedback.knock(target, to_target)


## Current walking speed: `player_speed_ratio` x the target's base walking
## speed when set (and the target provides one), else `speed`.
func walk_speed() -> float:
	if player_speed_ratio > 0.0 and target != null and is_instance_valid(target) and target.has_method(&"base_walk_speed"):
		return player_speed_ratio * float(target.call(&"base_walk_speed"))
	return speed


## Applies run scaling once (call after _ready, before the enemy is damaged):
## max/current HP x `health_mult`, every damage source x `damage_mult`, attack
## rate x `pace_mult`, move speed x `move_mult` (defaults to `pace_mult`; capped
## at `speed_cap`, by default LevelScaling.MAX_PURSUER_SPEED), damage taken x `vulnerability`,
## post-attack recovery pauses / `recovery_mult` (Issue #51 tempo; telegraphs
## and windups are never scaled).
## Returns false (and changes nothing) if this enemy was already scaled.
func apply_scaling(health_mult: float, damage_mult: float, pace_mult: float = 1.0, vulnerability: float = 1.0,
		move_mult: float = -1.0, recovery_mult: float = 1.0) -> bool:
	if scaled:
		return false
	scaled = true
	health.scale_max_health(health_mult)
	damage_taken_multiplier = vulnerability
	var cap := speed_cap if speed_cap > 0.0 else LevelScaling.MAX_PURSUER_SPEED
	speed = minf(speed * (pace_mult if move_mult < 0.0 else move_mult), maxf(speed, cap))
	attack_cooldown /= maxf(pace_mult, 0.01)
	_scale_attacks(damage_mult, pace_mult)
	_scale_recovery(maxf(recovery_mult, 0.01))
	return true


## Scales this enemy's damage (subclasses add their own attacks).
func _scale_attacks(damage_mult: float, _pace_mult: float) -> void:
	contact_damage *= damage_mult


## Divides this enemy's post-attack recovery pauses by `mult` (subclasses with
## such pauses override it; never a telegraph or windup).
func _scale_recovery(_mult: float) -> void:
	pass


func take_damage(amount: float) -> void:
	health.take_damage(amount * damage_taken_multiplier)
	if not health.is_dead():
		_flash()


## Starts a knockback along `direction` (see knockback_speed). Ignored while
## dead or while can_be_knocked_back() is false; a new hit restarts it.
## Returns true if the knockback started.
func apply_knockback(direction: Vector2) -> bool:
	if direction == Vector2.ZERO or knockback_speed <= 0.0 or knockback_duration <= 0.0 \
			or health.is_dead() or not can_be_knocked_back():
		return false
	_knock_velocity = direction.normalized() * knockback_speed
	_knock_left = knockback_duration
	return true


## False while this enemy must not be displaced: subclasses return false during
## committed attack phases (telegraphs, strikes, aiming); minibosses and the
## boss never move from hits.
func can_be_knocked_back() -> bool:
	return true


## True while a knockback is moving this enemy.
func is_knocked_back() -> bool:
	return _knock_left > 0.0


## One physics frame of the knockback (call after the frame's move_and_slide()).
## Stops at a collision and as soon as the enemy becomes protected.
func _knockback_step(delta: float) -> void:
	if _knock_left <= 0.0:
		return
	if not can_be_knocked_back():
		_knock_left = 0.0
		return
	var elapsed := 1.0 - _knock_left / knockback_duration
	var step := minf(delta, _knock_left)
	_knock_left -= delta
	if move_and_collide(_knock_velocity * (1.0 - knockback_falloff * elapsed) * step):
		_knock_left = 0.0


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


## Hit feedback: a brief white flash and a scale pop (HitFeedback.flash; never
## accumulates, always eases back to sprite_scale).
func _flash() -> void:
	HitFeedback.flash(_sprite, Color.WHITE, hit_flash_strength, hit_flash_time, Vector2.ONE * sprite_scale, _hit_pop())


## Scale pop of a hit (subclasses whose sprite scale is animated return 1).
func _hit_pop() -> float:
	return hit_pop_scale


## Death entry point (Health.died): runs once. The enemy leaves combat first,
## then _on_died() spawns the visuals, emits `died` (room count and rewards)
## and frees the enemy.
func _handle_death() -> void:
	if dying:
		return
	dying = true
	_leave_combat()
	_on_died()


## Removes this enemy from combat at once: out of the "enemies" group (targeting,
## blasts), no body or hurtbox collision, no AI or knockback.
func _leave_combat() -> void:
	remove_from_group(&"enemies")
	_knock_left = 0.0
	velocity = Vector2.ZERO
	set_physics_process(false)
	set_process(false)
	collision_layer = 0
	collision_mask = 0
	for child in get_children():
		var area := child as Area2D
		if area:
			area.collision_layer = 0
			area.collision_mask = 0
			area.set_deferred(&"monitoring", false)
			area.set_deferred(&"monitorable", false)


## Parent of the death visuals: not the Enemies container (rooms count its
## children); the scene root outlives the room.
func _death_visual_parent() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_tree().root


## Death visuals (subclasses may add their own, e.g. the Blood Monster blast):
## a detached EnemyCorpse playing the sprite's death animation (if it has one)
## and death_effect. Neither has collision; both free themselves.
func _spawn_death_visuals() -> void:
	var parent := _death_visual_parent()
	EnemyCorpse.spawn(_sprite, parent, facing)
	PixelEffect.spawn(death_effect, parent, global_position + death_effect_offset, 0.0, death_effect_diameter)


func _on_died() -> void:
	_spawn_death_visuals()
	died.emit()
	queue_free()
