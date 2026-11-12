class_name WaveHazard
extends Node2D
## Telegraphed water wave (Issue #51, Water Caster miniboss): a front that
## sweeps along a rectangular lane in one axis direction. Lifecycle:
##   TELEGRAPH (`telegraph` s) - the whole lane (exactly the area the front
##     will cross) is shown as a blue band, with a bold warning line at the
##     start edge and chevrons pointing in the travel direction; harmless.
##   SWEEP - a `thickness` px front moves from the start edge to the far edge at
##     `speed` px/s. Every living target (`target_group`) whose origin (feet)
##     the front crosses takes `damage` once and is slowed by `slow_factor` for
##     `slow_duration` s (if it has apply_slow()). A target that is invulnerable
##     at that moment (Mage dash, end of the run) is not hit and not slowed; it
##     can still be hit later in the same sweep if the front reaches it again.
##     Each target is hit at most once per wave.
##   DONE - `finished` fires and the wave frees itself.
## Like FloorHazard it is freed when its `source` leaves the tree or dies, and
## when it leaves the tree itself (its room is unloaded). Timers advance in
## _physics_process, so a wave inside a room that is not in the tree never ticks.

## Emitted when the telegraph ends and the front starts moving.
signal sweep_started
## Emitted when a target is hit (damaged and slowed).
signal hit(target: Node2D)
## Emitted when the front has crossed the whole lane.
signal finished

enum Phase { TELEGRAPH, SWEEP, DONE }

const GROUP := &"wave_hazards"

## Lane in global coordinates (the full area the front crosses).
var lane := Rect2()
## Travel direction: one of Vector2.RIGHT / LEFT / DOWN / UP.
var direction := Vector2.RIGHT
## Seconds of harmless telegraph before the front starts moving.
var telegraph: float = 1.4
var speed: float = 520.0
## Depth of the front along the travel direction (px).
var thickness: float = 56.0
var damage: float = 12.0
## Movement speed factor while slowed (1 = no slow) and its duration.
var slow_factor: float = 0.6
var slow_duration: float = 2.5
var target_group: StringName = &"player"
var color := Color(0.35, 0.7, 1.0)
## Node whose death or removal clears this wave (optional).
var source: Node

var phase: Phase = Phase.TELEGRAPH

var _left := 0.0
var _time := 0.0
## Distance the front's leading edge has travelled from the start edge.
var _travelled := 0.0
var _hit_targets: Array[Node] = []


## Adds a wave over the global `p_lane` travelling `p_direction` under `parent`
## (usually the Room) and returns it.
static func spawn(parent: Node, p_lane: Rect2, p_direction: Vector2, p_telegraph: float, p_speed: float,
		p_damage: float, p_slow_factor: float, p_slow_duration: float, p_source: Node = null,
		p_thickness: float = 56.0, p_color := Color(0.35, 0.7, 1.0)) -> WaveHazard:
	var wave := WaveHazard.new()
	wave.lane = p_lane
	wave.direction = axis(p_direction)
	wave.telegraph = p_telegraph
	wave.speed = p_speed
	wave.damage = p_damage
	wave.slow_factor = p_slow_factor
	wave.slow_duration = p_slow_duration
	wave.source = p_source
	wave.thickness = p_thickness
	wave.color = p_color
	parent.add_child(wave)
	wave.global_position = Vector2.ZERO
	return wave


## Frees every wave created by `p_source`.
static func clear_from(tree: SceneTree, p_source: Node) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		if (node as WaveHazard).source == p_source:
			node.queue_free()


## `v` snapped to its dominant axis (horizontal wins ties; zero -> RIGHT).
static func axis(v: Vector2) -> Vector2:
	if v == Vector2.ZERO:
		return Vector2.RIGHT
	if absf(v.x) >= absf(v.y):
		return Vector2.RIGHT if v.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if v.y > 0.0 else Vector2.UP


