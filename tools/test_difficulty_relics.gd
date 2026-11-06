extends SceneTree
## Headless check of difficulty tiers, persistent unlocks, Pact relics and
## relic synergies (scripts/progression/, RunState, Dungeon): unlock order and
## save/load (test-only save path), the pre-run menu, enemy scaling (melee,
## ranged, elite, boss, treasure-room and survival-wave enemies, exactly once),
## extra enemies at safe spawn points, gold, every Pact effect, the three
## synergies, Restart/death resets and the victory / game-over summaries.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_difficulty_relics.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"
const BOSS := Vector2i(2, 0)
const SURVIVAL := Vector2i(5, 2)
const NORMAL := Difficulty.Tier.NORMAL
const HARD := Difficulty.Tier.HARD
const ABYSSAL := Difficulty.Tier.ABYSSAL

var _failures := 0
var _prog: ProgressionStore
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState
var _base_hp := 0.0
var _base_damage := 0.0
var _base_cooldown := 0.0
var _real_save_time := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_prog = ProgressionStore.instance(self)
	_real_save_time = FileAccess.get_modified_time(ProgressionStore.SAVE_PATH) if FileAccess.file_exists(ProgressionStore.SAVE_PATH) else 0
	_check(_prog.save_path == ProgressionStore.TEST_SAVE_PATH, "headless progression uses the test save path (%s)" % _prog.save_path)
	_test_unlocks_and_save()
	await _test_menu()
	await _start_run(NORMAL)
	_base_hp = _mage.health.max_health
	_base_damage = _mage.caster.get_cast_spell().damage
	_base_cooldown = _mage.caster.get_cast_spell().cooldown
	await _test_normal_baseline()
	await _test_hard_scaling()
	await _test_abyssal_pressure()
	await _test_restart_and_death()
	await _test_pacts()
	await _test_synergies()
	await _test_victory_summaries()
	var real_time := FileAccess.get_modified_time(ProgressionStore.SAVE_PATH) if FileAccess.file_exists(ProgressionStore.SAVE_PATH) else 0
	_check(real_time == _real_save_time, "the player's real progression file was not touched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProgressionStore.TEST_SAVE_PATH))
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Progression -------------------------------------------------------------

func _test_unlocks_and_save() -> void:
	_prog.clear_progress()
	_check(_prog.is_unlocked(NORMAL) and not _prog.is_unlocked(HARD) and not _prog.is_unlocked(ABYSSAL),
			"fresh progression: only Normal unlocked")
	_check(not _prog.select(HARD) and not _prog.select(NORMAL, &"bogus") and _prog.selected_difficulty == NORMAL,
			"locked tiers and unknown Pacts cannot be selected")
	_check(_prog.record_victory(NORMAL) == HARD and _prog.is_unlocked(HARD) and not _prog.is_unlocked(ABYSSAL),
			"Normal victory unlocks Hard only")
	_check(_prog.record_victory(NORMAL) == -1 and _prog.completion_count(NORMAL) == 2, "replaying Normal unlocks nothing new")
	_check(_prog.select(HARD, &"avarice") and _prog.selected_difficulty == HARD and _prog.selected_pact == &"avarice",
			"Hard is selectable once unlocked")
	_check(_prog.record_victory(HARD) == ABYSSAL and _prog.is_unlocked(ABYSSAL), "Hard victory unlocks Abyssal")
	_check(_prog.record_victory(ABYSSAL) == -1, "Abyssal victory unlocks nothing further")
	_check(FileAccess.file_exists(ProgressionStore.TEST_SAVE_PATH), "victory saved to the test save file")
	_prog.completions.clear()
	_check(not _prog.is_unlocked(HARD), "setup: in-memory progress cleared")
	_prog.load_progress()
	_check(_prog.is_unlocked(HARD) and _prog.is_unlocked(ABYSSAL) and _prog.completion_count(NORMAL) == 2
			and _prog.completion_count(HARD) == 1, "unlocks load back from the save file")
	_prog.clear_progress()


func _test_menu() -> void:
	_prog.clear_progress()
	change_scene_to_file(MENU)
	await _wait_for_scene(0, false)
	var menu := current_scene as MainMenu
	(menu.get_node(^"%StartButton") as Button).pressed.emit()
	_check((menu.get_node(^"%RunSetup") as Control).visible and not (menu.get_node(^"%Center") as Control).visible,
			"Start Run opens the run setup panel")
	_check(menu.difficulty_button(NORMAL) and not menu.difficulty_button(NORMAL).disabled
			and menu.difficulty_button(HARD).disabled and menu.difficulty_button(ABYSSAL).disabled
			and menu.difficulty_button(HARD).text.contains("locked"), "locked tiers are shown disabled")
	var info := (menu.get_node(^"%DifficultyInfo") as Label).text
	_check(info.contains("Hard locked. Unlock: complete a Normal run") and info.contains("Abyssal locked. Unlock: complete a Hard run"),
			"unlock requirements are shown:\n%s" % info)
	_check(not menu.select_difficulty(HARD) and menu.selected_difficulty == NORMAL, "a locked tier cannot be selected in the menu")
	_check(menu.get_node(^"%PactButtons").get_child_count() == Pacts.PACTS.size() + 1, "None + every Pact offered")
	menu.pact_button(&"glass_heart").pressed.emit()
	var pact_info := (menu.get_node(^"%PactInfo") as Label).text
	_check(menu.selected_pact == &"glass_heart" and pact_info.contains("Benefit: +30% Fire Ball damage")
			and pact_info.contains("Drawback: -25% max HP") and pact_info.contains("Glass Cannon"),
			"Pact benefit, drawback and synergy are shown:\n%s" % pact_info)
	(menu.get_node(^"%BackButton") as Button).pressed.emit()
	_check(not (menu.get_node(^"%RunSetup") as Control).visible, "Back closes the setup panel")

	_prog.record_victory(NORMAL)
	var old_id := current_scene.get_instance_id()
	change_scene_to_file(MENU)
	await _wait_for_scene(old_id, false)
	menu = current_scene as MainMenu
	menu.open_setup()
	_check(not menu.difficulty_button(HARD).disabled and menu.difficulty_button(ABYSSAL).disabled, "Hard enabled after a Normal victory")
	menu.difficulty_button(HARD).pressed.emit()
	menu.pact_button(&"avarice").pressed.emit()
	info = (menu.get_node(^"%DifficultyInfo") as Label).text
	_check(info.contains("+35% HP") and info.contains("+25% damage") and info.contains("+10% speed")
			and info.contains("+1 in Lv 2 rooms") and info.contains("+25% gold"), "Hard effects and reward bonus shown:\n%s" % info)
	old_id = current_scene.get_instance_id()
	(menu.get_node(^"%BeginButton") as Button).pressed.emit()
	await _wait_for_scene(old_id)
	_check(_run != null and _run.difficulty == HARD and _run.pact == &"avarice", "Begin Run passes difficulty and Pact into the run")
	_prog.clear_progress()


# --- Scaling -----------------------------------------------------------------

func _test_normal_baseline() -> void:
	var index := _first_combat_room(1)
	var room := await _enter(index)
	var spec := _dungeon.rooms[index]
	_check(_enemies(room).size() == spec.enemies.size(), "Normal: no extra enemies")
	var enemy := _enemies(room)[0] as Enemy
	var base := _base_stats(spec.enemies[0])
	_check(enemy.scaled and is_equal_approx(enemy.health.max_health, base["hp"]) and is_equal_approx(enemy.contact_damage, base["damage"] * RunState.ENEMY_DAMAGE_FACTOR),
			"Normal: enemies keep baseline stats")
	var gold := _run.currency
	var xp := _run.xp
	room.start_encounter()
	var reward := enemy.currency_reward
	var xp_reward := enemy.xp_reward
	enemy.take_damage(99999.0)
	await _frames(1)
	_check(_run.currency == gold + reward and _run.xp == xp + xp_reward, "Normal: standard gold and XP (raw XP override)")
	_check(_mage.health.max_health == _base_hp and is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage),
			"difficulty never scales the player")


