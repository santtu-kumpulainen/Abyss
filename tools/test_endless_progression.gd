extends SceneTree
## Headless check of endless level progression: level scaling combined with
## the difficulty modifier, biome transitions, boss -> relic -> next level
## (build kept, level state reset), run timer, best-run records (rules and
## persistence) and level-select restrictions / replay runs.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_endless_progression.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"
const BOSS := Vector2i(2, 0)
const GOBLIN_ROOM := Vector2i(0, 4)
const NORMAL := Difficulty.Tier.NORMAL
const HARD := Difficulty.Tier.HARD

var _failures := 0
var _prog: ProgressionStore
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_prog = ProgressionStore.instance(self)
	_prog.clear_progress()
	_test_level_scaling_data()
	_test_biome_data()
	_test_record_rules()
	_test_record_persistence()
	await _load_scene(SCENE)
	await _test_flow_and_timer()
	await _test_biome_transition_and_scaling()
	await _test_game_over_record()
	await _test_level_select_and_replay()
	await _test_menu()
	_prog.clear_progress()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Pure data ----------------------------------------------------------------

func run_cap_ok() -> bool:
	var run := RunState.new()
	run.configure(Difficulty.Tier.ABYSSAL)
	run.dungeon_level = 99
	var ok := run.extra_room_enemies(2, 8) == RunState.MAX_EXTRA_ENEMIES and run.extra_wave_enemies() == RunState.MAX_EXTRA_ENEMIES
	run.free()
	return ok


func _test_level_scaling_data() -> void:
	_check(is_equal_approx(LevelScaling.enemy_health(1), 1.0) and is_equal_approx(LevelScaling.enemy_damage(1), 1.0)
			and is_equal_approx(LevelScaling.enemy_pace(1), 1.0) and LevelScaling.room_extra_enemies(1, true, 8) == 0,
			"level 1 is unscaled")
	_check(LevelScaling.enemy_health(5) > LevelScaling.enemy_health(2) and LevelScaling.enemy_damage(5) > LevelScaling.enemy_damage(2)
			and LevelScaling.room_extra_enemies(5, false, 8) > LevelScaling.room_extra_enemies(2, false, 8), "enemies get tougher with the level")
	_check(LevelScaling.enemy_pace(99) <= 1.0 + LevelScaling.PACE_CAP + 0.0001 and run_cap_ok(),
			"speed and extra enemies are capped")
	var run := RunState.new()
	run.configure(HARD)
	var hard := Difficulty.data(HARD)
	_check(is_equal_approx(run.enemy_health_multiplier(), hard["enemy_health"]) and run.extra_room_enemies(2, 8) == hard["extra_lv2"],
			"Hard at level 1: only the difficulty modifier applies")
	run.dungeon_level = 5
	_check(is_equal_approx(run.enemy_health_multiplier(), hard["enemy_health"] * LevelScaling.enemy_health(5))
			and is_equal_approx(run.enemy_damage_multiplier(), hard["enemy_damage"] * LevelScaling.enemy_damage(5) * RunState.ENEMY_DAMAGE_FACTOR)
			and is_equal_approx(run.enemy_pace_multiplier(), hard["enemy_pace"] * LevelScaling.enemy_pace(5))
			and run.extra_room_enemies(2, 8) == mini(hard["extra_lv2"] + LevelScaling.room_extra_enemies(5, true, 8), RunState.MAX_EXTRA_ENEMIES)
			and run.extra_wave_enemies() == mini(hard["extra_wave"] + LevelScaling.wave_extra_enemies(5), RunState.MAX_EXTRA_ENEMIES),
			"difficulty and level scaling multiply / add")
	_check(is_equal_approx(run.spell_damage_multiplier(), 1.0) and run.xp_to_next_level() == 50 and is_equal_approx(run.move_speed_multiplier(), 1.0)
			and is_equal_approx(run.gold_multiplier(), hard["gold"]), "player stats, XP and gold are not scaled by level")
	run.free()


