class_name MainMenu
extends Control
## Main menu: Start Run opens the run setup panel (difficulty + optional Pact),
## Begin Run stores the selection in the Progression autoload and loads
## `dungeon_scene` as a fresh run (its RunState is created with the scene and
## configured from that selection). Locked difficulties are shown disabled
## with their unlock requirement. Quit closes the game. The menu shows the
## best run record. The setup panel can start the run at an already reached
## dungeon level (never above Progression.highest_level): level 1 is a normal
## endless run, higher levels are practice runs (new build, no records or
## unlocks).
## The gear button (top right) opens Settings, which lists the controls
## (ControlsInfo, keys read from the InputMap; Issue #55). Back or Escape
## returns to the menu; Settings changes nothing else.

## Key column colour of the controls list (the Anvil prompt / ability bar gold).
const CONTROL_KEY_COLOR := Color(1, 0.9, 0.55, 1)

@export var dungeon_scene: PackedScene

## Selection shown in the setup panel.
var selected_difficulty: int = Difficulty.Tier.NORMAL
var selected_pact: StringName = &""
var selected_start_level: int = 1

var _progression: ProgressionStore
var _difficulty_group := ButtonGroup.new()
var _pact_group := ButtonGroup.new()

@onready var _menu: Control = %Center
@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton
@onready var _setup: Control = %RunSetup
@onready var _difficulty_buttons: Container = %DifficultyButtons
@onready var _difficulty_info: Label = %DifficultyInfo
@onready var _pact_buttons: Container = %PactButtons
@onready var _pact_info: Label = %PactInfo
@onready var _best_run_label: Label = %BestRunLabel
@onready var _prev_level_button: Button = %PrevLevelButton
@onready var _next_level_button: Button = %NextLevelButton
@onready var _start_level_label: Label = %StartLevelLabel
@onready var _begin_button: Button = %BeginButton
@onready var _back_button: Button = %BackButton
@onready var _gear_button: Button = %GearButton
@onready var _gear_icon: Control = %GearIcon
@onready var _settings: Control = %Settings
@onready var _controls_grid: GridContainer = %ControlsGrid
@onready var _anvil_grid: GridContainer = %AnvilGrid
@onready var _settings_back_button: Button = %SettingsBackButton