func _test_hard_scaling() -> void:
	await _start_run(HARD)
	_check(is_equal_approx(_mage.health.max_health, _base_hp) and is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage),
			"Hard: player stats unscaled")
	# Melee, Lv 1 room (no extra enemies on Hard).
	var lv1 := _first_combat_room(1)
	var room := await _enter(lv1)
	var spec := _dungeon.rooms[lv1]
	_check(_enemies(room).size() == spec.enemies.size(), "Hard: no extra enemies in Lv 1 rooms")
	var enemy := _enemies(room)[0] as Enemy
	var base := _base_stats(spec.enemies[0])
	_check(is_equal_approx(enemy.health.max_health, base["hp"] * 1.35) and is_equal_approx(enemy.health.current, base["hp"] * 1.35)
			and is_equal_approx(enemy.contact_damage, base["damage"] * 1.25 * RunState.ENEMY_DAMAGE_FACTOR) and is_equal_approx(enemy.speed, base["speed"] * 1.1)
			and is_equal_approx(enemy.attack_cooldown, base["cooldown"] / 1.1), "Hard melee: HP x1.35, damage x1.25, pace x1.1")
	_check(not enemy.apply_scaling(2.0, 2.0, 2.0) and is_equal_approx(enemy.health.max_health, base["hp"] * 1.35),
			"scaling applies exactly once per enemy")
	room.start_encounter()
	var gold := _run.currency
	var xp := _run.xp
	var reward := enemy.currency_reward
	var xp_reward := enemy.xp_reward
	enemy.take_damage(99999.0)
	await _frames(1)
	_check(_run.currency == gold + roundi(reward * 1.25) and _run.xp == xp + xp_reward,
			"Hard: gold x1.25, XP unscaled (%d -> %d)" % [gold, _run.currency])
	_kill_all(room)
	await _frames(2)
	# Leaving and re-entering a cached room never rescales.
	var lv2 := _first_combat_room(2)
	room = await _enter(lv2)
	spec = _dungeon.rooms[lv2]
	_check(_enemies(room).size() == spec.enemies.size() + 1, "Hard: +1 enemy in Lv 2 rooms (%d)" % _enemies(room).size())
	var hp_before := (_enemies(room)[0] as Enemy).health.max_health
	await _enter(lv1)
	room = await _enter(lv2)
	_check(is_equal_approx((_enemies(room)[0] as Enemy).health.max_health, hp_before), "re-entering a room does not rescale its enemies")
	# Ranged.
	var ranged: RangedEnemy = await _find_ranged()
	_check(ranged != null, "setup: found a ranged enemy")
	if ranged:
		var rbase := _base_stats(load(ranged.scene_file_path))
		var shot := ranged.fire(_mage.global_position)
		_check(is_equal_approx(ranged.projectile_damage, rbase["projectile"] * 1.25 * RunState.ENEMY_DAMAGE_FACTOR) and shot != null
				and is_equal_approx(shot.spell.damage, rbase["projectile"] * 1.25 * RunState.ENEMY_DAMAGE_FACTOR), "Hard ranged: projectile damage x1.25 (fired bolt too)")
		if shot:
			shot.queue_free()
	# Boss.
	var boss := await _boss_room()
	var bbase := _base_stats(load(boss.scene_file_path))
	_check(boss.elite and boss.scaled and is_equal_approx(boss.health.max_health, bbase["hp"] * 1.35)
			and is_equal_approx(boss.slam_damage, bbase["slam"] * 1.25 * RunState.ENEMY_DAMAGE_FACTOR) and is_equal_approx(boss.volley_damage, bbase["volley"] * 1.25 * RunState.ENEMY_DAMAGE_FACTOR)
			and is_equal_approx(boss.contact_damage, bbase["damage"] * 1.25 * RunState.ENEMY_DAMAGE_FACTOR), "Hard boss: HP, slam, volley and contact damage scaled")
	boss.begin_attack(&"volley")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
	var bolts := _hostile_shots()
	_check(not bolts.is_empty() and bolts.all(func(p: Projectile) -> bool: return is_equal_approx(p.spell.damage, bbase["volley"] * 1.25 * RunState.ENEMY_DAMAGE_FACTOR)),
			"Hard boss bolts carry the scaled damage")
	for b in bolts:
		b.queue_free()


