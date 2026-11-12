class_name FloorHazard
extends Node2D
## Telegraphed floor circle (Issue #43), shared by minibosses and the Abyss
## Warden. Lifecycle:
##   TELEGRAPH (`delay` s) - an outline of exactly `radius` with a disc filling
##     up towards it; harmless, so the target can step out.
##   ERUPT - every living target (`target_group`) whose origin (feet) is within
##     `radius` takes `damage` once (none if `damage` <= 0), `erupted` fires.
##   LINGER (`lifetime` s, optional) - the zone stays and pulses every
##     `pulse_interval` s, damaging whoever stands inside (once per pulse).
## Then it frees itself. Each eruption also leaves a short, self-freeing Burst
## (expanding ring and flash, plus `erupt_effect` sized to the zone if set) next
## to it, so the explosion stays visible after the hazard is gone. In the last
## IMMINENT_TIME s of the telegraph the outline pulses fast with a white rim.
## It is also freed when its `source` leaves the tree or
## dies, and when it leaves the tree itself (its room is unloaded), so nothing
## stays behind after an encounter. Timers advance in _physics_process, so a
## hazard inside a room that is not in the tree never ticks.

signal erupted(hits: int)
signal pulsed(hits: int)

enum Phase { TELEGRAPH, LINGER, DONE }

const ERUPT_FLASH := 0.2
## Last seconds of the telegraph shown as "about to erupt".
const IMMINENT_TIME := 0.35
const OUTLINE_WIDTH := 4.0

## Seconds of harmless telegraph before the eruption.
@export var delay: float = 1.0
@export var radius: float = 64.0
## Damage of the eruption and of each lingering pulse.
@export var damage: float = 10.0
## Seconds the zone lingers after erupting (0 = gone right after the eruption).
@export var lifetime: float = 0.0
@export var pulse_interval: float = 1.0
@export var target_group: StringName = &"player"
@export var color := Color(0.75, 0.35, 1.0)
## Optional sheet played over the zone when it erupts (fitted to its diameter).
@export var erupt_effect: EffectSheet

var phase: Phase = Phase.TELEGRAPH
## Node whose death or removal clears this hazard (optional).
var source: Node

var _left := 0.0
var _pulse_left := 0.0
var _flash := 0.0
var _time := 0.0


## Adds a hazard at global `pos` under `parent` (usually the Room) and returns it.
static func spawn(parent: Node, pos: Vector2, p_radius: float, p_delay: float, p_damage: float,
		p_lifetime: float = 0.0, p_source: Node = null, p_color := Color(0.75, 0.35, 1.0)) -> FloorHazard:
	var hazard := FloorHazard.new()
	hazard.radius = p_radius
	hazard.delay = p_delay
	hazard.damage = p_damage
	hazard.lifetime = p_lifetime
	hazard.color = p_color
	hazard.source = p_source
	parent.add_child(hazard)
	hazard.global_position = pos
	return hazard


## Frees every hazard created by `p_source`.
static func clear_from(tree: SceneTree, p_source: Node) -> void:
	for node in tree.get_nodes_in_group(&"floor_hazards"):
		if (node as FloorHazard).source == p_source:
			node.queue_free()


func _ready() -> void:
	add_to_group(&"floor_hazards")
	z_index = -1
	_left = delay
	if source:
		source.tree_exiting.connect(queue_free)
		if source.has_signal(&"died"):
			source.connect(&"died", queue_free)


func _exit_tree() -> void:
	# The room was unloaded (or the scene ended): never resume later.
	queue_free()


## True if `node`'s origin is inside the circle.
func contains(node: Node2D) -> bool:
	return global_position.distance_to(node.global_position) <= radius


## Seconds until the eruption (0 once erupted).
func time_to_erupt() -> float:
	return _left if phase == Phase.TELEGRAPH else 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()
	match phase:
		Phase.TELEGRAPH:
			_left -= delta
			if _left <= 0.0:
				erupted.emit(_hit())
				_flash = ERUPT_FLASH
				_spawn_burst()
				if lifetime > 0.0:
					phase = Phase.LINGER
					_left = lifetime
					_pulse_left = pulse_interval
				else:
					_finish()
		Phase.LINGER:
			_left -= delta
			_pulse_left -= delta
			if _pulse_left <= 0.0 and _left > 0.0:
				_pulse_left = pulse_interval
				_flash = ERUPT_FLASH * 0.6
				pulsed.emit(_hit())
			if _left <= 0.0:
				_finish()


## Damages every living target inside; returns how many were hit.
func _hit() -> int:
	if damage <= 0.0:
		return 0
	var hits := 0
	for node in get_tree().get_nodes_in_group(target_group):
		var target := node as Node2D
		if target == null or not target.has_method(&"take_damage"):
			continue
		if target.has_method(&"is_dead") and target.is_dead():
			continue
		if contains(target):
			target.take_damage(damage)
			HitFeedback.knock(target, target.global_position - global_position)
			hits += 1
	return hits


## The eruption visual, independent of this hazard's own lifetime.
func _spawn_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var burst := Burst.new()
	burst.radius = radius
	burst.color = color
	burst.z_index = z_index
	parent.add_child(burst)
	burst.global_position = global_position
	if erupt_effect:
		PixelEffect.spawn(erupt_effect, parent, global_position, 0.0, radius * 2.4)


func _finish() -> void:
	phase = Phase.DONE
	queue_free()


func _draw() -> void:
	match phase:
		Phase.TELEGRAPH:
			var progress := clampf(1.0 - _left / maxf(delay, 0.01), 0.0, 1.0)
			draw_circle(Vector2.ZERO, radius, Color(color, 0.10 + 0.14 * progress))
			draw_circle(Vector2.ZERO, radius * progress, Color(color, 0.26))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(color, 0.95), OUTLINE_WIDTH)
			if _left <= IMMINENT_TIME:
				# About to erupt: fast pulse and a white rim.
				var pulse := 0.5 + 0.5 * sin(_time * 40.0)
				draw_circle(Vector2.ZERO, radius, Color(color.lightened(0.3), 0.15 + 0.2 * pulse))
				draw_arc(Vector2.ZERO, radius - OUTLINE_WIDTH, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.5 + 0.5 * pulse), 2.0)
		Phase.LINGER:
			var pulse := 0.5 + 0.5 * sin(_time * 6.0)
			draw_circle(Vector2.ZERO, radius, Color(color, 0.28 + 0.12 * pulse))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(color.lightened(0.3), 0.9), OUTLINE_WIDTH)
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.95, 1.0, 0.5 * _flash / ERUPT_FLASH))


## Eruption visual: a flash of the zone and a ring expanding past its edge,
## fading over DURATION s, then it frees itself. No gameplay effect.
class Burst extends Node2D:
	const DURATION := 0.35

	var radius := 64.0
	var color := Color.WHITE
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= DURATION:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var t := clampf(_age / DURATION, 0.0, 1.0)
		var fade := 1.0 - t
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.97, 1.0, 0.45 * fade * fade))
		draw_circle(Vector2.ZERO, radius * (0.6 + 0.4 * t), Color(color.lightened(0.3), 0.35 * fade))
		draw_arc(Vector2.ZERO, radius * (1.0 + 0.35 * t), 0.0, TAU, 64, Color(color.lightened(0.5), fade), 6.0 * fade + 1.0)