func _ready() -> void:
	add_to_group(GROUP)
	z_index = -1
	# Drawn in global coordinates; the node itself stays at the origin of its parent space.
	top_level = true
	global_position = Vector2.ZERO
	_left = telegraph
	if source:
		source.tree_exiting.connect(queue_free)
		if source.has_signal(&"died"):
			source.connect(&"died", queue_free)


func _exit_tree() -> void:
	# The room was unloaded (or the scene ended): never resume later.
	queue_free()


## Length of the lane along the travel direction.
func length() -> float:
	return lane.size.x if direction.x != 0.0 else lane.size.y


## Seconds until the front starts moving (0 once it moves).
func time_to_sweep() -> float:
	return _left if phase == Phase.TELEGRAPH else 0.0


## True if global `point` is inside the lane (the telegraphed area).
func lane_contains(point: Vector2) -> bool:
	# Inclusive on every edge (Rect2.has_point() excludes the end edges).
	return point.x >= lane.position.x and point.x <= lane.end.x and point.y >= lane.position.y and point.y <= lane.end.y


## The front's current area (global), empty before the sweep.
func front_rect() -> Rect2:
	if phase != Phase.SWEEP:
		return Rect2()
	return _band(_travelled - thickness, _travelled)


## Seconds from now until the front's leading edge reaches global `point`
## (INF if `point` is outside the lane or the front has already passed it).
func time_to_reach(point: Vector2) -> float:
	if not lane_contains(point):
		return INF
	var dist := _distance_along(point) - _travelled
	if dist < -thickness:
		return INF
	return (_left if phase == Phase.TELEGRAPH else 0.0) + maxf(dist, 0.0) / maxf(speed, 0.01)


func _physics_process(delta: float) -> void:
	_time += delta
	queue_redraw()
	match phase:
		Phase.TELEGRAPH:
			_left -= delta
			if _left <= 0.0:
				phase = Phase.SWEEP
				_travelled = 0.0
				sweep_started.emit()
				_hit_band(-thickness, 0.0)
		Phase.SWEEP:
			var from := _travelled - thickness
			_travelled += speed * delta
			# The whole area the front covered this tick (no tunnelling at any speed).
			_hit_band(from, _travelled)
			if _travelled - thickness >= length():
				phase = Phase.DONE
				finished.emit()
				queue_free()


## Damages and slows every living target whose origin lies in the band between
## `from` and `to` (distances from the start edge), at most once per wave.
func _hit_band(from: float, to: float) -> void:
	for node in get_tree().get_nodes_in_group(target_group):
		var target := node as Node2D
		if target == null or _hit_targets.has(target) or not target.has_method(&"take_damage"):
			continue
		if target.has_method(&"is_dead") and target.is_dead():
			continue
		if not lane_contains(target.global_position):
			continue
		var d := _distance_along(target.global_position)
		if d < from or d > to:
			continue
		if _is_protected(target):
			continue
		_hit_targets.append(target)
		target.take_damage(damage)
		if target.has_method(&"apply_slow"):
			target.apply_slow(slow_factor, slow_duration)
		hit.emit(target)


## True while `target` ignores damage (dash invulnerability, end of the run).
static func _is_protected(target: Node) -> bool:
	if target.has_method(&"is_dash_invulnerable") and target.is_dash_invulnerable():
		return true
	return target.get(&"invulnerable") == true


## Distance of global `point` from the lane's start edge along the travel direction.
func _distance_along(point: Vector2) -> float:
	match direction:
		Vector2.RIGHT:
			return point.x - lane.position.x
		Vector2.LEFT:
			return lane.end.x - point.x
		Vector2.DOWN:
			return point.y - lane.position.y
		_:
			return lane.end.y - point.y


## Global rect of the lane between distances `from` and `to` from the start edge (clipped to the lane).
func _band(from: float, to: float) -> Rect2:
	var a := clampf(from, 0.0, length())
	var b := clampf(to, 0.0, length())
	match direction:
		Vector2.RIGHT:
			return Rect2(lane.position.x + a, lane.position.y, b - a, lane.size.y)
		Vector2.LEFT:
			return Rect2(lane.end.x - b, lane.position.y, b - a, lane.size.y)
		Vector2.DOWN:
			return Rect2(lane.position.x, lane.position.y + a, lane.size.x, b - a)
		_:
			return Rect2(lane.position.x, lane.end.y - b, lane.size.x, b - a)