func _test_abyssal_pressure() -> void:
	await _start_run(ABYSSAL)
	var lv1 := _first_combat_room(1)
	var room := await _enter(lv1)
	_check(_enemies(room).size() == _dungeon.rooms[lv1].enemies.size() + 1, "Abyssal: +1 enemy in Lv 1 rooms")
	var lv2 := _first_combat_room(2)
	room = await _enter(lv2)
	var spec := _dungeon.rooms[lv2]
	var expected := mini(spec.enemies.size() + 2, room.get_node(^"SpawnPoints").get_child_count())
	_check(_enemies(room).size() == expected, "Abyssal: +2 enemies in Lv 2 rooms (%d)" % _enemies(room).size())
	var base := _base_stats(spec.enemies[0])
	_check(is_equal_approx((_enemies(room)[0] as Enemy).health.max_health, base["hp"] * 1.75), "Abyssal: enemy HP x1.75")
	var positions := _enemies(room).map(func(e: Enemy) -> Vector2: return e.position)
	var unique := {}
	for p: Vector2 in positions:
		unique[p] = true
	_check(unique.size() == positions.size(), "extra enemies never share a spawn point")
	var doors := room.get_doors()
	var extras := _enemies(room).slice(spec.enemies.size())
	_check(extras.all(func(e: Enemy) -> bool: return doors.all(func(d: Door) -> bool: return e.position.distance_to(d.position) >= 180.0)),
			"extra enemies spawn away from the doors")
	# Fallback: a room with no free spawn points gets no extra enemies.
	var template := spec.scene.instantiate() as Room
	var points := template.get_node(^"SpawnPoints").get_child_count()
	_check(template.add_extra_enemies(spec.enemies, 3, points) == 0, "no free safe spawn points: no extra enemies (no overlap)")
	template.free()
	# Survival waves.
	var trial := await _enter(_dungeon.index_at(SURVIVAL)) as SurvivalRoom
	_check(trial.extra_per_wave == 2 and is_equal_approx(trial.duration, 120.0), "Abyssal survival: +2 per wave, timer unchanged")
	trial.begin_challenge()
	_check(_enemies(trial).size() == trial.wave_sizes[0] + 2, "Abyssal survival: wave 1 has %d+2 enemies" % trial.wave_sizes[0])
	var first := _enemies(trial)[0] as Enemy
	var wbase := _base_stats(trial.wave_enemies[0])
	_check(first.scaled and is_equal_approx(first.health.max_health, wbase["hp"] * 1.75), "survival-wave enemies are scaled")
	for w in trial.wave_count():
		_kill_all(trial)
		await _frames(2)
	_check(trial.waves_spawned == trial.wave_count(), "all survival waves spawn with the extra enemies")


