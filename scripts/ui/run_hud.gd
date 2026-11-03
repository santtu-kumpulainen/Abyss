class_name RunHud
extends CanvasLayer
## Shows the run's level, XP progress and currency, e.g. "Lv 2   XP 30/100   Gold 15",
## or "Lv 3 (MAX)   Gold 15" at the level cap. show_message() briefly shows a
## centred announcement (e.g. level-up unlocks).

## Seconds a message stays fully visible before fading out.
@export var message_duration: float = 3.0

@onready var _label: Label = %RunLabel
@onready var _message: Label = %MessageLabel

var _run_state: RunState
var _message_tween: Tween


## Displays `run_state` and follows its changes.
func set_run_state(run_state: RunState) -> void:
	if _run_state and _run_state.changed.is_connected(_refresh):
		_run_state.changed.disconnect(_refresh)
	_run_state = run_state
	_run_state.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _run_state.is_max_level():
		_label.text = "Lv %d (MAX)   Gold %d" % [_run_state.level, _run_state.currency]
		return
	_label.text = "Lv %d   XP %d/%d   Gold %d" % [
		_run_state.level, _run_state.xp, _run_state.xp_to_next_level(), _run_state.currency]


## Shows `text` centred near the top, then fades it out.
func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_message.show()
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(message_duration)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)
	_message_tween.tween_callback(_message.hide)
