extends SceneTree
## Headless check of the optional treasure rooms (scenes/dungeon/dungeon.tscn):
## seeded in-grid dead-end layout (Issue #45) and minimap markers, the timed survival trial (start once, timer,
## waves, locked exits, completion only after timer + clear), the rune
## sequence puzzle (correct order only, reset on mistakes, persistent state),
## one-time chest rewards, revisits, Restart, and that the treasure rooms are
## not needed for the pre-boss anvil.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_treasure_rooms.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const ACTIONS := {&"DoorTop": &"move_up", &"DoorBottom": &"move_down", &"DoorLeft": &"move_left", &"DoorRight": &"move_right"}

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	change_scene_to_file(SCENE)
	await _wait_for_scene(0)
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
	else:
		_test_layout()
		await _test_survival()
		await _test_puzzle()
		await _test_restart()
		await _test_not_required_for_anvil()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _test_layout() -> void:
	var s := _dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)
	var p := _dungeon.treasure_index(RoomSpec.Treasure.PUZZLE)
	_check(s >= 0 and _dungeon.rooms[s].treasure == RoomSpec.Treasure.SURVIVAL and _dungeon.rooms[s].cell.y <= 2,
			"survival treasure room in the Level 2 rows (%s)" % _dungeon.rooms[s].cell)
	_check(p >= 0 and _dungeon.rooms[p].treasure == RoomSpec.Treasure.PUZZLE and _dungeon.rooms[p].cell.y >= 3,
			"rune puzzle treasure room in the Level 1 rows (%s)" % _dungeon.rooms[p].cell)
	_check(_dungeon.rooms.filter(func(r: RoomSpec) -> bool: return r.is_treasure()).size() == 2, "exactly two treasure rooms")
	_check(_entry_of(s) >= 0 and _entry_of(p) >= 0 and not _dungeon.rooms[_entry_of(s)].is_treasure()
			and not _dungeon.rooms[_entry_of(p)].is_treasure(), "treasure rooms are dead-end side rooms off main rooms")
	_check(_exit(s) != &"DoorTop" and _exit(p) != &"DoorBottom",
			"treasure room doors avoid their chests (survival %s, puzzle %s)" % [_exit(s), _exit(p)])
	_check(not _dungeon.rooms[s].is_boss and not _dungeon.rooms[p].is_boss and _dungeon.rooms[s].enemies.is_empty(),
			"treasure rooms are not boss/encounter rooms")
	var map := _map()
	var normal := map.marker_color(_dungeon.start_room)
	var sc := map.marker_color(s)
	var pc := map.marker_color(p)
	_check(normal.a == 0.0 and sc.a > 0.0 and pc.a > 0.0 and sc != pc, "minimap marks both treasure rooms with distinct colours")


