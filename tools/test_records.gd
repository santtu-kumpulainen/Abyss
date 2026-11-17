extends SceneTree
## Headless check of per-difficulty records, their migration from the old
## single best run, Settings -> Reset Records (cancel and confirm) and the
## main menu's unfinished-run options (Continue / New Run confirmation /
## damaged save) (Issue #63).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_records.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const RECORDS_FILE := "user://progression_records_suite.cfg"
const RUN_FILE := "user://run_save_records_suite.json"
const NORMAL := Difficulty.Tier.NORMAL
const HARD := Difficulty.Tier.HARD
const ABYSSAL := Difficulty.Tier.ABYSSAL

var _failures := 0
var _prog: ProgressionStore


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_prog = ProgressionStore.instance(self)
	var real_path := _prog.save_path
	_prog.save_path = RECORDS_FILE
	RunSave.path_override = RUN_FILE
	_prog.clear_progress()
	_test_independent_records()
	_test_save_and_migration()
	await _test_records_screen_and_reset()
	await _test_continue_menu()
	DirAccess.remove_absolute(RECORDS_FILE)
	RunSave.delete()
	RunSave.path_override = ""
	_prog.save_path = real_path
	_prog.clear_progress()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_independent_records() -> void:
	_prog.clear_progress()
	_prog.record_run(1, 3, 300.0, 250.0, NORMAL, &"dungeon", 40, 2)
	_prog.record_run(2, 2, 200.0, 150.0, HARD, &"dungeon", 25, 1)
	_check(_prog.record_for(NORMAL)["level"] == 3 and _prog.record_for(HARD)["level"] == 2 and _prog.record_for(ABYSSAL).is_empty(),
			"each difficulty keeps its own best level")
	_prog.record_run(3, 5, 500.0, 450.0, HARD, &"cave", 80, 4)
	_check(_prog.record_for(HARD)["level"] == 5 and _prog.record_for(NORMAL)["level"] == 3 and _prog.record_for(NORMAL)["run_id"] == 1,
			"a better Hard run does not overwrite the Normal record")
	_prog.record_run(4, 2, 90.0, 60.0, NORMAL, &"dungeon", 10, 1)
	_check(_prog.record_for(NORMAL)["level"] == 3, "a lower level never replaces a record")
	_prog.record_run(1, 3, 330.0, 250.0, NORMAL, &"dungeon", 46, 3)
	var normal := _prog.record_for(NORMAL)
	_check(normal["enemies"] == 46 and normal["bosses"] == 3 and is_equal_approx(normal["time"], 330.0)
			and is_equal_approx(normal["reach_time"], 250.0), "the same run refreshes its stats, keeping its reach time")
	_check(_prog.best_run["level"] == 5 and _prog.best_run["difficulty"] == HARD and _prog.highest_level == 5,
			"the overall best run and highest level still span every difficulty")


func _test_save_and_migration() -> void:
	# Round trip through the file.
	var saved := _prog.records.duplicate(true)
	var loaded := ProgressionStore.new()
	loaded.save_path = RECORDS_FILE
	loaded.load_progress()
	_check(loaded.records == saved and loaded.best_run == _prog.best_run, "per-difficulty records survive a restart")
	loaded.free()
	# Old format: one best_run for all difficulties, no record sections.
	var legacy := ConfigFile.new()
	legacy.set_value("completions", "normal", 2)
	legacy.set_value("records", "highest_level", 4)
	legacy.set_value("best_run", "level", 4)
	legacy.set_value("best_run", "time", 400.0)
	legacy.set_value("best_run", "reach_time", 350.0)
	legacy.set_value("best_run", "difficulty", HARD)
	legacy.set_value("best_run", "biome", "cave")
	legacy.set_value("best_run", "run_id", 77)
	legacy.save(RECORDS_FILE)
	var migrated := ProgressionStore.new()
	migrated.save_path = RECORDS_FILE
	migrated.load_progress()
	var hard := migrated.record_for(HARD)
	_check(not hard.is_empty() and hard["level"] == 4 and hard["run_id"] == 77 and hard["enemies"] == -1
			and migrated.record_for(NORMAL).is_empty() and migrated.highest_level == 4 and migrated.completion_count(NORMAL) == 2,
			"an old save migrates: its best run becomes that difficulty's record, nothing is lost")
	migrated.save_progress()
	var config := ConfigFile.new()
	config.load(RECORDS_FILE)
	_check(config.get_value("records_hard", "level", 0) == 4 and config.get_value("best_run", "level", 0) == 4
			and config.get_value("records", "format", 0) == ProgressionStore.RECORDS_FORMAT,
			"the migrated save is written in the new format (old keys kept)")
	migrated.free()
	# A damaged record section is ignored without touching the others.
	config.set_value("records_normal", "level", "bogus")
	config.set_value("records_normal", "difficulty", NORMAL)
	config.save(RECORDS_FILE)
	var damaged := ProgressionStore.new()
	damaged.save_path = RECORDS_FILE
	damaged.load_progress()
	_check(damaged.record_for(NORMAL).is_empty() and damaged.record_for(HARD)["level"] == 4, "a damaged record is ignored, others stay")
	damaged.free()
	# Back to the records of the first test for the screen tests.
	_prog.save_progress()


