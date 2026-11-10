class_name DashTrail
extends Line2D
## Short fading streak behind a dashing body (Issue #49). Lives in world space
## (add it to the body's parent): while following, it records `target`'s
## position (plus `offset`) every frame; finish() fades it out and frees it.

## How long finish() takes to fade the trail out.
@export var fade_time := 0.2

var target: Node2D
var offset := Vector2.ZERO
var _following := false
var _finished := false


func _init() -> void:
	width = 9.0
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Thin and transparent at the tail (first point), full at the body.
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.2))
	taper.add_point(Vector2(1.0, 1.0))
	width_curve = taper
	var fade := Gradient.new()
	fade.set_color(0, Color(0.35, 0.6, 1.0, 0.0))
	fade.set_color(1, Color(0.6, 0.85, 1.0, 0.55))
	gradient = fade


## Starts following `body` (from its current position) under `parent`. A
## sibling of `body` is placed just before it (same z, at its feet), so the
## trail draws above the room but under the body, also in a y-sorted parent.
static func follow(body: Node2D, parent: Node, body_offset := Vector2.ZERO) -> DashTrail:
	var trail := DashTrail.new()
	trail.target = body
	trail.offset = body_offset
	trail.z_index = body.z_index
	parent.add_child(trail)
	trail.global_position = body.global_position
	if body.get_parent() == parent:
		parent.move_child(trail, body.get_index())
	trail.add_point(trail.to_local(body.global_position + body_offset))
	trail._following = true
	return trail


func is_following() -> bool:
	return _following


## Stops following and fades out (immediately freed when `fade` <= 0).
func finish(fade := fade_time) -> void:
	if _finished:
		return
	_finished = true
	_following = false
	if fade <= 0.0 or not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, fade)
	tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	if not _following:
		return
	if not is_instance_valid(target):
		finish()
		return
	var point := to_local(target.global_position + offset)
	if points.size() == 0 or points[points.size() - 1].distance_to(point) > 1.0:
		add_point(point)