func _test_survival() -> void:
	_run.add_rewards(_run.xp_to_next_level(), 0)  # Lv 2: the survival room's neighbour tier
	var index := _dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	var room := _dungeon.current_room as SurvivalRoom
	_check(room != null and room.state == Room.State.IDLE and room.can_exit() and _door(room, _exit(index)).is_open(),
			"survival room: entering does not start the trial, exit open")
	_check(_hud_text().begins_with("Survival trial"), "HUD names the room before the trial (%s)" % _hud_text())
	_check(not room.chest.interact() and _run.currency == 0, "chest sealed before the trial")
	_check(_map().marker_color(index) == _map().survival_color, "survival marker shown while uncompleted")

	# Leaving before the trial is allowed.
	await _try_exit(room, _exit(index), ACTIONS[_exit(index)])
	_check(_dungeon.current_index == _entry_of(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)), "Mage can leave before starting the trial")
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)

	# Start through the altar with a real "interact" press, standing next to it.
	_mage.global_position = room.altar.global_position + Vector2(0, 40)
	await _wait_until(func() -> bool: return room.altar.player_near)
	_press_interact()
	await _wait_until(func() -> bool: return room.state == Room.State.COMBAT)
	_check(room.state == Room.State.COMBAT and room.waves_spawned == 1 and room.enemies_remaining == room.wave_sizes[0],
			"[E] at the altar starts the trial with wave 1 (%d enemies)" % room.enemies_remaining)
	var too_close := _enemies(room).filter(func(e: Enemy) -> bool:
		return e.global_position.distance_to(_mage.global_position) < room.min_spawn_distance)
	_check(too_close.is_empty(), "no enemy spawns next to the Mage")
	_check(_all_locked(room) and not room.can_exit(), "exits lock while the trial runs")
	_check(not room.begin_challenge() and not room.altar.can_interact() and room.waves_spawned == 1, "trial cannot be started twice")
	var t0 := room.time_left()
	await _wait_until(func() -> bool: return room.time_left() < t0 - 0.05)
	_check(room.time_left() < t0 and room.time_left() > room.duration - 5.0, "timer counts down (%.2f s left)" % room.time_left())
	_check(_hud_text().begins_with("Defeat all waves") and _hud_text().contains("Wave 1/4") and _hud_text().contains("Time "), "HUD shows timer and wave (%s)" % _hud_text())

	_check(room.wave_sizes == PackedInt32Array([3, 4, 5, 6]) and room.wave_enemies.size() == 18, "waves escalate 3/4/5/6 (18 enemies)")

	# No new wave while enemies remain, however long it takes.
	room._advance(60.0)
	await _frames(2)
	_check(room.waves_spawned == 1 and room.enemies_remaining == 3, "no next wave while wave 1 is alive (60 s later)")
	_check(_all_locked(room) and not room.chest.interact(), "exits locked and chest sealed during the trial")
	await _try_exit(room, _exit(index), ACTIONS[_exit(index)])
	_check(_dungeon.current_room == room, "Mage cannot leave during the trial")

	# A duplicate death signal is counted once and cannot skip a wave.
	var first: Enemy = _enemies(room)[0]
	first.died.emit()
	first.died.emit()
	await _frames(2)
	_check(room.enemies_remaining == 2 and room.waves_spawned == 1, "duplicate death signal counted once, no extra wave")

	# Clearing a wave spawns the next one right away; the timer keeps running.
	var t_before := room.time_left()
	for wave in range(2, 5):
		await _kill_all(room)
		await _wait_until(func() -> bool: return room.waves_spawned == wave)
		_check(room.waves_spawned == wave and room.enemies_remaining == room.wave_sizes[wave - 1]
				and room.state == Room.State.COMBAT, "wave %d spawns as soon as wave %d is defeated (%d enemies)" % [wave, wave - 1, room.enemies_remaining])
		var close := _enemies(room).filter(func(e: Enemy) -> bool:
			return e.global_position.distance_to(_mage.global_position) < room.min_spawn_distance)
		_check(close.is_empty(), "wave %d keeps its distance from the Mage" % wave)
	_check(_hud_text().contains("Wave 4/4"), "HUD tracks the wave (%s)" % _hud_text())
	_check(room._spawned_enemies == 18, "all 18 wave enemies spawned once")

	# All waves cleared early: the trial ends at once, the timer is display-only.
	await _kill_all(room)
	await _frames(2)
	_check(room.all_waves_cleared() and room.waves_spawned == 4 and room.time_left() > 0.0 and room.time_left() < t_before,
			"all waves cleared with time left (%.0f s)" % room.time_left())
	_check(room.state == Room.State.CLEARED and room.can_exit() and _door(room, _exit(index)).is_open(),
			"clearing the last wave completes the trial immediately and unlocks the exit")
	_check(_dungeon.is_cleared(index) and _map().marker_color(index) != _map().survival_color, "minimap shows the trial as completed")
	_check(_hud_text() == "Trial complete! Open the chest", "HUD points at the chest (%s)" % _hud_text())

	# Chest: once.
	_mage.health.take_damage(60.0)
	var hp := _mage.health.current
	var gold := _run.currency
	_check(room.chest.can_interact() and room.chest.interact(), "chest opens after the trial")
	_check(_run.currency == gold + 150 and is_equal_approx(_mage.health.current, minf(hp + 50.0, _mage.health.max_health)),
			"Survivor's Cache: +150 gold, restores 50 HP (%d gold, %.0f HP)" % [_run.currency, _mage.health.current])
	_check(_message().begins_with("Survivor's Cache"), "reward announced (%s)" % _message())
	_check(not room.chest.interact() and _run.currency == gold + 150 and not _run.claim_treasure(&"survivor_cache"),
			"chest reward cannot be claimed twice")
	_check(_hud_text() == "Treasure claimed", "HUD shows the claimed treasure")

	# Revisit.
	gold = _run.currency
	await _try_exit(room, _exit(index), ACTIONS[_exit(index)])
	_check(_dungeon.current_index == _entry_of(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)), "exit works after the trial")
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(3)
	_check(_dungeon.current_room == room and room.state == Room.State.CLEARED and _enemies(room).is_empty()
			and room.waves_spawned == 4 and room._spawned_enemies == 18 and _run.currency == gold, "revisit: trial stays completed, no respawns")
	_check(not room.begin_challenge() and not room.altar.can_interact() and not room.chest.interact(),
			"revisit: trial cannot restart, chest stays empty")


