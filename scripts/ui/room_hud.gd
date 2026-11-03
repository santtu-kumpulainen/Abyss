class_name RoomHud
extends CanvasLayer
## Shows the room's encounter state: nothing while idle,
## "Enemies remaining: N" during combat and "Room cleared" after victory.

## The Room to display.
@export var room: Room

@onready var _label: Label = %StatusLabel


func _ready() -> void:
	if room == null:
		push_warning("RoomHud has no Room assigned: %s" % get_path())
		hide()
		return
	room.state_changed.connect(_refresh.unbind(1))
	room.enemies_remaining_changed.connect(_refresh.unbind(1))
	_refresh()


func _refresh() -> void:
	match room.state:
		Room.State.COMBAT:
			_label.text = "Enemies remaining: %d" % room.enemies_remaining
		Room.State.CLEARED:
			_label.text = "Room cleared"
		_:
			_label.text = ""
	_label.visible = not _label.text.is_empty()
