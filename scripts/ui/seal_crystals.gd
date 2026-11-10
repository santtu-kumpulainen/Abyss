class_name SealCrystals
extends Control
## Ancient Seal indicators of the AbilityBar (Issue #49): one crystal per
## RunState.seal_sources() entry, dark until that seal is collected on this
## dungeon level, then lit. Reads RunState on every draw; redrawn on
## RunState.changed / seal_collected, so a new level's sources reset it.

const DARK := Color(0.2, 0.2, 0.3, 1)
const DARK_EDGE := Color(0.4, 0.4, 0.55, 1)
const LIT := Color(0.55, 1, 0.95, 1)
const GLOW := Color(0.4, 1, 0.9, 0.35)
const CRYSTAL := Vector2(12, 22)
const GAP := 6.0

var run_state: RunState:
	set(value):
		if run_state and run_state.changed.is_connected(queue_redraw):
			run_state.changed.disconnect(queue_redraw)
			run_state.seal_collected.disconnect(_on_seal_collected)
		run_state = value
		if run_state:
			run_state.changed.connect(queue_redraw)
			run_state.seal_collected.connect(_on_seal_collected)
		queue_redraw()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(4 * CRYSTAL.x + 3 * GAP + 12, 44)


## Lit state per seal source, in RunState order (for tests and the draw).
func states() -> Array[bool]:
	var lit: Array[bool] = []
	if run_state:
		for id in run_state.seal_sources():
			lit.append(run_state.is_seal_collected(id))
	return lit


func _on_seal_collected(_id: StringName) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), AbilitySlot.FRAME)
	draw_rect(Rect2(Vector2.ZERO, size), AbilitySlot.BORDER, false, 2.0)
	var lit := states()
	var total_width := lit.size() * CRYSTAL.x + maxi(lit.size() - 1, 0) * GAP
	var x := (size.x - total_width) / 2.0
	for on in lit:
		var c := Vector2(x + CRYSTAL.x / 2.0, size.y / 2.0)
		var points := PackedVector2Array([c + Vector2(0, -CRYSTAL.y / 2.0), c + Vector2(CRYSTAL.x / 2.0, -2),
				c + Vector2(0, CRYSTAL.y / 2.0), c + Vector2(-CRYSTAL.x / 2.0, -2)])
		if on:
			draw_circle(c, CRYSTAL.y * 0.55, GLOW)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_colored_polygon(points, LIT if on else DARK)
		draw_polyline(outline, Color.WHITE if on else DARK_EDGE, 1.5)
		# Facet line.
		draw_line(points[0], points[2], Color(1, 1, 1, 0.5) if on else Color(0.5, 0.5, 0.65, 0.4), 1.0)
		x += CRYSTAL.x + GAP