func _test_puzzle() -> void:
	var index := _dungeon.treasure_index(RoomSpec.Treasure.PUZZLE)
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	var room := _dungeon.current_room as RunePuzzleRoom
	_check(room != null and room.state == Room.State.IDLE and room.can_exit() and _door(room, _exit(index)).is_open(),
			"rune room: no combat, exit open")
	var order := room.sequence
	var a := order[0] if order.size() == 3 else "moon"
	var b := order[1] if order.size() == 3 else "sun"
	var c := order[2] if order.size() == 3 else "star"
	var sorted := Array(order)
	sorted.sort()
	_check(sorted == ["moon", "star", "sun"] and room.get_rune("sun") and room.get_rune("moon") and room.get_rune("star")
			and (room.get_node(^"Decor/Plaque") as Label).text == room.hint_text(order),
			"three runes in a seeded order %s, the plaque gives that order" % order)
	_check(_hud_text().begins_with("Rune puzzle") and _hud_text().contains("0/3"), "HUD explains the puzzle (%s)" % _hud_text())
	_check(not room.chest.interact(), "chest sealed before solving")

	# Wrong first rune.
	_check(not room.activate(b) and room.progress == 0 and room.mistakes == 1, "wrong first rune is rejected")
	_check(room.get_rune(b).wrong_flash > 0.0 and not room.get_rune(b).lit, "wrong rune flashes red")
	_check(_hud_text().begins_with("Wrong order"), "HUD reports the mistake (%s)" % _hud_text())
	# Correct, then wrong: everything resets.
	_check(room.activate(a) and room.get_rune(a).lit and room.progress == 1, "correct rune lights up")
	_check(not room.activate(c) and room.progress == 0 and not room.get_rune(a).lit and room.mistakes == 2,
			"wrong rune after a correct one resets the sequence")
	# A lit rune is ignored (no reset).
	room.activate(a)
	_check(not room.activate(a) and room.progress == 1 and room.mistakes == 2, "touching a lit rune again is ignored")

	# Progress persists when leaving mid-sequence.
	await _try_exit(room, _exit(index), ACTIONS[_exit(index)])
	_check(_dungeon.current_index == _entry_of(_dungeon.treasure_index(RoomSpec.Treasure.PUZZLE)), "Mage can leave the unsolved rune room")
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	_check(_dungeon.current_room == room and room.progress == 1 and room.get_rune(a).lit, "partial progress kept on revisit")

	# Real "interact" press on the next rune.
	_mage.global_position = room.get_rune(b).global_position + Vector2(0, 36)
	await _wait_until(func() -> bool: return room.get_rune(b).player_near)
	_press_interact()
	await _wait_until(func() -> bool: return room.progress == 2)
	_check(room.progress == 2 and room.get_rune(b).lit, "[E] at a rune activates it")
	_check(room.activate(c) and room.is_solved() and room.state == Room.State.CLEARED, "correct full sequence solves the puzzle")
	_check(room.get_rune(a).solved and room.get_rune(b).solved and room.get_rune(c).solved, "solved runes turn gold")
	_check(not room.activate(b) and room.progress == 3, "solved puzzle ignores further activations")
	_check(_dungeon.is_cleared(index) and _map().marker_color(index) != _map().puzzle_color, "minimap shows the puzzle as completed")

	var cooldown := _run.spell_cooldown_multiplier()
	_check(room.chest.interact() and is_equal_approx(_run.spell_cooldown_multiplier(), cooldown - 0.05),
			"Rune Sigil: -5%% spell cooldown (%.2f)" % _run.spell_cooldown_multiplier())
	_check(is_equal_approx(_mage.caster.cooldown_multiplier, _run.spell_cooldown_multiplier()), "Mage spell cooldown follows the sigil")
	_check(_items_text().contains("Rune Sigil"), "HUD lists the Rune Sigil (%s)" % _items_text())
	_check(not room.chest.interact() and is_equal_approx(_run.spell_cooldown_multiplier(), cooldown - 0.05), "sigil cannot be claimed twice")

	await _try_exit(room, _exit(index), ACTIONS[_exit(index)])
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	_check(room.is_solved() and room.chest.is_claimed() and is_equal_approx(_run.spell_cooldown_multiplier(), cooldown - 0.05)
			and _hud_text() == "Treasure claimed", "revisit: puzzle stays solved, no duplicate reward")
	var summary := _dungeon.run_summary()
	_check(summary["treasures"] == [&"survivor_cache", &"rune_sigil"] and summary["rooms_total"] == 23,
			"run summary lists both treasures; room count is the 23 main rooms")


