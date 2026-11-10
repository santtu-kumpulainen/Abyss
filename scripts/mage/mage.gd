class_name Mage
extends CharacterBody2D
## Playable Mage: WASD movement with 8-direction idle/walk animations, and a
## SpellCaster that fires its equipped Spell toward the mouse while "attack"
## is held. Animations are named "<action>_<direction>" (see mage.tres).
## Takes damage via take_damage(); on death input stops and `died` is emitted.
## end_run() (victory) stops input and makes the Mage ignore further damage.
## "dash" (Space) dashes `dash_distance` px over `dash_duration` s in the input
## direction (or `facing`), ignoring damage for `dash_invulnerability` s and
## then recharging for `dash_cooldown` s, both counted from the dash start
## (Issue #49). The HUD reads dash_ready()/dash_cooldown_ratio().

signal died
## Emitted when a dash starts, with its unit direction.
signal dash_started(direction: Vector2)
## Emitted when the dash movement ends (finished, stopped or cancelled).
signal dash_ended

## Clockwise from east, matching Vector2.angle() in 45° steps.
const DIRECTIONS: Array[StringName] = [
	&"east", &"south_east", &"south", &"south_west",
	&"west", &"north_west", &"north", &"north_east",
]
## HUD controls whose clicks are not attacks (see is_attack_held()).
const HUD_CLICK_GROUP := &"hud_click"
## Group of the dash afterimage sprites.
const AFTERIMAGE_GROUP := &"dash_afterimages"

## Movement speed in pixels per second.
@export var speed: float = 150.0

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

@export_group("Dash")
## Distance of one dash in pixels (not scaled by speed upgrades or potions).
@export var dash_distance := 110.0
## Duration of the dash movement in seconds.
@export var dash_duration := 0.15
## Damage is ignored for this long after the dash starts.
@export var dash_invulnerability := 0.20
## Time from one dash start until the next dash is available.
@export var dash_cooldown := 2.75
## Number of fading copies of the sprite left along the dash path.
@export_range(0, 8) var dash_afterimages := 4
## Colour of the afterimages.
@export var dash_afterimage_tint := Color(0.45, 0.7, 1.0, 0.65)
## How long one afterimage takes to fade out.
@export var dash_afterimage_fade := 0.3
## The start puff is moved this far back from the feet, so the smoke starts at
## the feet and blows away from the dash direction.
@export var dash_puff_offset := 11.0
@export_group("")

var facing: StringName = &"south"
## Run modifier applied on top of `speed` (set by the Dungeon from RunState).
var speed_multiplier := 1.0
## Run modifier on all damage taken (set by the Dungeon from RunState).
var damage_taken_multiplier := 1.0
## Set by end_run(): take_damage() does nothing.
var invulnerable := false

var _dash_direction := Vector2.ZERO
## Seconds left of the dash movement (> 0 while dashing).
var _dash_time_left := 0.0
var _dash_distance_left := 0.0
var _dash_invulnerable_left := 0.0
var _dash_cooldown_left := 0.0
var _afterimages_spawned := 0
## Set by the "dash" key; the dash starts on the next physics tick.
var _dash_requested := false
var _dash_trail: DashTrail
## Visual nodes of the current/last dash (afterimages, puff), freed on cancel.
var _dash_effects: Array[Node] = []

@onready var caster: SpellCaster = $SpellCaster
@onready var health: Health = $Health
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_apply_scale()
	health.died.connect(_on_died)
	_play(&"idle")


func _physics_process(delta: float) -> void:
	_dash_invulnerable_left = _count_down(_dash_invulnerable_left, delta)
	_dash_cooldown_left = _count_down(_dash_cooldown_left, delta)
	# get_vector() clamps length to 1, so diagonals are not faster.
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if _dash_requested:
		_dash_requested = false
		try_dash(input)
	if is_dashing():
		# No walking or casting during the burst.
		_dash_step(delta)
		return

	velocity = input * speed * speed_multiplier
	move_and_slide()

	if input != Vector2.ZERO:
		facing = direction_name(input)

	if is_attack_held():
		var target := get_global_mouse_position()
		# No cast animation exists; when standing still, turn toward the aim.
		if caster.try_cast(target) and input == Vector2.ZERO:
			facing = direction_name(target - caster.global_position)

	_play(&"idle" if input == Vector2.ZERO else &"walk")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"dash") and not event.is_echo() and can_dash():
		_dash_requested = true


