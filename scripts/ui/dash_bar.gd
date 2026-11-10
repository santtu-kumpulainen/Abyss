class_name DashBar
extends ProgressBar
## Dash cooldown under the Mage's HP bar (Issue #49): empty right after a dash,
## fills as Mage.dash_cooldown_ratio() recovers and flashes when the dash is
## ready again. Reads the Mage every frame and keeps no timer of its own.

## The Mage whose dash is shown (defaults to the parent).
@export var mage: Mage
## Modulate of the short flash when the dash becomes ready.
@export var flash_color := Color(1.8, 1.8, 1.8)
@export var flash_time := 0.25

var _was_ready := true


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	min_value = 0.0
	max_value = 1.0
	step = 0.0
	show_percentage = false
	if mage == null:
		mage = get_parent() as Mage
	if mage == null:
		push_warning("DashBar has no Mage assigned: %s" % get_path())
		hide()
		set_process(false)
		return
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	value = mage.dash_cooldown_ratio()
	var ready := mage.dash_ready()
	if ready and not _was_ready:
		modulate = flash_color
		create_tween().tween_property(self, ^"modulate", Color.WHITE, flash_time)
	_was_ready = ready