func _test_restart() -> void:
	await _restart()
	_check(_run.treasures.is_empty() and not _dungeon.is_visited(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL))
			and not _dungeon.is_visited(_dungeon.treasure_index(RoomSpec.Treasure.PUZZLE)), "Restart resets treasures and both rooms")
	_dungeon.enter_room(_dungeon.treasure_index(RoomSpec.Treasure.PUZZLE), _dungeon.entry_door(_dungeon.treasure_index(RoomSpec.Treasure.PUZZLE)))
	await _frames(2)
	var puzzle := _dungeon.current_room as RunePuzzleRoom
	_check(puzzle.progress == 0 and not puzzle.is_solved() and not puzzle.chest.is_claimed() and not puzzle.chest.can_interact(),
			"Restart: puzzle unsolved, chest sealed")
	_run.add_rewards(_run.xp_to_next_level(), 0)
	_dungeon.enter_room(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL), _dungeon.entry_door(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)))
	await _frames(2)
	var survival := _dungeon.current_room as SurvivalRoom
	_check(survival.state == Room.State.IDLE and survival.waves_spawned == 0 and not survival.chest.is_claimed(),
			"Restart: survival trial ready again")
	# Dying during the trial ends the run normally; Restart resets the trial.
	_check(survival.begin_challenge(), "setup: trial started")
	# Time running out with waves left: the remaining waves must still be fought.
	survival._advance(survival.duration)
	_check(survival.time_left() == 0.0 and survival.waves_spawned == 1 and survival.state == Room.State.COMBAT,
			"timer over during wave 1: trial not complete")
	_check(_hud_text().begins_with("Defeat all waves") and _hud_text().contains("Time 0:00"), "HUD keeps asking for the remaining waves (%s)" % _hud_text())
	await _kill_all(survival)
	await _wait_until(func() -> bool: return survival.waves_spawned == 2)
	_check(survival.waves_spawned == 2 and survival.state == Room.State.COMBAT, "after time is up, the next wave still spawns")
	_mage.take_damage(9999.0)
	await _frames(3)
	_check(_mage.is_dead() and survival.state == Room.State.COMBAT, "Mage death during the trial: room stays locked (Game Over)")
	await _restart()
	_dungeon.enter_room(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL), _dungeon.entry_door(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)))
	await _frames(2)
	var fresh := _dungeon.current_room as SurvivalRoom
	_check(fresh != survival and fresh.state == Room.State.IDLE and _enemies(fresh).is_empty(), "Restart after dying mid-trial gives a fresh room")


