class_name LaneCharge
extends RefCounted
## Shared telegraphed straight-line dash (Issue #47), used by the Brood Mother's
## charge and the Blood Monster's dash. The owner locks the aim at the start of
## its windup (begin()), draws the lane while it winds up (draw_lane()) and calls
## step() every physics frame of the dash. The lane is exactly the hit area: a
## strip `hit_radius` wide on each side of the aim, `distance` long. The dash
## stops at `distance` or at a wall and hits the victim at most once.

## Locked dash direction (unit vector).
var aim := Vector2.RIGHT
## Pixels moved so far in this dash.
var travelled := 0.0
## True once this dash has hit its victim.
var hit := false
var speed := 0.0
var distance := 0.0
var hit_radius := 0.0
var damage := 0.0


## Locks a new dash from `from` towards `at` with the given values (read from the
## owner's scaled exports at windup start).
func begin(from: Vector2, at: Vector2, dash_speed: float, dash_distance: float, radius: float, dash_damage: float) -> void:
	aim = (at - from).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	travelled = 0.0
	hit = false
	speed = dash_speed
	distance = dash_distance
	hit_radius = radius
	damage = dash_damage


## One physics frame of the dash for `body` (sets its velocity; the owner calls
## move_and_slide()). Hits `victim` once if it is within hit_radius. Returns true
## when the dash is over (wall reached or full distance travelled).
func step(body: CharacterBody2D, delta: float, victim: Node2D) -> bool:
	if travelled > 0.0 and body.is_on_wall():
		return true
	body.velocity = aim * speed
	travelled += speed * delta
	if not hit and victim and body.global_position.distance_to(victim.global_position) <= hit_radius:
		hit = true
		victim.take_damage(damage)
		HitFeedback.knock(victim, aim)
	return travelled >= distance


## Draws the locked lane on `canvas` (local to the dashing body), filling with
## windup `progress` 0..1.
func draw_lane(canvas: CanvasItem, progress: float) -> void:
	var side := aim.orthogonal() * hit_radius
	var lane := PackedVector2Array([side, aim * distance + side, aim * distance - side, -side])
	canvas.draw_colored_polygon(lane, Color(1.0, 0.3, 0.2, 0.12 + 0.18 * progress))
	canvas.draw_line(Vector2.ZERO, aim * distance * progress, Color(1.0, 0.4, 0.2, 0.8), 3.0)
	canvas.draw_polyline(lane + PackedVector2Array([lane[0]]), Color(1.0, 0.45, 0.25, 0.9), 2.0)