func _test_biome_data() -> void:
	var interval := Biomes.default_levels
	_check(interval >= 3 and interval <= 5, "default biome interval is 3-5 (%d)" % interval)
	_check(Biomes.biome_id(1) == &"dungeon" and Biomes.biome_id(interval) == &"dungeon" and Biomes.biome_id(interval + 1) == &"caverns",
			"the biome changes after %d levels" % interval)
	_check(Biomes.is_transition(interval + 1) and not Biomes.is_transition(interval) and not Biomes.is_transition(1),
			"biome transitions are detected")
	_check(Biomes.biome_id(interval * 2 + 1) == &"dungeon", "the biome list repeats, so the run is endless")
	Biomes.default_levels = 4
	_check(Biomes.biome_id(4) == &"dungeon" and Biomes.biome_id(5) == &"caverns" and Biomes.biome_id(9) == &"dungeon",
			"the interval is configurable")
	Biomes.default_levels = interval
	_check(Biomes.theme_for(1) == null and Biomes.theme_for(interval + 1) != null, "the second biome overrides the room theme")
	_check(Biomes.relic_pool(1).size() == RunState.RELICS.size(), "empty biome relic pool offers every relic")
	var run := RunState.new()
	run.dungeon_level = interval + 1
	run.free()


func _test_record_rules() -> void:
	_prog.clear_progress()
	_check(_prog.best_run.is_empty() and _prog.highest_level == 1 and _prog.best_run_text() == "No runs yet", "no record before the first run")
	_check(_prog.record_run(1, 1, 10.0, 0.0, NORMAL, &"dungeon") and _prog.best_run["level"] == 1, "the first run creates a record")
	_check(_prog.record_run(1, 2, 70.0, 60.0, NORMAL, &"dungeon") and _prog.best_run["level"] == 2 and _prog.highest_level == 2,
			"reaching a higher level updates the record and the highest level")
	_check(_prog.record_run(1, 2, 95.0, 60.0, NORMAL, &"dungeon") and is_equal_approx(_prog.best_run["time"], 95.0)
			and is_equal_approx(_prog.best_run["reach_time"], 60.0), "the same run refreshes its duration, keeping its reach time")
	_check(not _prog.record_run(2, 2, 200.0, 150.0, HARD, &"dungeon") and _prog.best_run["difficulty"] == NORMAL,
			"a slower run to the same level does not replace the record")
	_check(_prog.record_run(3, 2, 80.0, 50.0, HARD, &"dungeon") and _prog.best_run["difficulty"] == HARD,
			"a faster run to the same level replaces the record")
	_check(not _prog.record_run(4, 1, 5.0, 0.0, NORMAL, &"dungeon") and _prog.best_run["level"] == 2, "a lower level never replaces the record")
	_check(_prog.best_run_text().contains("Level 2") and _prog.best_run_text().contains("Hard") and _prog.best_run_text().contains("01:20"),
			"best run text shows level, difficulty and time (%s)" % _prog.best_run_text())


func _test_record_persistence() -> void:
	var loaded := ProgressionStore.new()
	loaded.save_path = ProgressionStore.TEST_SAVE_PATH
	loaded.load_progress()
	_check(loaded.best_run == _prog.best_run and loaded.highest_level == _prog.highest_level and loaded.highest_level == 2,
			"records survive a restart (saved file reloaded: %s)" % loaded.best_run)
	loaded.free()
	var config := ConfigFile.new()
	config.set_value("best_run", "level", "bogus")
	config.save("user://progression_bogus.cfg")
	var bad := ProgressionStore.new()
	bad.save_path = "user://progression_bogus.cfg"
	bad.load_progress()
	_check(bad.best_run.is_empty() and bad.highest_level == 1, "a corrupt record is ignored")
	bad.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progression_bogus.cfg"))


# --- Scene flow ---------------------------------------------------------------

