class_name RunHud
extends CanvasLayer
## Shows the run's level, XP progress and currency, e.g. "Lv 2   XP 30/100   Gold 15".

@onready var _label: Label = %RunLabel

var _run_state: RunState


## Displays `run_state` and follows its changes.
func set_run_state(run_state: RunState) -> void:
	if _run_state and _run_state.changed.is_connected(_refresh):
		_run_state.changed.disconnect(_refresh)
	_run_state = run_state
	_run_state.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_label.text = "Lv %d   XP %d/%d   Gold %d" % [
		_run_state.level, _run_state.xp, _run_state.xp_to_next_level(), _run_state.currency]
