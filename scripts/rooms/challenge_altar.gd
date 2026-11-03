class_name ChallengeAltar
extends Interactable
## Altar that starts a SurvivalRoom's trial: "interact" (E) emits `interacted`
## while the room is still IDLE. Drawn as a stone pedestal with a flame that
## burns while the trial runs and goes out once it is complete.

var _room: Room


func _ready() -> void:
	super._ready()
	_room = find_room()
	if _room:
		_room.state_changed.connect(func(_state: Room.State) -> void: refresh())
	refresh()


func can_interact() -> bool:
	return _room != null and _room.state == Room.State.IDLE


func prompt_text() -> String:
	if _room == null:
		return ""
	match _room.state:
		Room.State.IDLE:
			return "[E] Begin the survival trial"
		Room.State.COMBAT:
			return "Survive!"
	return "The trial is complete"


func _draw() -> void:
	var state := _room.state if _room else Room.State.IDLE
	draw_circle(Vector2(0, 2), 26.0, Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-22, -10, 44, 12), Color(0.36, 0.34, 0.4))
	draw_rect(Rect2(-14, -34, 28, 26), Color(0.46, 0.44, 0.5))
	draw_rect(Rect2(-18, -40, 36, 8), Color(0.55, 0.53, 0.6))
	var flame := Color(1.0, 0.55, 0.15)
	match state:
		Room.State.IDLE:
			draw_circle(Vector2(0, -48), 6.0, Color(flame, 0.6))
		Room.State.COMBAT:
			draw_circle(Vector2(0, -52), 20.0, Color(flame, 0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(-9, -42), Vector2(0, -66), Vector2(9, -42)]), flame)
			draw_circle(Vector2(0, -46), 6.0, Color(1.0, 0.9, 0.5))
		_:
			draw_circle(Vector2(0, -44), 4.0, Color(0.3, 0.3, 0.32))
