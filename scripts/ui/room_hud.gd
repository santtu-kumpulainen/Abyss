class_name RoomHud
extends CanvasLayer
## Shows the room's encounter state: nothing while idle,
## "Enemies remaining: N" during combat and "Room cleared" after victory
## (Room.status_text(), which special rooms override).

## The Room to display.
@export var room: Room

@onready var _label: Label = %StatusLabel


func _ready() -> void:
	if room == null:
		# A Dungeon assigns rooms at runtime with set_room().
		_label.hide()
		return
	set_room(room)


## Shows `new_room` instead of the current room (e.g. after a room transition).
func set_room(new_room: Room) -> void:
	if room and room.state_changed.is_connected(_on_room_changed):
		room.state_changed.disconnect(_on_room_changed)
		room.enemies_remaining_changed.disconnect(_on_room_changed)
		room.status_changed.disconnect(_refresh)
	room = new_room
	room.state_changed.connect(_on_room_changed)
	room.enemies_remaining_changed.connect(_on_room_changed)
	room.status_changed.connect(_refresh)
	_refresh()


func _on_room_changed(_value: Variant) -> void:
	_refresh()


func _refresh() -> void:
	_label.text = room.status_text()
	_label.visible = not _label.text.is_empty()