func _test_not_required_for_anvil() -> void:
	await _restart()
	var boss := -1
	for i in _dungeon.rooms.size():
		if _dungeon.rooms[i].is_boss:
			boss = i
		elif not _dungeon.rooms[i].is_treasure():
			_dungeon.enter_room(i)
			await _frames(1)
			_dungeon.current_room.start_encounter()
			await _kill_all(_dungeon.current_room)
	_check(_dungeon.all_rooms_cleared() and _dungeon.final_anvil != null and not _dungeon.is_visited(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL))
			and not _dungeon.is_visited(_dungeon.treasure_index(RoomSpec.Treasure.PUZZLE)), "pre-boss anvil appears without the treasure rooms")
	_check(boss >= 0 and not _dungeon.is_visited(boss), "boss room untouched")


# --- helpers ---

## The only door of treasure room `index` (towards its main room).
func _exit(index: int) -> StringName:
	return _dungeon.door_to(index, _entry_of(index))


func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = &"interact"
	release.pressed = false
	Input.parse_input_event(release)


func _restart() -> void:
	if not _mage.is_dead():
		_mage.take_damage(9999.0)
		await _frames(1)
	var old_id := current_scene.get_instance_id()
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_for_scene(old_id)


## Scene changes are deferred; waits until a new, ready scene (not `old_id`) is current, then binds.
func _wait_for_scene(old_id: int) -> void:
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	if _dungeon:
		_mage = _dungeon.mage
		_run = _dungeon.run_state


func _try_exit(room: Room, door_name: StringName, action: StringName) -> void:
	var door := _door(room, door_name)
	var dir: Vector2 = {&"move_up": Vector2.UP, &"move_down": Vector2.DOWN,
			&"move_left": Vector2.LEFT, &"move_right": Vector2.RIGHT}[action]
	_mage.global_position = door.global_position - dir * 60.0
	Input.action_press(action)
	await _wait_until(func() -> bool: return _dungeon.current_room != room, 50)
	Input.action_release(action)
	await _frames(2)


func _kill_all(room: Room) -> void:
	for enemy in _enemies(room):
		enemy.take_damage(99999.0)
	await _wait_until(func() -> bool: return _enemies(room).is_empty())
	await _frames(1)


func _enemies(room: Room) -> Array:
	return room.get_node(^"Enemies").get_children().filter(func(n: Node) -> bool: return n is Enemy and not n.is_queued_for_deletion())


func _door(room: Room, door_name: StringName) -> Door:
	return room.get_node(NodePath("Doors/" + door_name)) as Door


func _all_locked(room: Room) -> bool:
	return room.get_doors().all(func(d: Door) -> bool: return not d.is_open())


func _map() -> DungeonMap:
	return current_scene.get_node(^"DungeonMap/Map") as DungeonMap


func _hud_text() -> String:
	var label := current_scene.get_node(^"RoomHud/StatusLabel") as Label
	return label.text if label.visible else ""


func _message() -> String:
	return (current_scene.get_node(^"RunHud/MessageLabel") as Label).text


func _items_text() -> String:
	return (current_scene.get_node(^"RunHud/ItemsLabel") as Label).text


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


## The room a treasure room is linked to (its only neighbour; seeded layout, Issue #45).
func _entry_of(index: int) -> int:
	var links := _dungeon.get_neighbours(index)
	return links[0] if links.size() == 1 else -1
