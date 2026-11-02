class_name HealthBar
extends ProgressBar
## Shows a Health node's current/max health. Updates immediately on the
## Health's damaged/died signals.

## The Health component to display.
@export var health: Health
## Hide the bar when the owner dies (otherwise it stays visible at 0).
@export var hide_on_death: bool = true
## Show a "current / max" label on the bar.
@export var show_numbers: bool = false

@onready var _label: Label = $Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_label.visible = show_numbers
	if health == null:
		push_warning("HealthBar has no Health assigned: %s" % get_path())
		hide()
		return
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_refresh()
	if health.is_node_ready() and health.is_dead():
		_on_died()


func _refresh() -> void:
	max_value = health.max_health
	# Health sets `current` in its own _ready; before that it is full.
	value = health.current if health.is_node_ready() else health.max_health
	_label.text = "%d / %d" % [ceili(value), ceili(max_value)]


func _on_damaged(_amount: float, _current: float) -> void:
	_refresh()


func _on_died() -> void:
	_refresh()
	if hide_on_death:
		hide()
