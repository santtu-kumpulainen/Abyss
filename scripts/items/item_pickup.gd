class_name ItemPickup
extends Area2D
## Collectible run item (RunState.ITEMS[item_id]). Hidden until its Room is
## cleared (or immediately when not inside a Room); the first "player" body
## touching it collects it through RunState, which applies the effect once per
## run. Collected pickups free themselves and never reappear, even in cached
## rooms. Inert until the Dungeon assigns `run_state`. Drawn as a glowing gem
## in the item's colour, so no extra art is needed.
## Reward choices: pickups sharing a non-empty `choice_group` under the same
## parent are alternatives (e.g. a miniboss's pick-1-of-2); collecting one
## removes the others for good (the cached room never restores them).

@export var item_id: StringName
## Pickups with the same group under one parent are mutually exclusive.
@export var choice_group: StringName = &""

var run_state: RunState:
	set(value):
		run_state = value
		if is_node_ready():
			_refresh()

## Bobbing height in pixels.
@export var bob_height: float = 4.0

var _room: Room
var _time := 0.0

@onready var _label: Label = $Label


func _ready() -> void:
	var node := get_parent()
	while node and not node is Room:
		node = node.get_parent()
	_room = node as Room
	if _room:
		_room.state_changed.connect(func(_state: Room.State) -> void: _refresh())
	if RunState.ITEMS.has(item_id):
		_label.text = RunState.ITEMS[item_id]["name"]
		if not choice_group.is_empty():
			_label.text = "%s\n%s" % [_label.text, RunState.ITEMS[item_id]["effect"]]
			_label.offset_top -= 18.0
	else:
		push_warning("ItemPickup: unknown item id '%s'" % item_id)
	_refresh()


## True while the item can be picked up.
func is_active() -> bool:
	return run_state != null and RunState.ITEMS.has(item_id) and run_state.can_collect(item_id) \
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


## Collects the item through RunState and removes the pickup. Returns true on success.
func collect() -> bool:
	if not is_active() or not run_state.collect_item(item_id):
		return false
	if not choice_group.is_empty():
		for node in alternatives():
			node.queue_free()
	queue_free()
	return true


## Other pickups of this pickup's choice group (empty without a group).
func alternatives() -> Array[ItemPickup]:
	var result: Array[ItemPickup] = []
	if choice_group.is_empty() or get_parent() == null:
		return result
	for node in get_parent().get_children():
		if node != self and node is ItemPickup and (node as ItemPickup).choice_group == choice_group \
				and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _refresh() -> void:
	if run_state and not run_state.can_collect(item_id):
		queue_free()
		return
	visible = is_active()


func _draw() -> void:
	if not RunState.ITEMS.has(item_id):
		return
	var color: Color = RunState.ITEMS[item_id]["color"]
	var y := -18.0 + sin(_time * 3.0) * bob_height
	draw_circle(Vector2.ZERO, 14.0, Color(0, 0, 0, 0.3))
	draw_circle(Vector2(0, y), 18.0, Color(color, 0.18))
	draw_circle(Vector2(0, y), 12.0, Color(color, 0.25))
	var gem := PackedVector2Array([Vector2(0, y - 11), Vector2(8, y), Vector2(0, y + 11), Vector2(-8, y)])
	draw_colored_polygon(gem, color)
	draw_polyline(gem + PackedVector2Array([gem[0]]), color.lightened(0.6), 1.5)
	draw_line(Vector2(-3, y - 3), Vector2(0, y - 7), Color(1, 1, 1, 0.8), 1.5)
