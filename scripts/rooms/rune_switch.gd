class_name RuneSwitch
extends Interactable
## Floor rune of a RunePuzzleRoom. "interact" (E) emits `interacted`; the room
## decides whether it was the right rune and sets `lit`/`solved` or calls
## flash_wrong(). Drawn as a stone disc with its glyph (sun, moon or star):
## grey when idle, cyan when lit, gold when the puzzle is solved and briefly
## red after a wrong activation.

@export_enum("sun", "moon", "star") var rune_id: String = "sun":
	set(value):
		rune_id = value
		queue_redraw()

var lit := false:
	set(value):
		lit = value
		refresh()
var solved := false:
	set(value):
		solved = value
		refresh()
## 1.0 right after a wrong activation, fading to 0.
var wrong_flash := 0.0:
	set(value):
		wrong_flash = value
		queue_redraw()

var _flash_tween: Tween


func can_interact() -> bool:
	return not lit and not solved


func prompt_text() -> String:
	if solved:
		return ""
	return "%s rune (lit)" % rune_id.capitalize() if lit else "[E] Touch the %s rune" % rune_id.capitalize()


## Red flash for a wrong activation.
func flash_wrong() -> void:
	if _flash_tween:
		_flash_tween.kill()
	wrong_flash = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, ^"wrong_flash", 0.0, 0.8)


func glyph_color() -> Color:
	var base := Color(0.62, 0.66, 0.78)
	if solved:
		base = Color(1.0, 0.82, 0.35)
	elif lit:
		base = Color(0.4, 0.92, 1.0)
	return base.lerp(Color(1.0, 0.25, 0.25), wrong_flash)


func _draw() -> void:
	var color := glyph_color()
	draw_circle(Vector2.ZERO, 34.0, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, 30.0, Color(0.22, 0.22, 0.27))
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 40, color.darkened(0.2), 3.0)
	if lit or solved or wrong_flash > 0.0:
		draw_circle(Vector2.ZERO, 42.0, Color(color, 0.18))
	match rune_id:
		"sun":
			draw_circle(Vector2.ZERO, 8.0, color)
			for i in 8:
				var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
				draw_line(dir * 12.0, dir * 20.0, color, 3.0)
		"moon":
			var points := PackedVector2Array()
			for i in 17:
				points.append(Vector2.from_angle(lerpf(-PI * 0.75, PI * 0.75, i / 16.0) + PI) * 18.0)
			for i in 17:
				var a := lerpf(PI * 0.75, -PI * 0.75, i / 16.0) + PI
				points.append(Vector2(6.0, 0.0) + Vector2.from_angle(a) * 13.0)
			draw_colored_polygon(points, color)
		"star":
			var star := PackedVector2Array()
			for i in 10:
				var r := 19.0 if i % 2 == 0 else 8.0
				star.append(Vector2.UP.rotated(TAU * i / 10.0) * r)
			draw_colored_polygon(star, color)