func _test_restart_and_death() -> void:
	_unlock_all()
	_prog.select(HARD, &"avarice")
	await _restart()
	_run.add_rewards(_run.xp_to_next_level(), 300)
	_check(_run.collect_item(&"ember_shard"), "setup: progress in the run")
	var index := _first_combat_room(1)
	await _enter(index)
	var unlocks := _prog.completions.duplicate()
	await _restart()
	_check(_run.difficulty == HARD and _run.pact == &"avarice", "Restart keeps the selected difficulty and Pact")
	_check(_run.level == 1 and _run.currency == 0 and _run.gold_earned == 0 and _run.collected.is_empty()
			and _run.active_synergies().is_empty() and not _dungeon.is_visited(index) and not _dungeon.victory,
			"Restart resets level, gold, items, synergies and rooms")
	_check(is_equal_approx(_mage.health.current, _base_hp) and is_equal_approx(_mage.health.max_health, _base_hp), "Restart resets HP")
	_check(_prog.completions == unlocks, "Restart keeps permanent unlocks")
	# Death never unlocks anything.
	_prog.completions = {NORMAL: 1}
	_mage.take_damage(9999.0)
	await _frames(2)
	var overlay := current_scene.get_node(^"GameOverOverlay") as GameOverOverlay
	var info := (overlay.get_node(^"%RunInfo") as Label).text
	_check(overlay.visible and info.contains("Difficulty: Hard") and info.contains("Pact: Avarice"), "Game Over shows difficulty and Pact:\n%s" % info)
	_check(not _prog.is_unlocked(ABYSSAL) and _prog.completion_count(HARD) == 0, "death does not unlock the next tier")
	var old_id := current_scene.get_instance_id()
	(overlay.get_node(^"%MainMenuButton") as Button).pressed.emit()
	await _wait_for_scene(old_id, false)
	_check(current_scene is MainMenu, "Game Over -> Main Menu")


