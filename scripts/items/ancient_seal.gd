class_name AncientSeal
extends Area2D
## Ancient Seal pickup (Issue #43): one of the seals needed to unseal the boss
## gate on the current dungeon level. Works like ItemPickup: hidden until its
## Room is cleared (a won encounter, a finished trial, a solved puzzle), then
## the first living "player" body touching it collects it through
## RunState.collect_seal(seal_id), once per level. A collected seal frees
## itself and never reappears in the cached room. Inert until the Dungeon
## assigns `run_state`. Drawn as a glowing rune disc, so no extra art is needed.

@export var seal_id: StringName
## Bobbing height in pixels.
@export var bob_height: float = 4.0
@export var color := Color(0.35, 0.95, 0.85)

var run_state: RunState:
	set(value):
		run_state = value
		if is_node_ready():
			_refresh()

var _room: Room
var _time := 0.0


func _ready() -> void:
	var node := get_parent()
	while node and not node is Room:
		node = node.get_parent()
	_room = node as Room
	if _room:
		_room.state_changed.connect(func(_state: Room.State) -> void: _refresh())
	_refresh()


## True while the seal can be collected.
func is_active() -> bool:
	return run_state != null and run_state.can_collect_seal(seal_id) \
		and not is_queued_for_deletion() and (_room == null or _room.state == Room.State.CLEARED)


func _physics_process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if not is_active():
		return
	for body in get_overlapping_bodies():
		if body.is_in_group(&"player") and not (body.has_method(&"is_dead") and body.is_dead()):
			collect()
			return


## Collects the seal through RunState and removes the pickup. Returns true on success.
func collect() -> bool:
	if not is_active() or not run_state.collect_seal(seal_id):
		return false
	queue_free()
	return true


func _refresh() -> void:
	if run_state and run_state.is_seal_collected(seal_id):
		queue_free()
		return
	visible = is_active()


func _draw() -> void:
	var y := -20.0 + sin(_time * 2.5) * bob_height
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, 16.0, Color(0, 0, 0, 0.3))
	draw_circle(Vector2(0, y), 26.0, Color(color, 0.12 + 0.1 * pulse))
	draw_circle(Vector2(0, y), 15.0, color.darkened(0.55))
	draw_arc(Vector2(0, y), 15.0, 0.0, TAU, 32, color, 2.5)
	draw_arc(Vector2(0, y), 20.0 + 3.0 * pulse, 0.0, TAU, 32, Color(color, 0.5), 1.5)
	# Three-pointed rune: one stroke per seal of the objective.
	for i in RunState.SEALS_REQUIRED:
		var dir := Vector2.UP.rotated(TAU * i / RunState.SEALS_REQUIRED)
		draw_line(Vector2(0, y), Vector2(0, y) + dir * 10.0, color.lightened(0.5), 2.0)
	draw_circle(Vector2(0, y), 3.0, Color.WHITE)
