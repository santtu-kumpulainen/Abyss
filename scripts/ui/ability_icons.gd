class_name AbilityIcons
extends RefCounted
## Code-drawn pixel-style icons for the ability bar (Issue #49; the effects pack
## has no item icons): dash streaks, red Health flask, green Speed flask and a
## blue house for Home Teleport. Everything is drawn into `rect` on `canvas`
## and multiplied by `tint`.

const OUTLINE := Color(0, 0, 0, 1)


static func draw_icon(canvas: CanvasItem, id: StringName, rect: Rect2, tint: Color) -> void:
	match id:
		&"dash":
			_dash(canvas, rect, tint)
		&"health_potion":
			_flask(canvas, rect, Color(0.9, 0.2, 0.25) * tint, tint, false)
		&"speed_potion":
			_flask(canvas, rect, Color(0.3, 0.85, 0.35) * tint, tint, true)
		&"home_teleport":
			_house(canvas, rect, tint)


static func _dash(canvas: CanvasItem, r: Rect2, tint: Color) -> void:
	var c := Color(0.6, 0.85, 1) * tint
	var w := Color(1, 1, 1) * tint
	# Speed streaks and a forward chevron.
	for i in 3:
		var y := r.position.y + r.size.y * (0.3 + 0.2 * i)
		var x0 := r.position.x + r.size.x * (0.05 + 0.1 * (i % 2))
		canvas.draw_line(Vector2(x0, y), Vector2(r.position.x + r.size.x * 0.5, y), OUTLINE, 5.0)
		canvas.draw_line(Vector2(x0, y), Vector2(r.position.x + r.size.x * 0.5, y), c, 3.0)
	var tip := Vector2(r.end.x - r.size.x * 0.05, r.get_center().y)
	var points := PackedVector2Array([Vector2(r.position.x + r.size.x * 0.55, r.position.y + r.size.y * 0.15), tip,
			Vector2(r.position.x + r.size.x * 0.55, r.end.y - r.size.y * 0.15)])
	canvas.draw_polyline(points, OUTLINE, 7.0)
	canvas.draw_polyline(points, w, 4.0)


static func _flask(canvas: CanvasItem, r: Rect2, liquid: Color, tint: Color, speed: bool) -> void:
	var glass := Color(0.85, 0.9, 1) * tint
	var body_center := Vector2(r.get_center().x, r.position.y + r.size.y * 0.64)
	var radius := r.size.x * 0.32
	var neck := Rect2(r.get_center().x - r.size.x * 0.11, r.position.y + r.size.y * 0.12, r.size.x * 0.22, r.size.y * 0.26)
	canvas.draw_rect(neck.grow(1.5), OUTLINE)
	canvas.draw_circle(body_center, radius + 1.5, OUTLINE)
	canvas.draw_rect(neck, glass)
	canvas.draw_circle(body_center, radius, liquid)
	# Cork.
	canvas.draw_rect(Rect2(neck.position.x - 1, neck.position.y - 3, neck.size.x + 2, 4), Color(0.6, 0.4, 0.25) * tint)
	# Shine.
	canvas.draw_circle(body_center + Vector2(-radius * 0.4, -radius * 0.4), radius * 0.18, Color(1, 1, 1, 0.8) * tint)
	var mark := Color(1, 1, 1) * tint
	if speed:
		# Chevrons: speed.
		for dx: float in [-0.12, 0.08]:
			var x := body_center.x + r.size.x * dx
			canvas.draw_polyline(PackedVector2Array([Vector2(x - 2, body_center.y - 4), Vector2(x + 2, body_center.y),
					Vector2(x - 2, body_center.y + 4)]), mark, 2.0)
	else:
		# Cross: healing.
		canvas.draw_rect(Rect2(body_center.x - 1.5, body_center.y - 5, 3, 10), mark)
		canvas.draw_rect(Rect2(body_center.x - 5, body_center.y - 1.5, 10, 3), mark)


static func _house(canvas: CanvasItem, r: Rect2, tint: Color) -> void:
	var wall := Color(0.45, 0.7, 1) * tint
	var roof := Color(0.25, 0.45, 0.9) * tint
	var base := Rect2(r.position.x + r.size.x * 0.2, r.position.y + r.size.y * 0.45, r.size.x * 0.6, r.size.y * 0.45)
	var roof_points := PackedVector2Array([Vector2(r.position.x + r.size.x * 0.08, base.position.y + 1),
			Vector2(r.get_center().x, r.position.y + r.size.y * 0.1), Vector2(r.end.x - r.size.x * 0.08, base.position.y + 1)])
	canvas.draw_rect(base.grow(1.5), OUTLINE)
	canvas.draw_colored_polygon(_grown_triangle(roof_points, 2.0), OUTLINE)
	canvas.draw_rect(base, wall)
	canvas.draw_colored_polygon(roof_points, roof)
	# Door (6 x 9 px, smaller when the icon is small, e.g. on the minimap).
	var door := Vector2(minf(6.0, base.size.x * 0.34), minf(9.0, base.size.y * 0.75))
	canvas.draw_rect(Rect2(base.get_center().x - door.x / 2.0, base.end.y - door.y, door.x, door.y), Color(0.15, 0.2, 0.4) * tint)


static func _grown_triangle(points: PackedVector2Array, by: float) -> PackedVector2Array:
	var center := (points[0] + points[1] + points[2]) / 3.0
	var grown := PackedVector2Array()
	for p in points:
		grown.append(p + (p - center).normalized() * by)
	return grown
