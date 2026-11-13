extends SceneTree
## Headless check of the Issue #55 Stage 1 controls guide:
## - ControlsInfo lists only real InputMap bindings, covers every gameplay
##   action of the InputMap and shows the expected key names;
## - main menu: the gear opens Settings > Controls (rows from ControlsInfo),
##   Back and Escape close it, nothing else in the menu changes;
## - Home room: the floor ControlsGuide is visible, shows the same controls,
##   lies inside the floor clear of doors, obstacles, the Anvil (prompt and
##   interact area) and the Mage's start, draws above the floor but below
##   characters, and has no collision or mouse input.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_controls_guide.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const MENU := "res://scenes/ui/main_menu.tscn"
const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const SEED := 5555

var _failures := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_input_map()
	await _test_menu()
	await _test_home_room()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_input_map() -> void:
	var listed := ControlsInfo.listed_actions()
	for action in listed:
		_check(InputMap.has_action(action) and not ControlsInfo.action_key(action).is_empty(),
				"listed action '%s' is bound (%s)" % [action, ControlsInfo.action_key(action)])
	var unique := {}
	for action in listed:
		unique[action] = true
	_check(unique.size() == listed.size(), "no action is listed twice")
	# Every gameplay action of the project (not Godot's built-in ui_*) is documented.
	for property in ProjectSettings.get_property_list():
		var key: String = property["name"]
		if key.begins_with("input/") and not key.begins_with("input/ui_"):
			var action := StringName(key.trim_prefix("input/"))
			_check(listed.has(action), "InputMap action '%s' is documented" % action)
	var expected := {
		"Move": "W A S D", "Aim": "Mouse", "Cast Fire Ball": "Left Click (hold)", "Dash": "Space",
		"Interact": "E", "Use item slots": "1-3", "Buy upgrade": "1-4", "Buy supply": "5-7",
	}
	for entry: Dictionary in ControlsInfo.GAMEPLAY + ControlsInfo.ANVIL:
		var what := ControlsInfo.short_text(entry["text"])
		_check(expected.get(what, "?") == ControlsInfo.key_text(entry),
				"%s shows '%s' (expected '%s')" % [what, ControlsInfo.key_text(entry), expected.get(what, "?")])


func _test_menu() -> void:
	change_scene_to_file(MENU)
	await _until_ready()
	var menu := current_scene as MainMenu
	var gear := menu.get_node(^"%GearButton") as Button
	var settings := menu.get_node(^"%Settings") as Control
	var main := menu.get_node(^"%Center") as Control
	var back := menu.get_node(^"%SettingsBackButton") as Button
	var before := [menu.selected_difficulty, menu.selected_pact, menu.selected_start_level]
	_check(gear.visible and not settings.visible and main.visible, "menu starts with the gear shown and Settings closed")
	_check(gear.tooltip_text == "Settings", "the gear is labelled Settings")

	gear.pressed.emit()
	await process_frame
	_check(settings.visible and not main.visible and not gear.visible, "the gear opens Settings in place of the menu")
	_check(back.has_focus(), "Settings focuses its Back button")
	var grid := menu.get_node(^"%ControlsGrid") as GridContainer
	var anvil := menu.get_node(^"%AnvilGrid") as GridContainer
	_check(grid.get_child_count() == ControlsInfo.GAMEPLAY.size() * 2, "one row per gameplay control")
	_check(anvil.get_child_count() == ControlsInfo.ANVIL.size() * 2, "one row per Anvil key group")
	var rows_ok := true
	for i in ControlsInfo.GAMEPLAY.size():
		var entry: Dictionary = ControlsInfo.GAMEPLAY[i]
		rows_ok = rows_ok and (grid.get_child(i * 2) as Label).text == ControlsInfo.key_text(entry) \
				and (grid.get_child(i * 2 + 1) as Label).text == entry["text"]
	_check(rows_ok, "Settings rows match ControlsInfo (keys from the InputMap)")

	back.pressed.emit()
	await process_frame
	_check(not settings.visible and main.visible and gear.visible, "Back returns to the menu")

	gear.pressed.emit()
	await process_frame
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	menu._unhandled_input(cancel)
	await process_frame
	_check(not settings.visible and main.visible, "Escape (ui_cancel) closes Settings")
	_check([menu.selected_difficulty, menu.selected_pact, menu.selected_start_level] == before,
			"opening Settings changes no run selection")

	menu.open_setup()
	_check(not gear.visible, "the gear hides while the run setup is open")
	menu.close_setup()
	_check(gear.visible and main.visible, "closing the run setup brings the gear back")