# --- Pacts -------------------------------------------------------------------

func _test_pacts() -> void:
	# Glass Heart.
	await _start_run(NORMAL, &"glass_heart")
	_check(is_equal_approx(_mage.health.max_health, _base_hp * 0.75) and is_equal_approx(_mage.health.current, _base_hp * 0.75),
			"Glass Heart: -25% max HP")
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage * 1.3), "Glass Heart: +30% damage")
	_run.add_rewards(_run.xp_to_next_level(), 0)
	_check(is_equal_approx(_mage.health.max_health, _base_hp * 0.75 + 15.0), "Glass Heart: max HP gains also -25%")
	_run.changed.emit()
	_run.changed.emit()
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage * 1.35), "Pact bonus does not stack on recalculation")
	_check(not _run.configure(NORMAL, &"avarice") and _run.pact == &"glass_heart", "a run's Pact cannot be changed or added twice")

	# Swift Casting.
	await _start_run(NORMAL, &"swift_casting")
	_check(is_equal_approx(_mage.caster.get_cast_spell().cooldown, _base_cooldown * 0.7)
			and is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage * 0.8), "Swift Casting: -30% cooldown, -20% damage")

	# Avarice.
	await _start_run(NORMAL, &"avarice")
	var index := _first_combat_room(1)
	var room := await _enter(index)
	var enemy := _enemies(room)[0] as Enemy
	var base := _base_stats(_dungeon.rooms[index].enemies[0])
	_check(is_equal_approx(enemy.health.max_health, base["hp"] * 1.2), "Avarice: enemies +20% HP")
	room.start_encounter()
	var reward := enemy.currency_reward
	var xp_reward := enemy.xp_reward
	enemy.take_damage(99999.0)
	await _frames(1)
	_check(_run.currency == roundi(reward * 1.4), "Avarice: +40% enemy gold")
	var gold := _run.currency
	_run.claim_treasure(&"survivor_cache")
	_check(_run.currency == gold + 210, "Avarice: +40% treasure gold (150 -> 210)")

	# Blood Pact: every healing source halved, kills heal 4.
	await _start_run(NORMAL, &"blood_pact")
	_mage.take_damage(60.0)
	var hp := _mage.health.current
	_run.add_rewards(_run.xp_to_next_level(), 0)
	_check(is_equal_approx(_mage.health.current, hp + 10.0), "Blood Pact: level-up heal halved (20 -> 10)")
	hp = _mage.health.current
	_run.claim_treasure(&"survivor_cache")
	_check(is_equal_approx(_mage.health.current, hp + 25.0), "Blood Pact: treasure heal halved (50 -> 25)")
	_mage.take_damage(40.0)
	hp = _mage.health.current
	_run.collect_item(&"heart_crystal")
	_check(is_equal_approx(_mage.health.current, hp + 12.5), "Blood Pact: item heal halved (25 -> 12.5)")
	_run.add_rewards(0, 100)
	hp = _mage.health.current
	_run.purchase(&"vitality")
	_check(is_equal_approx(_mage.health.current, hp + 10.0), "Blood Pact: upgrade heal halved (20 -> 10)")
	_check(is_equal_approx(_dungeon.heal_mage(10.0), 5.0), "Blood Pact: shared heal API halves direct heals")
	room = await _enter(_first_combat_room(1))
	room.start_encounter()
	hp = _mage.health.current
	(_enemies(room)[0] as Enemy).take_damage(99999.0)
	await _frames(1)
	_check(is_equal_approx(_mage.health.current, hp + 4.0), "Blood Pact: +4 HP per enemy defeated")

	# Hunter's Mark: elites and boss only.
	await _start_run(NORMAL, &"hunters_mark")
	var pair := await _elite_and_normal()
	if pair.size() == 2:
		var elite := pair[0] as Enemy
		var normal := pair[1] as Enemy
		var ebase := _base_stats(load(elite.scene_file_path))
		var nbase := _base_stats(load(normal.scene_file_path))
		_check(is_equal_approx(elite.damage_taken_multiplier, 1.4) and is_equal_approx(elite.contact_damage, ebase["damage"] * 1.3 * RunState.ENEMY_DAMAGE_FACTOR),
				"Hunter's Mark: elites take +40% and deal +30% damage")
		_check(is_equal_approx(normal.damage_taken_multiplier, 1.0) and is_equal_approx(normal.contact_damage, nbase["damage"] * RunState.ENEMY_DAMAGE_FACTOR),
				"Hunter's Mark: ordinary enemies unaffected")
		var before := elite.health.current
		elite.take_damage(10.0)
		_check(is_equal_approx(before - elite.health.current, 14.0), "Hunter's Mark: a 10-damage hit deals 14 to an elite")
	else:
		_check(false, "setup: found an elite and an ordinary enemy")
	var boss := await _boss_room()
	_check(is_equal_approx(boss.damage_taken_multiplier, 1.4) and is_equal_approx(boss.slam_damage, _base_stats(load(boss.scene_file_path))["slam"] * 1.3 * RunState.ENEMY_DAMAGE_FACTOR),
			"Hunter's Mark: affects the boss")

	# Treasure Seeker: treasure rooms and rewards only.
	await _start_run(NORMAL, &"treasure_seeker")
	index = _first_combat_room(1)
	room = await _enter(index)
	base = _base_stats(_dungeon.rooms[index].enemies[0])
	_check(is_equal_approx((_enemies(room)[0] as Enemy).health.max_health, base["hp"]), "Treasure Seeker: normal rooms unaffected")
	var trial := await _enter(_dungeon.index_at(SURVIVAL)) as SurvivalRoom
	_check(is_equal_approx(trial.duration, 120.0), "Treasure Seeker: survival timer unchanged (display only)")
	trial.begin_challenge()
	var first := _enemies(trial)[0] as Enemy
	var wbase := _base_stats(trial.wave_enemies[0])
	_check(is_equal_approx(first.health.max_health, wbase["hp"] * 1.3) and is_equal_approx(first.contact_damage, wbase["damage"] * 1.3 * RunState.ENEMY_DAMAGE_FACTOR),
			"Treasure Seeker: treasure-room enemies +30% HP and damage")
	_mage.take_damage(90.0)
	hp = _mage.health.current
	gold = _run.currency
	_run.claim_treasure(&"survivor_cache")
	_check(_run.currency == gold + 263 and is_equal_approx(_mage.health.current, hp + 87.5), "Treasure Seeker: chest gold and heal x1.75")
	await _restart()
	_check(is_equal_approx((await _enter(_dungeon.index_at(SURVIVAL)) as SurvivalRoom).duration, 120.0), "survival timer still unchanged after Restart")