func _draw() -> void:
	match phase:
		Phase.TELEGRAPH:
			var progress := clampf(1.0 - _left / maxf(telegraph, 0.01), 0.0, 1.0)
			var blink := 0.5 + 0.5 * sin(_time * (8.0 + 10.0 * progress))
			draw_rect(lane, Color(color, 0.10 + 0.14 * progress))
			draw_rect(lane, Color(color, 0.9), false, 3.0)
			# The start edge: a bold warning line where the wave comes from.
			draw_rect(_band(0.0, 14.0), Color(color.lightened(0.4), 0.6 + 0.4 * blink))
			draw_rect(_band(0.0, 4.0), Color(1.0, 1.0, 1.0, 0.5 + 0.5 * blink))
			# The part of the lane the wave will reach first, filling up with the countdown.
			draw_rect(_band(0.0, length() * progress), Color(color, 0.12))
			_draw_chevrons(Color(color.lightened(0.3), 0.45 + 0.4 * blink))
		Phase.SWEEP:
			# Faint wet trail behind the front, then the front itself with a foam edge.
			draw_rect(_band(0.0, _travelled - thickness), Color(color, 0.08))
			draw_rect(lane, Color(color, 0.5), false, 1.5)
			var front := front_rect()
			draw_rect(front, Color(color, 0.75))
			draw_rect(_band(_travelled - thickness * 0.5, _travelled), Color(color.lightened(0.25), 0.6))
			draw_rect(_band(_travelled - 12.0, _travelled), Color(0.9, 0.97, 1.0, 0.95))
			_draw_spray()


## Foam and spray: droplets just ahead of the front and splashes where the
## front meets the lane edges (procedural, so nothing to clean up).
func _draw_spray() -> void:
	var across := Vector2(direction.y, direction.x).abs()
	var width := lane.size.x if across.x != 0.0 else lane.size.y
	var lead := _band(_travelled, _travelled).get_center() - across * width * 0.5
	var drops := maxi(int(width / 18.0), 4)
	for i in drops:
		# Stable per-droplet offsets that flicker with time.
		var seed_v := float(i) * 12.9898
		var jitter := fposmod(sin(seed_v + _time * 9.0) * 43758.5453, 1.0)
		var ahead := 4.0 + 22.0 * jitter
		var pos := lead + across * (width * (i + 0.5) / drops) + direction * ahead
		draw_circle(pos, 2.0 + 3.0 * (1.0 - jitter), Color(0.85, 0.95, 1.0, 0.85 - 0.5 * jitter))
	for edge in [0.0, width]:
		var at: Vector2 = lead + across * edge
		var out: Vector2 = across * (-1.0 if edge == 0.0 else 1.0)
		for k in 3:
			var t := fposmod(_time * 3.0 + k / 3.0, 1.0)
			draw_circle(at + out * (6.0 + 26.0 * t) - direction * 10.0 * k, 5.0 * (1.0 - t) + 1.0,
					Color(0.85, 0.95, 1.0, 0.8 * (1.0 - t)))


## Arrow chevrons along the lane's centre line, pointing in the travel direction.
func _draw_chevrons(c: Color) -> void:
	var across := Vector2(direction.y, direction.x).abs()
	var width := lane.size.x if across.x != 0.0 else lane.size.y
	var size := clampf(width * 0.12, 14.0, 40.0)
	var steps := maxi(int(length() / 140.0), 2)
	for i in steps:
		var d := (i + 0.5) * length() / steps
		var centre := _band(d, d).get_center()
		var tip := centre + direction * size * 0.5
		var back := centre - direction * size * 0.5
		draw_line(back + across * size, tip, c, 3.0)
		draw_line(back - across * size, tip, c, 3.0)