func _test_flow_and_timer() -> void:
	_prog.clear_progress()
	_prog.select(HARD if _prog.is_unlocked(HARD) else NORMAL)
	await _load_scene(SCENE)
	_check(_run.dungeon_level == 1 and not _run.is_replay and _prog.best_run["level"] == 1, "a fresh run starts at level 1 and records it")
	var hud := _dungeon.get_node(^"RunHud") as RunHud
	_check(RunHud.status_text(_run).contains("Level 1 - The Dungeon") and RunHud.status_text(_run).contains("Difficulty: Normal"),
			"the HUD shows the level, biome and difficulty")
	hud.hide()
	await _frames(30)
	_check(_run.run_time > 0.3 and is_equal_approx(_run.run_time, _run.level_time), "the run timer counts play time (%.2f)" % _run.run_time)
	# Build: an item, an upgrade and enough XP for the boss.
	_run.collect_item(&"swift_boots")
	_run.add_rewards(0, 100)
	_run.purchase(&"vitality")
	await _win_fast()
	var time_at_boss := _run.run_time
	await _frames(20)
	_check(is_equal_approx(_run.run_time, time_at_boss), "the timer stops while the boss reward is shown")
	var visited_boss := _dungeon.is_visited(_dungeon.index_at(BOSS))
	var kills := _run.enemies_defeated
	_check(_overlay().choose_relic(&"ember_relic") and _run.dungeon_level == 2 and not paused, "relic choice starts level 2")
	_check(visited_boss and not _dungeon.is_visited(_dungeon.index_at(BOSS)) and _run.level_time < 0.5
			and is_equal_approx(_run.run_time, time_at_boss), "level state and level timer reset; the run timer is kept")
	_check(_run.collected.has(&"swift_boots") and _run.purchased.has(&"vitality") and _run.relics == [&"ember_relic"]
			and _run.level == MageLevels.cap(1) and _run.enemies_defeated == kills, "build is kept across levels")
	await _frames(20)
	_check(_run.run_time > time_at_boss + 0.2, "the run timer continues in the new level (%.2f -> %.2f)" % [time_at_boss, _run.run_time])
	_check(_prog.best_run["level"] == 2 and _prog.highest_level == 2, "reaching level 2 was saved immediately")
	_check(RunHud.status_text(_run).contains("Level 2 - The Dungeon"), "the HUD follows the level")


func _test_biome_transition_and_scaling() -> void:
	# Level 2 enemies: difficulty x level scaling, original enemy pool.
	var goblin := await _first_goblin_room_enemy()
	var base := _base_health(goblin.scene_file_path)
	_check(goblin.scene_file_path.ends_with("giant_goblin.tscn") and is_equal_approx(goblin.get_node(^"Health").max_health,
			base * _run.enemy_health_multiplier()), "level 2 enemy HP is scaled (%.0f x %.2f)" % [base, _run.enemy_health_multiplier()])
	_check(_run.enemy_health_multiplier() > Difficulty.data(_run.difficulty)["enemy_health"], "level scaling stacks on the difficulty")
	_check(_dungeon.current_room.get_node(^"Visuals").theme == _room_theme(_dungeon.current_room), "level 2 keeps the scene's own theme")
	# Play up to the biome change.
	while _run.dungeon_level < Biomes.default_levels + 1:
		await _win_fast()
		_check(_overlay().choose_relic(&"wind_relic"), "setup: relic chosen on level %d" % (_run.dungeon_level - 1))
	_check(Biomes.biome_id(_run.dungeon_level) == &"caverns" and _run.relics.size() == Biomes.default_levels, "level %d starts the second biome" % _run.dungeon_level)
	var replaced := await _first_goblin_room_enemy()
	_check(not replaced.scene_file_path.ends_with("giant_goblin.tscn"), "the biome's enemy pool replaces goblins (%s)" % replaced.scene_file_path)
	_check(_dungeon.current_room.get_node(^"Visuals").theme == Biomes.theme_for(_run.dungeon_level), "the biome theme is applied to rooms")
	_check(RunHud.status_text(_run).contains("Cavern Depths"), "the HUD shows the biome")


func _test_game_over_record() -> void:
	var level := _run.dungeon_level
	var best_before: int = _prog.best_run["level"]
	_check(best_before == level, "setup: the record is at the current level (%d)" % level)
	await _frames(10)
	_mage.invulnerable = false
	_mage.take_damage(99999.0)
	await _frames(3)
	_check(_prog.best_run["level"] == level and _prog.best_run["time"] >= _run.run_time - 0.1 and _prog.best_run["biome"] == &"caverns",
			"Game Over saves the final duration (%s)" % _prog.best_run)
	_check((_dungeon.get_node(^"GameOverOverlay") as GameOverOverlay).run_info_text().contains("Reached Level %d" % level),
			"Game Over shows the level reached")
	_check(((_dungeon.get_node(^"GameOverOverlay") as Node).get_node(^"%MainMenuButton") as Button) != null, "Game Over offers a Main Menu button")