func _test_home_room() -> void:
	RunState.seed_override = SEED
	change_scene_to_file(DUNGEON)
	await _until_ready()
	for i in 3:
		await physics_frame
	var dungeon := current_scene as Dungeon
	var room := dungeon.current_room
	_check(dungeon.current_index == dungeon.start_room, "the run starts in the Home room")
	var guide := room.get_node_or_null(^"ControlsGuide") as ControlsGuide
	_check(guide != null, "the Home room has a ControlsGuide")
	if guide == null:
		RunState.seed_override = 0
		return
	await process_frame
	_check(guide.is_visible_in_tree(), "the guide is visible")

	var lines := guide.shown_lines()
	var text := "\n".join(lines)
	var all_shown := true
	for entry: Dictionary in ControlsInfo.GAMEPLAY:
		all_shown = all_shown and lines.has(ControlsInfo.key_text(entry)) and lines.has(ControlsInfo.short_text(entry["text"]))
	_check(all_shown, "the guide shows every gameplay control with its key")
	_check(text.contains(ControlsInfo.anvil_line()), "the guide shows the Anvil keys")

	var plate := guide.plate_rect()
	var floor_rect := (room.get_node(^"Visuals") as RoomVisuals).floor_rect
	_check(plate.size.x > 200.0 and plate.size.y > 120.0, "readable plate size (%s)" % plate.size)
	_check(floor_rect.grow(-48.0).encloses(plate), "the plate lies inside the floor, clear of the walls")
	for door in room.get_doors():
		_check(_distance(plate, dungeon._room_position(room, door)) >= 120.0, "the plate is clear of door %s" % door.name)
	var obstacles_clear := true
	for node in room.find_children("*", "Obstacle", true, false):
		var o := node as Obstacle
		var footprint := Rect2(dungeon._room_position(room, o) - o.footprint / 2.0, o.footprint).grow(8.0)
		obstacles_clear = obstacles_clear and not footprint.intersects(plate)
	_check(obstacles_clear, "the plate overlaps no obstacle")
	for node in room.find_children("*", "UpgradeStation", true, false):
		var station := node as UpgradeStation
		var at := dungeon._room_position(room, station)
		var prompt := station.get_node(^"Prompt") as Label
		var prompt_rect := Rect2(at + prompt.position, prompt.size)
		_check(not prompt_rect.intersects(plate), "the plate does not cover the Anvil prompt")
		var shape := (station.get_node(^"InteractArea/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
		_check(_distance(plate, at) > shape.radius, "the plate is outside the Anvil interact area")
	var mage_start := room.to_local(dungeon.mage.global_position)
	_check(_distance(plate, mage_start) >= 60.0, "the plate leaves room for the Mage at its start (and its HP bar)")

	var visuals_z := (room.get_node(^"Visuals") as Node2D).z_index
	_check(guide.z_index > visuals_z and guide.z_index < dungeon.mage.z_index, "drawn above the floor and below characters")
	var passive := true
	for node in guide.find_children("*", "", true, false):
		if node is CollisionObject2D:
			passive = false
		elif node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			passive = false
	_check(passive, "no collision and no mouse input (never blocks movement or casting)")
	RunState.seed_override = 0


func _distance(rect: Rect2, point: Vector2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))


func _until_ready() -> void:
	for i in 600:
		if current_scene != null and current_scene.is_node_ready():
			break
		await physics_frame
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