func _ready() -> void:
	# A previous run may have ended paused (victory screen).
	get_tree().paused = false
	_progression = ProgressionStore.instance(get_tree())
	# Normal gameplay music (Issue #53); keeps playing into the run without a restart.
	AudioManager.instance(get_tree()).play_music(SoundLibrary.MUSIC_NORMAL)
	selected_difficulty = _progression.selected_difficulty
	selected_pact = _progression.selected_pact
	selected_start_level = clampi(_progression.selected_start_level, 1, _progression.highest_level)
	_build_buttons()
	_prev_level_button.pressed.connect(select_start_level.bind(-1, true))
	_next_level_button.pressed.connect(select_start_level.bind(1, true))
	_best_run_label.text = "Best Run: " + _progression.best_run_text()
	_start_button.pressed.connect(open_setup)
	_quit_button.pressed.connect(get_tree().quit)
	_begin_button.pressed.connect(begin_run)
	_back_button.pressed.connect(close_setup)
	_gear_button.pressed.connect(open_settings)
	_gear_icon.draw.connect(_draw_gear)
	_gear_button.mouse_entered.connect(_gear_icon.queue_redraw)
	_gear_button.mouse_exited.connect(_gear_icon.queue_redraw)
	_settings_back_button.pressed.connect(close_settings)
	_build_controls(_controls_grid, ControlsInfo.GAMEPLAY)
	_build_controls(_anvil_grid, ControlsInfo.ANVIL)
	_setup.hide()
	_settings.hide()
	_start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _settings.visible and event.is_action_pressed(&"ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()


## Shows Settings (the controls list) in place of the main menu.
func open_settings() -> void:
	_menu.hide()
	_gear_button.hide()
	_settings.show()
	_settings_back_button.grab_focus()


func close_settings() -> void:
	_settings.hide()
	_menu.show()
	_gear_button.show()
	_gear_button.grab_focus()


func open_setup() -> void:
	if not _progression.is_unlocked(selected_difficulty):
		selected_difficulty = Difficulty.Tier.NORMAL
	_menu.hide()
	_gear_button.hide()
	_setup.show()
	_refresh()
	_begin_button.grab_focus()


func close_setup() -> void:
	_setup.hide()
	_menu.show()
	_gear_button.show()
	_start_button.grab_focus()


## Selects difficulty `tier` for the next run. Returns false if it is locked.
func select_difficulty(tier: int) -> bool:
	if not _progression.is_unlocked(tier):
		return false
	selected_difficulty = tier
	_refresh()
	return true


## Selects Pact `id` (&"" = none). Returns false if it is unknown.
func select_pact(id: StringName) -> bool:
	if not id.is_empty() and not Pacts.PACTS.has(id):
		return false
	selected_pact = id
	_refresh()
	return true


## Selects the start level for the next run (`relative`: step from the current
## one). Returns false (selection unchanged) if it is below 1 or above the
## highest level reached.
func select_start_level(level: int, relative: bool = false) -> bool:
	if relative:
		level += selected_start_level
	if level < 1 or level > _progression.highest_level:
		return false
	selected_start_level = level
	_refresh()
	return true


## Stores the selection and starts the run.
func begin_run() -> void:
	if not _progression.select(selected_difficulty, selected_pact, selected_start_level):
		return
	start_run()


## Loads the dungeon with the Progression selection.
func start_run() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_packed(dungeon_scene)


func difficulty_button(tier: int) -> Button:
	return _difficulty_buttons.get_node_or_null(Difficulty.display_name(tier)) as Button


func pact_button(id: StringName) -> Button:
	return _pact_buttons.get_node_or_null(String(id) if not id.is_empty() else "none") as Button


func _build_buttons() -> void:
	for tier: int in Difficulty.TIERS:
		var button := _make_button(Difficulty.display_name(tier), _difficulty_group, 160)
		button.add_theme_color_override(&"font_color", Difficulty.data(tier)["color"])
		button.pressed.connect(func() -> void: select_difficulty(tier))
		_difficulty_buttons.add_child(button)
	var none := _make_button("No Pact", _pact_group, 170)
	none.name = "none"
	none.pressed.connect(func() -> void: select_pact(&""))
	_pact_buttons.add_child(none)
	for id: StringName in Pacts.PACTS:
		var button := _make_button(Pacts.pact_name(id), _pact_group, 170)
		button.name = String(id)
		button.pressed.connect(func() -> void: select_pact(id))
		_pact_buttons.add_child(button)


## Fills `grid` (2 columns) with one "keys | what it does" row per entry.
func _build_controls(grid: GridContainer, entries: Array[Dictionary]) -> void:
	for entry: Dictionary in entries:
		var key := Label.new()
		key.text = ControlsInfo.key_text(entry)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.add_theme_font_size_override(&"font_size", 18)
		key.add_theme_color_override(&"font_color", CONTROL_KEY_COLOR)
		key.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
		key.add_theme_constant_override(&"outline_size", 4)
		grid.add_child(key)
		var what := Label.new()
		what.text = entry["text"]
		what.add_theme_font_size_override(&"font_size", 18)
		what.add_theme_color_override(&"font_color", Color(0.92, 0.92, 0.95, 1))
		grid.add_child(what)


## Code-drawn gear icon for the Settings button (the art packs have no UI icons).
func _draw_gear() -> void:
	var area := _gear_icon.size
	var center := area / 2.0
	var outer := minf(area.x, area.y) * 0.34
	var color := Color(0.85, 0.8, 0.95) if not _gear_button.is_hovered() else Color(1, 0.9, 0.55)
	for i in 8:
		var angle := TAU * i / 8.0
		var tooth := PackedVector2Array()
		for corner: Vector2 in [Vector2(-0.18, 0.75), Vector2(0.18, 0.75), Vector2(0.14, 1.25), Vector2(-0.14, 1.25)]:
			tooth.append(center + corner.rotated(angle) * outer)
		_gear_icon.draw_colored_polygon(tooth, color)
	# Ring body (outer edge at 0.9 x outer) with a see-through centre.
	_gear_icon.draw_arc(center, outer * 0.65, 0.0, TAU, 32, color, outer * 0.5, true)


func _make_button(text: String, group: ButtonGroup, width: float) -> Button:
	var button := Button.new()
	button.name = text
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(width, 40)
	button.add_theme_font_size_override(&"font_size", 18)
	return button


func _refresh() -> void:
	_prev_level_button.disabled = selected_start_level <= 1
	_next_level_button.disabled = selected_start_level >= _progression.highest_level
	_start_level_label.text = ("Start at Level 1 - new endless run" if selected_start_level == 1
			else "Start at Level %d - practice run (no records or unlocks)" % selected_start_level)
	_start_level_label.text += "   [highest reached: %d]" % _progression.highest_level
	for tier: int in Difficulty.TIERS:
		var button := difficulty_button(tier)
		var unlocked := _progression.is_unlocked(tier)
		button.disabled = not unlocked
		button.text = Difficulty.display_name(tier) + ("" if unlocked else " (locked)")
		button.tooltip_text = Difficulty.unlock_text(tier)
		button.set_pressed_no_signal(tier == selected_difficulty)
	var lines: Array[String] = ["%s - %s" % [Difficulty.display_name(selected_difficulty),
			"completed %d time(s)" % _progression.completion_count(selected_difficulty)]]
	lines.append(Difficulty.summary_text(selected_difficulty))
	for tier: int in Difficulty.TIERS:
		if not _progression.is_unlocked(tier):
			lines.append("%s locked. %s." % [Difficulty.display_name(tier), Difficulty.unlock_text(tier)])
	_difficulty_info.text = "\n".join(lines)
	for button: Button in _pact_buttons.get_children():
		button.set_pressed_no_signal(button.name == (String(selected_pact) if not selected_pact.is_empty() else "none"))
	if selected_pact.is_empty():
		_pact_info.text = "No Pact: play the run without extra benefits or drawbacks."
	else:
		var data: Dictionary = Pacts.PACTS[selected_pact]
		_pact_info.text = "%s\nBenefit: %s\nDrawback: %s" % [data["name"], data["benefit"], data["drawback"]]
		var synergies: Array[String] = []
		for id: StringName in Pacts.SYNERGIES:
			if Pacts.SYNERGIES[id]["requires"][0].has(selected_pact):
				synergies.append("%s (%s): %s" % [Pacts.SYNERGIES[id]["name"],
						Pacts.SYNERGIES[id]["requires_text"], Pacts.SYNERGIES[id]["effect"]])
		if not synergies.is_empty():
			_pact_info.text += "\nSynergy: " + "\n".join(synergies)