# --- Synergies ---------------------------------------------------------------

func _test_synergies() -> void:
	# Glass Cannon.
	await _start_run(NORMAL, &"glass_heart")
	_check(_run.active_synergies().is_empty(), "a Pact alone activates no synergy")
	var activations := []
	_run.synergy_activated.connect(func(id: StringName) -> void: activations.append(id))
	_run.collect_item(&"ember_shard")
	_check(_run.is_synergy_active(&"glass_cannon") and activations == [&"glass_cannon"], "Glass Cannon: Glass Heart + Ember Shard")
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage * (1.0 + 0.3 + 0.15 + 0.25))
			and is_equal_approx(_mage.damage_taken_multiplier, 1.2), "Glass Cannon: +25% damage and +20% damage taken")
	var hp := _mage.health.current
	_mage.take_damage(10.0)
	_check(is_equal_approx(hp - _mage.health.current, 12.0), "Glass Cannon: a 10-damage hit deals 12")
	_run.changed.emit()
	_run.collect_item(&"swift_boots")
	_check(activations.size() == 1 and is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage * 1.7),
			"Glass Cannon applies exactly once")
	_check(RunHud.status_text(_run).contains("Glass Cannon"), "HUD status shows the active synergy")

	# Arcane Momentum.
	await _start_run(NORMAL, &"swift_casting")
	_check(is_equal_approx(_mage.caster.momentum, 0.0), "no momentum without the synergy")
	_run.collect_item(&"swift_boots")
	_check(_run.is_synergy_active(&"arcane_momentum") and is_equal_approx(_mage.caster.momentum, 0.5), "Arcane Momentum: Swift Casting + Swift Boots")
	var target := (await _enter(_first_combat_room(1))).get_node(^"Enemies").get_child(0) as Enemy
	var caster := _mage.caster
	var shot := caster.try_cast(_mage.global_position + Vector2(200, 0))
	_check(shot != null, "setup: Fire Ball cast")
	if shot:
		shot.hit.emit(target)
		shot.queue_free()  # only the simulated hit counts
		_check(caster.has_momentum(), "a Fire Ball hit on an enemy grants a momentum charge")
		await _wait_until(caster.can_cast)
		caster.try_cast(_mage.global_position + Vector2(200, 0)).queue_free()
		var cd := caster.get_cast_spell().cooldown
		_check(is_equal_approx(caster.cooldown_left(), cd * 0.5) and not caster.has_momentum(), "Arcane Momentum: next cooldown -50%, charge used")
		await _wait_until(caster.can_cast)
		caster.try_cast(_mage.global_position + Vector2(200, 0)).queue_free()
		_check(is_equal_approx(caster.cooldown_left(), cd), "without a new hit the cooldown is normal")

	# Greed's Reward.
	await _start_run(NORMAL, &"avarice")
	_check(_run.upgrade_cost(&"vitality") == 100, "no anvil surcharge without the synergy")
	_run.claim_treasure(&"survivor_cache")
	_check(_run.is_synergy_active(&"greeds_reward"), "Greed's Reward: Avarice + Survivor's Cache")
	_check(_run.currency == 210 and is_equal_approx(_run.gold_damage_bonus(), 0.1)
			and is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage * 1.1), "Greed's Reward: +1% damage per 20 gold (210 gold -> +10%)")
	_run.add_rewards(0, 5000)
	_check(is_equal_approx(_run.gold_damage_bonus(), 0.3), "Greed's Reward bonus capped at +30%")
	_check(_run.upgrade_cost(&"vitality") == 125, "Greed's Reward: anvil prices +25%")
	var gold := _run.currency
	_run.purchase(&"vitality")
	_check(_run.currency == gold - 125, "the anvil charges the raised price")

	# Synergies reset between runs.
	await _restart()
	_check(_run.active_synergies().is_empty() and _run.upgrade_cost(&"vitality") == 100 and is_equal_approx(_mage.caster.momentum, 0.0),
			"Restart clears synergies")