func _test_records_screen_and_reset() -> void:
	_prog.ability_slots = [&"home_teleport", &"health_potion", &"speed_potion"]
	_prog.record_victory(NORMAL)
	_prog.save_progress()
	await _write_valid_run_save()
	var run_save_text := FileAccess.get_file_as_string(RUN_FILE)
	var menu := await _load_menu()
	menu.open_records()
	var normal_row := menu.record_row(NORMAL)
	var hard_row := menu.record_row(HARD)
	var abyssal_row := menu.record_row(ABYSSAL)
	_check(normal_row[0] == "Normal" and normal_row[1] == "Level 3" and normal_row[4] == "3" and normal_row[5] == "46",
			"Records screen: Normal row (%s)" % ", ".join(normal_row))
	_check(hard_row[0] == "Hard" and hard_row[1] == "Level 5", "Records screen: Hard row (%s)" % ", ".join(hard_row))
	_check(abyssal_row[0] == "Abyssal" and abyssal_row[1] == "No runs yet", "Records screen: Abyssal has no record yet")
	var grid := menu.get_node(^"%RecordsGrid") as GridContainer
	_check(grid.get_child_count() == 6 * (1 + Difficulty.TIERS.size()), "Records grid: a header and one row per difficulty")
	menu.close_records()
	menu.open_settings()
	# Cancel: nothing changes.
	(menu.get_node(^"%ResetRecordsButton") as Button).pressed.emit()
	var dialog := menu.get_node(^"%ConfirmDialog") as ConfirmationDialog
	_check(menu.is_confirming() and dialog.dialog_text.contains("cannot be undone"), "Reset Records asks for confirmation first")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(not menu.is_confirming() and _prog.record_for(NORMAL)["level"] == 3 and _prog.record_for(HARD)["level"] == 5,
			"cancelling keeps every record")
	# Confirm: records are gone, everything else stays.
	(menu.get_node(^"%ResetRecordsButton") as Button).pressed.emit()
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check(_prog.records.is_empty() and _prog.best_run.is_empty() and _prog.highest_level == 1,
			"confirming resets the records of every difficulty")
	_check(_prog.completion_count(NORMAL) == 1 and _prog.ability_slots[0] == &"home_teleport"
			and FileAccess.get_file_as_string(RUN_FILE) == run_save_text,
			"unlocks, preferences and the unfinished-run save are kept")
	_check((menu.get_node(^"%BestRunLabel") as Label).text == "Best Run: No runs yet"
			and menu.record_row(HARD)[1] == "No runs yet", "the menu refreshes at once")
	var reloaded := ProgressionStore.new()
	reloaded.save_path = RECORDS_FILE
	reloaded.load_progress()
	_check(reloaded.records.is_empty() and reloaded.best_run.is_empty() and reloaded.completion_count(NORMAL) == 1,
			"the reset persists after a restart")
	reloaded.free()
	_prog.ability_slots = ProgressionStore.default_ability_slots()


func _test_continue_menu() -> void:
	await _write_valid_run_save()
	var menu := await _load_menu()
	var cont := menu.get_node(^"%ContinueButton") as Button
	var start := menu.get_node(^"%StartButton") as Button
	_check(cont.visible and start.text == "New Run" and (menu.get_node(^"%RunInfoLabel") as Label).text.contains("Level"),
			"a valid save shows Continue, New Run and the run's details")
	# New Run asks first; cancelling keeps the menu and the save.
	start.pressed.emit()
	var dialog := menu.get_node(^"%ConfirmDialog") as ConfirmationDialog
	_check(menu.is_confirming() and not (menu.get_node(^"%RunSetup") as Control).visible, "New Run asks before replacing the saved run")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(not (menu.get_node(^"%RunSetup") as Control).visible and RunSave.read()["status"] == RunSave.Status.VALID,
			"cancelling keeps the saved run")
	start.pressed.emit()
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check((menu.get_node(^"%RunSetup") as Control).visible, "confirming opens the new run setup")
	menu.close_setup()
	# A damaged save: no Continue, an explanation instead.
	var file := FileAccess.open(RUN_FILE, FileAccess.WRITE)
	file.store_string("{ damaged")
	file.close()
	menu.refresh_save()
	_check(not cont.visible and start.text == "Start Run"
			and (menu.get_node(^"%RunInfoLabel") as Label).text.contains("could not be loaded"), "a damaged save is explained, no Continue")
	_check(not menu.continue_run(), "Continue refuses a damaged save")
	# Continue resumes the valid run.
	await _write_valid_run_save()
	menu = await _load_menu()
	cont = menu.get_node(^"%ContinueButton") as Button
	_check(cont.visible, "returning to the menu offers Continue again")
	var scene_id := current_scene.get_instance_id()
	cont.pressed.emit()
	await _wait_for_scene(scene_id)
	var dungeon := current_scene as Dungeon
	_check(dungeon != null and dungeon.resumed, "Continue resumes the saved run")
	await _load_menu()


## Starts a run in a Dungeon and keeps its first save (a valid run save).
func _write_valid_run_save() -> void:
	RunState.seed_override = 4242
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file("res://scenes/dungeon/dungeon.tscn")
	await _wait_for_scene(scene_id)
	RunState.seed_override = 0


func _load_menu() -> MainMenu:
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(MENU_SCENE)
	await _wait_for_scene(scene_id)
	return current_scene as MainMenu


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


func _wait_for_scene(old_id: int) -> void:
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await process_frame
	for i in 3:
		await physics_frame
	await process_frame
