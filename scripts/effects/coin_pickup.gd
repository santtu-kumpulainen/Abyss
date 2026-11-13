class_name CoinPickup
extends Node2D
## A dropped coin (Issue #58 Stage 2), spawned by CombatFeedback.drop_coins().
## It pops out (`launch`, with gravity, for `scatter_time`), rests, then flies to
## `target` once that is within `magnet_radius` or after `auto_attract_delay`,
## accelerating smoothly (no teleport). Reaching the target collects it exactly
## once: `collected` fires, a pickup sound and sparkle play and the coin frees
## itself. The gold itself was granted by RunState at the kill (exactly once), so
## a coin never changes the economy. A dead / freed target or a stopped
## CombatFeedback makes the coin fade out uncollected.

signal collected

@export var magnet_radius: float = 170.0
@export var auto_attract_delay: float = 0.9
@export var scatter_time: float = 0.35
@export var accel: float = 2200.0
@export var max_speed: float = 900.0
@export var collect_distance: float = 14.0
## Collect point above the target's feet (the Mage's body).
@export var target_height: float = 18.0

var target: Node2D
var launch := Vector2.ZERO
## Gold this coin stands for (shown in the pickup popup).
var value := 0
var _speed := 0.0

var _age := 0.0
var _velocity := Vector2.ZERO
var _attracting := false
var _collected := false
var _fading := false


func _ready() -> void:
	_velocity = launch


func is_collected() -> bool:
	return _collected


func is_attracting() -> bool:
	return _attracting


func _process(delta: float) -> void:
	if _collected or _fading:
		return
	_age += delta
	if not _target_valid():
		_fade_out()
		return
	var goal := target.global_position + Vector2(0, -target_height)
	if not _attracting:
		if _age < scatter_time:
			_velocity.y += 420.0 * delta
			position += _velocity * delta
		elif global_position.distance_to(goal) <= magnet_radius or _age >= auto_attract_delay:
			_attracting = true
			_speed = 120.0
	if _attracting:
		var to_goal := goal - global_position
		if to_goal.length() <= collect_distance:
			_collect()
			return
		# Magnet pull: always straight at the goal (no orbiting), speeding up.
		_speed = minf(_speed + accel * delta, max_speed)
		var step := _speed * delta
		if step >= to_goal.length():
			_collect()
			return
		global_position += to_goal.normalized() * step
	queue_redraw()


func _target_valid() -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if target.has_method(&"is_dead") and target.call(&"is_dead"):
		return false
	var fb := get_parent() as CombatFeedback
	return fb == null or fb.active


func _collect() -> void:
	if _collected:
		return
	_collected = true
	# Sound only: a particle burst per coin would be wasteful with big waves.
	AudioManager.sfx(self, &"coin_pickup")
	var fb := get_parent() as CombatFeedback
	if fb:
		fb.coin_collected(value, target)
	collected.emit()
	queue_free()


func _fade_out() -> void:
	_fading = true
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.5, Color(0.5, 0.33, 0.04))
	draw_circle(Vector2(0, -0.5), 5.2, Color(1.0, 0.82, 0.25))
	draw_rect(Rect2(-1.5, -4, 3, 5), Color(1.0, 0.95, 0.6))