# --- Victory -----------------------------------------------------------------

func _test_victory_summaries() -> void:
	_prog.clear_progress()
	_prog.select(NORMAL, &"glass_heart")
	await _restart()
	await _win_fast()
	var overlay := current_scene.get_node(^"VictoryOverlay") as VictoryOverlay
	var ember := overlay.get_node(^"%RelicChoices").get_node(^"ember_relic") as Button
	_check(ember.text.contains("completes synergy: Glass Cannon"), "relic choice names the synergy it completes (%s)" % ember.text)
	_check(_prog.is_unlocked(HARD) and _dungeon.unlocked_tier == HARD, "Normal victory unlocks Hard")
	ember.pressed.emit()
	_check(_run.relic == &"ember_relic" and _run.is_synergy_active(&"glass_cannon"), "post-boss Ember Relic completes Glass Cannon")
	var first := _dungeon.run_summary()
	_check(first["difficulty"] == NORMAL and first["pact"] == &"glass_heart" and first["synergies"] == [&"glass_cannon"]
			and first["gold_earned"] == 150 and first["unlocked_tier"] == HARD and first["relic"] == &"ember_relic",
			"run summary shows difficulty, Pact, gold, synergy and unlock (%s)" % first)

	_prog.select(HARD)
	await _restart()
	await _win_fast()
	var summary := _dungeon.run_summary()
	_check(_prog.is_unlocked(ABYSSAL) and summary["unlocked_tier"] == ABYSSAL and summary["difficulty"] == HARD,
			"Hard victory unlocks Abyssal")
	_check(summary["gold_earned"] == roundi(150 * 1.25) and summary["difficulty_bonus_gold"] == roundi(150 * 0.25),
			"boss gold x1.25 with the difficulty bonus tracked (%s)" % summary)
	overlay = current_scene.get_node(^"VictoryOverlay") as VictoryOverlay
	overlay.choose_relic(&"wind_relic")
	_check(_dungeon.run_summary()["difficulty"] == HARD and _dungeon.run_summary()["difficulty_bonus_gold"] == 38,
			"Hard summary shows the reward bonus (%s)" % _dungeon.run_summary())

	_prog.select(HARD)
	await _restart()
	await _win_fast()
	_check(_dungeon.unlocked_tier == -1 and _prog.completion_count(HARD) == 2, "replaying a completed tier unlocks nothing new")
	await _restart()
	_check(not paused, "Restart after victory unpauses")
	_prog.clear_progress()