func take_damage(amount: float) -> void:
	if invulnerable or is_dash_invulnerable():
		return
	health.take_damage(amount * damage_taken_multiplier)
	if not health.is_dead():
		_sprite.modulate = Color(1.0, 0.4, 0.4)
		create_tween().tween_property(_sprite, ^"modulate", Color.WHITE, 0.15)


func is_dead() -> bool:
	return health.is_dead()


## Ends the run (victory): stops movement and casting, ignores further damage.
func end_run() -> void:
	cancel_dash()
	invulnerable = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	_play(&"idle")


## Undoes end_run() when the run continues on the next dungeon level.
func resume_run() -> void:
	invulnerable = false
	set_physics_process(true)


## True while "attack" is held for gameplay: not while the mouse is over a HUD
## control in HUD_CLICK_GROUP (e.g. an ability bar slot) or a HUD drag is under
## way, so clicking or dragging on the HUD never casts a spell.
func is_attack_held() -> bool:
	if not Input.is_action_pressed(&"attack"):
		return false
	var viewport := get_viewport()
	if viewport == null:
		return true
	if viewport.gui_is_dragging():
		return false
	var hovered := viewport.gui_get_hovered_control()
	return hovered == null or not hovered.is_in_group(HUD_CLICK_GROUP)


## Starts a dash toward `direction` (the current `facing` if zero). Returns false
## (changing nothing) while dashing, on cooldown, dead or after end_run().
func try_dash(direction := Vector2.ZERO) -> bool:
	if not can_dash():
		return false
	if direction.is_zero_approx():
		direction = Vector2.RIGHT.rotated(DIRECTIONS.find(facing) * PI / 4.0)
	_dash_direction = direction.normalized()
	facing = direction_name(_dash_direction)
	_dash_time_left = dash_duration
	_dash_distance_left = dash_distance
	_dash_invulnerable_left = dash_invulnerability
	_dash_cooldown_left = dash_cooldown
	_afterimages_spawned = 0
	_play(&"dash")
	_set_dash_lean(true)
	_spawn_dash_start_effects()
	dash_started.emit(_dash_direction)
	return true


## True if a dash can start now.
func can_dash() -> bool:
	return dash_ready() and not is_dashing() and not health.is_dead() and is_physics_processing()


## True once the cooldown of the last dash has run out.
func dash_ready() -> bool:
	return _dash_cooldown_left <= 0.0


## Seconds until the next dash is available (0 when ready).
func dash_cooldown_remaining() -> float:
	return _dash_cooldown_left


## Recharge progress: 0.0 right after a dash, 1.0 when ready.
func dash_cooldown_ratio() -> float:
	if dash_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _dash_cooldown_left / dash_cooldown, 0.0, 1.0)


func is_dashing() -> bool:
	return _dash_time_left > 0.0


## True while the dash ignores damage (separate from the end_run() flag).
func is_dash_invulnerable() -> bool:
	return _dash_invulnerable_left > 0.0


## Unit direction of the current or last dash.
func dash_direction() -> Vector2:
	return _dash_direction


## Stops a running dash and its invulnerability at once and removes its
## visuals (room/level change, death, end_run()). The cooldown keeps running.
func cancel_dash() -> void:
	_dash_requested = false
	_dash_invulnerable_left = 0.0
	var was_dashing := is_dashing()
	_dash_time_left = 0.0
	_dash_distance_left = 0.0
	if was_dashing:
		velocity = Vector2.ZERO
		_set_dash_lean(false)
	if _dash_trail and is_instance_valid(_dash_trail):
		_dash_trail.finish(0.0)
	_dash_trail = null
	for node in _dash_effects:
		if is_instance_valid(node):
			node.queue_free()
	_dash_effects.clear()
	if was_dashing:
		dash_ended.emit()


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
	cancel_dash()
	# No death animation or game-over flow yet: stop and dim.
	velocity = Vector2.ZERO
	set_physics_process(false)
	_play(&"idle")
	_sprite.modulate = Color(0.5, 0.5, 0.5, 0.7)
	died.emit()