func _test_level_select_and_replay() -> void:
	var highest := _prog.highest_level
	_check(highest >= 4 and not _prog.select(NORMAL, &"", highest + 1) and not _prog.select(NORMAL, &"", 0),
			"levels above the highest reached (or below 1) cannot be selected")
	_check(_prog.select(NORMAL, &"", 3) and _prog.selected_start_level == 3, "a reached level can be selected")
	var best_before := _prog.best_run.duplicate()
	var completions := _prog.completion_count(NORMAL)
	await _load_scene(SCENE)
	_check(_run.dungeon_level == 3 and _run.is_replay and RunHud.status_text(_run).contains("practice"), "a replay run starts at the chosen level and is marked")
	_check(_run.level == MageLevels.arrival_level(3) and _run.collected.is_empty() and _run.relics.is_empty() and _run.purchased.is_empty() and _run.currency == 0, "a replay run starts at the arrival Mage level with no items, relics or gold")
	await _win_fast()
	_check(_overlay().choose_relic(&"wind_relic") and _run.dungeon_level == 4, "a replay run still progresses")
	_check(_prog.best_run == best_before and _prog.highest_level == highest and _prog.completion_count(NORMAL) == completions
			and _dungeon.unlocked_tier == -1, "replay runs change no record, level unlock or difficulty unlock")
	# A normal run afterwards is unaffected by the replay selection.
	_prog.select(NORMAL)
	await _load_scene(SCENE)
	_check(_run.dungeon_level == 1 and not _run.is_replay, "starting normally goes back to a fresh level 1 run")


func _test_menu() -> void:
	await _load_scene(MENU)
	var menu := current_scene as MainMenu
	_check(menu != null and (menu.get_node(^"%BestRunLabel") as Label).text.contains("Best Run: Level %d" % _prog.best_run["level"]),
			"the main menu shows the best run")
	_check(menu.selected_start_level == 1 and not menu.select_start_level(_prog.highest_level + 1) and not menu.select_start_level(0),
			"the menu rejects start levels above the highest reached")
	_check(menu.select_start_level(2) and menu.select_start_level(1, true) and menu.selected_start_level == 3 and menu.select_start_level(-2, true) and not menu.select_start_level(-1, true) and menu.selected_start_level == 1,
			"the menu steps through reached levels")
	menu.select_start_level(_prog.highest_level)
	_check((menu.get_node(^"%StartLevelLabel") as Label).text.contains("practice run") and (menu.get_node(^"%NextLevelButton") as Button).disabled,
			"the menu marks level-select runs as practice")
	menu.select_start_level(1)
	_check((menu.get_node(^"%StartLevelLabel") as Label).text.contains("new endless run"), "level 1 is labelled as the endless run")


# --- Helpers ------------------------------------------------------------------

func _load_scene(path: String) -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	if current_scene and path == SCENE and current_scene is Dungeon:
		paused = false
	change_scene_to_file(path)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	if current_scene is Dungeon:
		_dungeon = current_scene as Dungeon
		_mage = _dungeon.mage
		_run = _dungeon.run_state


## Levels the Mage up, kills the boss and waits for the reward screen.
func _win_fast() -> void:
	while _run.level < _run.max_level():
		_run.add_rewards(_run.xp_to_next_level(), 0)
	_dungeon.enter_room(_dungeon.index_at(BOSS), &"DoorBottom")
	await _frames(2)
	for e in _dungeon.current_room.get_node(^"Enemies").get_children():
		if e is Boss:
			(e as Boss).take_damage(99999.0)
	await _wait_until(func() -> bool: return _overlay().is_open, 240)


func _first_goblin_room_enemy() -> Enemy:
	_dungeon.enter_room(_dungeon.index_at(GOBLIN_ROOM), &"DoorBottom")
	await _frames(2)
	return _dungeon.current_room.get_node(^"Enemies").get_child(0) as Enemy


func _base_health(scene_path: String) -> float:
	var e := (load(scene_path) as PackedScene).instantiate()
	var hp: float = (e.get_node(^"Health") as Health).max_health
	e.free()
	return hp


## The unmapped theme of a room's scene.
func _room_theme(room: Room) -> RoomTheme:
	var fresh := (load(room.scene_file_path) as PackedScene).instantiate()
	var theme: RoomTheme = (fresh.get_node(^"Visuals") as RoomVisuals).theme
	fresh.free()
	return theme


func _overlay() -> VictoryOverlay:
	return current_scene.get_node_or_null(^"VictoryOverlay") as VictoryOverlay


func _wait_until(condition: Callable, max_frames: int = 240) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