# --- Helpers -----------------------------------------------------------------

func _unlock_all() -> void:
	_prog.completions = {NORMAL: 1, HARD: 1}


## Starts a fresh run on `tier` with `pact` (everything unlocked for the test).
func _start_run(tier: int, pact: StringName = &"") -> void:
	_unlock_all()
	_check(_prog.select(tier, pact), "setup: selected %s / %s" % [Difficulty.display_name(tier), pact])
	await _restart()


func _restart() -> void:
	paused = false
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_for_scene(old_id)


func _enter(index: int) -> Room:
	_dungeon.enter_room(index)
	await _frames(1)
	return _dungeon.current_room


func _first_combat_room(level: int) -> int:
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if not spec.enemies.is_empty() and not spec.is_boss and not spec.is_treasure() and spec.required_level == level:
			return i
	return -1


func _find_ranged() -> RangedEnemy:
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if spec.is_treasure() or spec.is_boss or not spec.enemies.any(func(s: PackedScene) -> bool: return s.resource_path.contains("caster")):
			continue
		var room := await _enter(i)
		for e in _enemies(room):
			if e is RangedEnemy:
				return e
	return null


## [elite, ordinary] enemies from one combat room, or [].
func _elite_and_normal() -> Array:
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if spec.is_treasure() or spec.is_boss or not spec.enemies.any(func(s: PackedScene) -> bool: return s.resource_path.contains("blood")):
			continue
		var room := await _enter(i)
		var elites := _enemies(room).filter(func(e: Enemy) -> bool: return e.elite)
		var normals := _enemies(room).filter(func(e: Enemy) -> bool: return not e.elite)
		if not elites.is_empty() and not normals.is_empty():
			return [elites[0], normals[0]]
	return []


func _boss_room() -> Boss:
	while _run.level < _run.max_level():
		_run.add_rewards(_run.xp_to_next_level(), 0)
	_dungeon.enter_room(_dungeon.index_at(BOSS), &"DoorBottom")
	await _frames(2)
	for e in _enemies(_dungeon.current_room):
		if e is Boss:
			return e
	return null


func _win_fast() -> void:
	var boss := await _boss_room()
	boss.take_damage(99999.0)
	await _wait_until(func() -> bool: return (current_scene.get_node(^"VictoryOverlay") as VictoryOverlay).is_open, 240)


## Unscaled stats of a fresh instance of `scene`.
func _base_stats(scene: PackedScene) -> Dictionary:
	var e := scene.instantiate() as Enemy
	var stats := {"hp": (e.get_node(^"Health") as Health).max_health, "damage": e.contact_damage,
			"speed": e.speed, "cooldown": e.attack_cooldown}
	if e is RangedEnemy:
		stats["projectile"] = (e as RangedEnemy).projectile_damage
	if e is Boss:
		stats["slam"] = (e as Boss).slam_damage
		stats["volley"] = (e as Boss).volley_damage
	e.free()
	return stats


func _enemies(room: Room) -> Array:
	return room.get_node(^"Enemies").get_children().filter(func(n: Node) -> bool: return n is Enemy and not n.is_queued_for_deletion())


func _kill_all(room: Room) -> void:
	for e in _enemies(room):
		(e as Enemy).take_damage(999999.0)


func _hostile_shots() -> Array:
	return current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile and (n as Projectile).hostile_to_player)


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage if _dungeon else null
	_run = _dungeon.run_state if _dungeon else null
	if _run:
		_run.xp_multiplier_override = 1.0  # raw enemy XP (scaled XP is tested in test_endless_progression.gd)


func _wait_for_scene(old_id: int, dungeon: bool = true) -> void:
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	if dungeon:
		_bind()


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