func _apply_scale() -> void:
	_sprite.scale = Vector2.ONE * sprite_scale
	caster.position = Vector2(0.0, -cast_height * sprite_scale)


## One physics frame of the dash: moves with collision (walls, obstacles and
## locked doors stop it) and never further than the remaining distance.
func _dash_step(delta: float) -> void:
	var step := minf(dash_distance / maxf(dash_duration, 0.001) * delta, _dash_distance_left)
	velocity = _dash_direction * (step / delta) if delta > 0.0 else Vector2.ZERO
	move_and_slide()
	_dash_distance_left -= step
	_dash_time_left -= delta
	# Afterimages evenly spread over the burst.
	var due := ceili((1.0 - maxf(_dash_time_left, 0.0) / dash_duration) * dash_afterimages)
	while _afterimages_spawned < mini(due, dash_afterimages):
		_spawn_afterimage()
		_afterimages_spawned += 1
	if _dash_distance_left <= 0.01 or _dash_time_left <= 0.0:
		_end_dash()


## `time` minus `delta`, snapped to 0 when (almost) run out, so a timer of
## N ticks ends on tick N despite float rounding.
static func _count_down(time: float, delta: float) -> float:
	var left := time - delta
	return left if left > 0.0001 else 0.0


func _end_dash() -> void:
	_dash_time_left = 0.0
	_dash_distance_left = 0.0
	velocity = Vector2.ZERO
	_set_dash_lean(false)
	if _dash_trail and is_instance_valid(_dash_trail):
		_dash_trail.finish()
		# Still fading: cancel_dash() (e.g. on a room change) removes it at once.
		_dash_effects.append(_dash_trail)
	_dash_trail = null
	dash_ended.emit()


## Node that holds the world-space dash visuals (they stay behind the Mage).
func _effect_parent() -> Node:
	return get_parent() if get_parent() else self


func _spawn_dash_start_effects() -> void:
	var parent := _effect_parent()
	for i in range(_dash_effects.size() - 1, -1, -1):
		if not is_instance_valid(_dash_effects[i]):
			_dash_effects.remove_at(i)
	# The puff sheet blows upward from the bottom of its cell: turn "up" into
	# the opposite of the dash and move it back so it starts at the feet.
	var puff := EffectLibrary.spawn(&"dash_puff", parent, global_position - _dash_direction * dash_puff_offset,
			(-_dash_direction).angle() + PI / 2.0)
	if puff:
		_put_behind_mage(puff)
		_dash_effects.append(puff)
	if _dash_trail and is_instance_valid(_dash_trail):
		_dash_trail.finish(0.0)
	_dash_trail = DashTrail.follow(self, parent, caster.position * 0.5)


## Draws a world effect above the room but under the Mage: same z as the Mage,
## just before it among its siblings (which also breaks y-sort ties).
func _put_behind_mage(node: CanvasItem) -> void:
	node.z_index = z_index
	if get_parent() and node.get_parent() == get_parent():
		get_parent().move_child(node, get_index())


## Leaves a fading, tinted copy of the current sprite frame at the Mage's position.
func _spawn_afterimage() -> void:
	var frames := _sprite.sprite_frames
	if frames == null or not frames.has_animation(_sprite.animation):
		return
	var ghost := Sprite2D.new()
	ghost.texture = frames.get_frame_texture(_sprite.animation, _sprite.frame)
	ghost.texture_filter = _sprite.texture_filter
	ghost.centered = _sprite.centered
	ghost.offset = _sprite.offset
	ghost.flip_h = _sprite.flip_h
	ghost.scale = _sprite.scale
	ghost.skew = _sprite.skew
	ghost.modulate = dash_afterimage_tint
	ghost.add_to_group(AFTERIMAGE_GROUP)
	_effect_parent().add_child(ghost)
	ghost.global_position = global_position
	_put_behind_mage(ghost)
	_dash_effects.append(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, ^"modulate:a", 0.0, dash_afterimage_fade)
	tween.tween_callback(ghost.queue_free)


## Stretches the sprite along the burst and leans it into the dash.
func _set_dash_lean(on: bool) -> void:
	_apply_scale()
	_sprite.skew = 0.0
	if on:
		_sprite.scale *= Vector2(1.12, 0.9)
		_sprite.skew = 0.2 * _dash_direction.x
