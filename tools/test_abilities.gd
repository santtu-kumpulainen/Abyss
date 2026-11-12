extends SceneTree
## Headless check of the Issue #49 abilities. Stage 3, Dash:
## - the dash input and its animations;
## - distance, duration and direction (input, facing, diagonal), not scaled by speed;
## - wall stop, invulnerability window and cooldown timing;
## - blocked states, end_run() flag, cancel, no casting during the burst;
## - visuals (puff, trail, afterimages, lean) and the cooldown bar;
## - cancel on a room change, and walking unchanged after a dash.
## Stage 4, Home Teleport: refusals (none owned, start room, combat, busy),
## the 1.5 s cast to the run's start_room with exactly one item spent, the
## ring/aura/arrival effects, cancellation by movement input, being moved,
## damage, dash, attack, the key again, room change, victory, level change and
## death (item kept), the destination after a level change, no duplicates.
## Fixes: a trial started (E at the altar) during a cast cancels it and blocks
## the escape; dash/arrival visuals never carry into another room, while the
## arrival warp plays in the destination and effects on the Mage are kept.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_abilities.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const MAGE_SCENE := "res://scenes/test/mage_test.tscn"
const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"
const MAGE_FRAMES := "res://scenes/mage/sprite_frames/mage.tres"
const DIRECTIONS: Array[StringName] = [
	&"east", &"south_east", &"south", &"south_west", &"west", &"north_west", &"north", &"north_east",
]
## Physics ticks per second (project default).
const TICKS := 60.0
const TELEPORT_SEED := 4949

var _failures := 0
var _mage: Mage
var _started: Array[Vector2] = []
var _ended := 0
var _dungeon: Dungeon
var _tp: HomeTeleport
var _idle := -1
var _tp_started := 0
var _tp_completed := 0
var _tp_state_changes := 0
var _tp_cancels: Array[StringName] = []


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_input_and_animations()
	await _load(MAGE_SCENE)
	_mage = current_scene.get_node(^"Mage") as Mage
	_mage.dash_started.connect(func(dir: Vector2) -> void: _started.append(dir))
	_mage.dash_ended.connect(func() -> void: _ended += 1)
	_check(_mage.dash_distance == 110.0 and _mage.dash_duration == 0.15 and _mage.dash_invulnerability == 0.20
			and _mage.dash_cooldown == 2.75, "dash values: 110 px, 0.15 s, 0.20 s invulnerable, 2.75 s cooldown")
	_check(_mage.dash_ready() and _mage.can_dash() and is_equal_approx(_mage.dash_cooldown_ratio(), 1.0)
			and _mage.dash_cooldown_remaining() == 0.0, "the dash is ready at the start")
	await _test_distance_and_direction()
	await _test_invulnerability()
	await _test_cooldown_and_bar()
	await _test_wall_stop()
	await _test_blocked_states()
	await _test_no_casting()
	await _test_visuals()
	await _test_cancel()
	await _test_input_key()
	await _test_walking_unchanged()
	await _test_room_change()
	await _test_home_teleport()
	await _test_trial_and_cleanup()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Resources --------------------------------------------------------------------

func _test_input_and_animations() -> void:
	var events := InputMap.action_get_events(&"dash") if InputMap.has_action(&"dash") else []
	_check(events.size() == 1 and events[0] is InputEventKey and (events[0] as InputEventKey).physical_keycode == KEY_SPACE,
			"input action dash = physical Space")
	var others: Array[StringName] = []
	for action in InputMap.get_actions():
		if action == &"dash" or String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SPACE:
				others.append(action)
	_check(others.is_empty(), "no other gameplay action uses Space %s" % [others])

	var frames := load(MAGE_FRAMES) as SpriteFrames
	var ok := true
	for dir in DIRECTIONS:
		var dash := StringName("dash_" + dir)
		var walk := StringName("walk_" + dir)
		if not frames.has_animation(dash) or frames.get_animation_loop(dash) or frames.get_animation_speed(dash) != 40.0:
			ok = false
			continue
		if frames.get_frame_count(dash) != ceili(frames.get_frame_count(walk) / 2.0):
			ok = false
		for i in frames.get_frame_count(dash):
			if frames.get_frame_texture(dash, i) != frames.get_frame_texture(walk, i * 2):
				ok = false
	_check(ok, "dash_<dir> for all 8 directions: every 2nd walk frame, 40 FPS, played once")
	var unchanged := true
	for dir in DIRECTIONS:
		for action in ["idle", "walk"]:
			var anim := StringName("%s_%s" % [action, dir])
			unchanged = unchanged and frames.has_animation(anim) and frames.get_animation_loop(anim) and frames.get_animation_speed(anim) == 12.0
	_check(unchanged and frames.get_animation_names().size() == 24, "idle/walk animations unchanged (looping, 12 FPS); 24 animations")


# --- Movement ---------------------------------------------------------------------

func _test_distance_and_direction() -> void:
	_place(Vector2(300, 324))
	var start := _mage.global_position
	_check(_mage.try_dash(Vector2.RIGHT) and _mage.is_dashing(), "try_dash(right) starts a dash")
	_check(_started.size() == 1 and _started[0].is_equal_approx(Vector2.RIGHT), "dash_started is emitted with the direction")
	_check(not _mage.try_dash(Vector2.LEFT), "no second dash while dashing")
	var ticks := await _ticks_until(func() -> bool: return not _mage.is_dashing())
	var moved := _mage.global_position - start
	_check(absf(moved.x - 110.0) <= 5.5 and absf(moved.y) < 0.5, "dash right moves 110 px (+-5%%): %.2f" % moved.x)
	_check(absf(ticks / TICKS - 0.15) <= 1.0 / TICKS + 0.001, "the burst lasts 0.15 s (%d ticks)" % ticks)
	_check(_ended == 1 and _mage.velocity == Vector2.ZERO and _mage.facing == &"east", "dash_ended once, stopped, facing east")

	await _recover()
	_place(Vector2(300, 324))
	start = _mage.global_position
	_mage.try_dash(Vector2(1, 1))
	await _ticks_until(func() -> bool: return not _mage.is_dashing())
	_check(absf(start.distance_to(_mage.global_position) - 110.0) <= 5.5, "a diagonal dash is not longer (%.2f px)" % start.distance_to(_mage.global_position))

	await _recover()
	_place(Vector2(500, 324))
	_mage.facing = &"north"
	start = _mage.global_position
	_mage.try_dash()
	await _ticks_until(func() -> bool: return not _mage.is_dashing())
	var up := _mage.global_position - start
	_check(absf(up.y + 110.0) <= 5.5 and absf(up.x) < 0.5, "no input: dashes toward facing (north, %s)" % up)

	await _recover()
	_place(Vector2(300, 324))
	_mage.speed_multiplier = 1.6
	start = _mage.global_position
	_mage.try_dash(Vector2.RIGHT)
	await _ticks_until(func() -> bool: return not _mage.is_dashing())
	_check(absf(_mage.global_position.x - start.x - 110.0) <= 5.5, "speed upgrades/potions do not scale the dash (%.2f px)" % (_mage.global_position.x - start.x))
	_mage.speed_multiplier = 1.0


func _test_wall_stop() -> void:
	await _recover()
	# The left wall's inner face is at x = 32; the feet circle has radius 8.
	_place(Vector2(80, 324))
	_mage.try_dash(Vector2.LEFT)
	var ticks := await _ticks_until(func() -> bool: return not _mage.is_dashing())
	_check(_mage.global_position.x >= 39.0 and _mage.global_position.x <= 42.0, "a wall stops the dash (x = %.1f)" % _mage.global_position.x)
	_check(ticks <= 10, "the dash still ends on time against a wall (%d ticks)" % ticks)


# --- Invulnerability and cooldown -------------------------------------------------

func _test_invulnerability() -> void:
	await _recover()
	_place(Vector2(300, 324))
	var hp := _mage.health.current
	_mage.try_dash(Vector2.RIGHT)
	_mage.take_damage(10.0)
	_check(_mage.health.current == hp and _mage.is_dash_invulnerable(), "damage at the dash start is ignored")
	await _ticks(11)  # ~0.183 s after the start.
	_mage.take_damage(10.0)
	_check(_mage.health.current == hp and _mage.is_dash_invulnerable() and not _mage.is_dashing(),
			"still ignored after the burst, inside 0.20 s")
	var ticks := 11 + await _ticks_until(func() -> bool: return not _mage.is_dash_invulnerable())
	_check(absi(ticks - 12) <= 1, "invulnerability ends 0.20 s after the start (%d ticks)" % ticks)
	_mage.take_damage(10.0)
	_check(_mage.health.current < hp, "damage applies normally after 0.20 s")
	_check(not _mage.invulnerable, "dash never sets the end_run() invulnerable flag")
	_mage.health.increase_max_health(0.0, _mage.health.max_health)


func _test_cooldown_and_bar() -> void:
	await _recover()
	var bar := _mage.get_node_or_null(^"DashBar") as DashBar
	_check(bar != null and bar.mage == _mage and is_equal_approx(bar.value, 1.0), "DashBar under the Mage, full while ready")
	_check(bar != null and bar.position.y > _mage.get_node(^"HealthBar").position.y and bar.size.x == (_mage.get_node(^"HealthBar") as Control).size.x,
			"DashBar sits below the HP bar with the same width")
	_place(Vector2(300, 324))
	# Start the dash between frames (not inside a physics_frame callback, where
	# _recover() returns): then every physics tick counted from dash_tick is one the
	# Mage has processed, so elapsed ticks and its cooldown line up exactly.
	await process_frame
	_mage.try_dash(Vector2.RIGHT)
	var dashes := _started.size()
	var dash_tick := Engine.get_physics_frames()
	var cooldown := _mage.dash_cooldown
	_check(not _mage.dash_ready() and _mage.dash_cooldown_ratio() == 0.0 and _mage.dash_cooldown_remaining() == cooldown,
			"the cooldown starts full when the dash is used (ratio 0, %.2f s left)" % _mage.dash_cooldown_remaining())
	# A process frame can contain 0..N physics ticks (the engine catches up after a
	# slow frame), so the expected values come from the ticks that actually ran.
	var seen := await _bar_sample()
	var elapsed := Engine.get_physics_frames() - dash_tick
	_check(not _mage.dash_ready() and is_equal_approx(bar.value, seen) and seen < _mage.dash_cooldown_ratio() + 0.0001
			and absf(_mage.dash_cooldown_ratio() - elapsed / TICKS / cooldown) <= 0.25 / TICKS / cooldown,
			"the bar empties when the dash is used and refills only with elapsed time (%.3f after %d ticks)" % [_mage.dash_cooldown_ratio(), elapsed])
	_check(not _mage.try_dash(Vector2.LEFT) and _started.size() == dashes, "no dash during the cooldown")
	var last := -1.0
	var rising := true
	var ticks := 0
	while not _mage.dash_ready() and ticks < 400:
		await physics_frame
		ticks += 1
		var ratio := _mage.dash_cooldown_ratio()
		rising = rising and ratio >= last
		last = ratio
		if ticks == 30:
			seen = await _bar_sample()
			# After a process frame every physics tick since the dash has run, so the
			# remaining time is exactly the cooldown minus the ticks that elapsed.
			elapsed = Engine.get_physics_frames() - dash_tick
			_check(is_equal_approx(bar.value, seen), "the bar shows the Mage's cooldown (%.2f)" % bar.value)
			_check(elapsed >= 30 and absf(_mage.dash_cooldown_remaining() - (cooldown - elapsed / TICKS)) <= 0.25 / TICKS,
					"dash_cooldown_remaining counts down (%.3f s after %d ticks)" % [_mage.dash_cooldown_remaining(), elapsed])
	ticks = Engine.get_physics_frames() - dash_tick
	_check(absi(ticks - 165) <= 1, "the dash is ready 2.75 s after the start (%d ticks)" % ticks)
	_check(rising and is_equal_approx(_mage.dash_cooldown_ratio(), 1.0), "the cooldown ratio rises steadily to 1.0")
	await _redraw()
	_check(is_equal_approx(bar.value, 1.0), "the bar is full when dash_ready() turns true")
	_check(_mage.try_dash(Vector2.RIGHT), "the dash is available right when the cooldown ends")
	await _ticks_until(func() -> bool: return not _mage.is_dashing())


# --- Blocked states ---------------------------------------------------------------

func _test_blocked_states() -> void:
	await _recover()
	_mage.end_run()
	_check(not _mage.try_dash(Vector2.RIGHT) and not _mage.can_dash() and _mage.invulnerable, "end_run(): no dash, flag kept")
	_mage.resume_run()
	_check(not _mage.invulnerable and _mage.try_dash(Vector2.RIGHT), "resume_run(): dash available again, flag cleared")
	_mage.end_run()
	_check(not _mage.is_dashing() and not _mage.is_dash_invulnerable() and _mage.invulnerable, "end_run() during a dash stops it and keeps the flag")
	_mage.resume_run()
	_check(not _mage.invulnerable, "the dash never changes the end_run() flag")


func _test_no_casting() -> void:
	await _recover()
	_place(Vector2(300, 324))
	var casts := [0]
	var count := func(_p: Projectile) -> void: casts[0] += 1
	_mage.caster.cast.connect(count)
	await _ticks_until(func() -> bool: return _mage.caster.can_cast())
	_mage.try_dash(Vector2.RIGHT)
	Input.action_press(&"attack")
	await _ticks_until(func() -> bool: return not _mage.is_dashing())
	_check(casts[0] == 0, "no spell is cast during the burst")
	await _ticks(3)
	Input.action_release(&"attack")
	_check(casts[0] >= 1, "casting resumes after the burst")
	_mage.caster.cast.disconnect(count)
	await _ticks(2)


# --- Visuals ----------------------------------------------------------------------

func _test_visuals() -> void:
	await _recover()
	_clear_effects()
	_place(Vector2(300, 324))
	var sprite := _mage.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	var base_scale := sprite.scale
	_mage.try_dash(Vector2.UP)
	var puff := _find_puff()
	_check(puff != null and puff.get_parent() == _mage.get_parent(), "a dash_puff spawns in the world")
	_check(puff != null and is_equal_approx(wrapf(puff.rotation, -PI, PI), wrapf(Vector2.DOWN.angle() + PI / 2.0, -PI, PI))
			and puff.global_position.y > _mage.global_position.y, "the puff points against the dash and starts behind the feet")
	var trail := _find(DashTrail) as DashTrail
	_check(trail != null and trail.is_following(), "a trail follows the Mage")
	_check(sprite.animation == &"dash_north" and sprite.is_playing(), "the dash_north animation plays")
	_check(sprite.scale != base_scale, "the sprite is stretched during the burst")
	await _ticks_until(func() -> bool: return not _mage.is_dashing())
	var ghosts := _count_afterimages()
	_check(ghosts >= 3 and ghosts <= 5, "%d afterimages along the path (3-5)" % ghosts)
	_check(trail != null and is_instance_valid(trail) and not trail.is_following() and trail.get_point_count() >= 2, "the trail stops and fades after the burst")
	_check(sprite.scale == base_scale and sprite.skew == 0.0, "the sprite lean/stretch is undone")
	await _ticks(2)
	_check(sprite.animation != &"dash_north", "walking/idle animations resume after the dash")
	await _ticks(40)
	_check(_count_afterimages() == 0 and _find(DashTrail) == null, "afterimages and trail fade out and are freed")


func _test_cancel() -> void:
	await _recover()
	_clear_effects()
	_place(Vector2(300, 324))
	var ended := _ended
	_mage.try_dash(Vector2.RIGHT)
	await _ticks(3)
	_mage.cancel_dash()
	_check(not _mage.is_dashing() and not _mage.is_dash_invulnerable() and _ended == ended + 1, "cancel_dash stops the dash and its invulnerability")
	_check(not _mage.dash_ready(), "the cooldown keeps running after a cancel")
	await process_frame
	_check(_find_puff() == null and _find(DashTrail) == null and _count_afterimages() == 0, "cancel removes the dash visuals")

	await _recover()
	_mage.try_dash(Vector2.RIGHT)
	_mage.health.take_damage(_mage.health.max_health * 10.0)
	_check(_mage.is_dead() and not _mage.is_dashing() and not _mage.try_dash(Vector2.LEFT), "death stops the dash and blocks new ones")


func _test_input_key() -> void:
	# Fresh Mage (the previous one died).
	await _load(MAGE_SCENE)
	_mage = current_scene.get_node(^"Mage") as Mage
	_mage.dash_started.connect(func(dir: Vector2) -> void: _started.append(dir))
	_place(Vector2(300, 324))
	var start := _mage.global_position
	var dashes := _started.size()
	Input.action_press(&"move_down")
	await _press(&"dash")
	await _ticks_until(func() -> bool: return _started.size() > dashes, 10)
	await _ticks_until(func() -> bool: return not _mage.is_dashing())
	Input.action_release(&"move_down")
	_check(not _mage.dash_ready() and _mage.global_position.y - start.y >= 104.0, "Space + S dashes down (%.1f px incl. walking)" % (_mage.global_position.y - start.y))


func _test_walking_unchanged() -> void:
	await _recover()
	_place(Vector2(300, 324))
	Input.action_press(&"move_right")
	await _ticks(3)
	_check(_mage.velocity.is_equal_approx(Vector2(_mage.speed * _mage.speed_multiplier, 0.0)) and not _mage.is_dashing(),
			"walking speed is unchanged (%s)" % _mage.velocity)
	var sprite := _mage.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	_check(sprite.animation == &"walk_east", "walk animation unchanged")
	Input.action_release(&"move_right")
	await _ticks(2)
	_check(sprite.animation == &"idle_east" and _mage.velocity == Vector2.ZERO, "idle when the key is released")


func _test_room_change() -> void:
	await _load(DUNGEON_SCENE)
	var dungeon := current_scene as Dungeon
	_mage = dungeon.mage
	_check(_mage.get_node_or_null(^"DashBar") != null, "the Dungeon's Mage has the dash bar")
	_mage.try_dash(Vector2.RIGHT)
	_check(_mage.is_dashing(), "setup: dashing in the dungeon")
	dungeon.enter_room(dungeon.start_room)
	_check(not _mage.is_dashing() and not _mage.is_dash_invulnerable(), "a room change cancels the dash")
	await process_frame
	_check(_find(DashTrail) == null, "no trail is carried into the next room")


# --- Home Teleport (Stage 4) -------------------------------------------------------

func _test_home_teleport() -> void:
	RunState.seed_override = TELEPORT_SEED
	await _load(DUNGEON_SCENE)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_tp = _dungeon.home_teleport
	var run := _dungeon.run_state
	_tp.cast_started.connect(func() -> void: _tp_started += 1)
	_tp.cast_completed.connect(func() -> void: _tp_completed += 1)
	_tp.cast_cancelled.connect(func(reason: StringName) -> void: _tp_cancels.append(reason))
	_tp.state_changed.connect(func() -> void: _tp_state_changes += 1)

	# State API and refusals.
	_check(_tp != null and _tp.get_parent() == _dungeon, "the Dungeon owns a HomeTeleport")
	_check(not _tp.is_casting() and _tp.cast_progress() == 0.0 and _tp.quantity() == 0 and is_equal_approx(_tp.cast_time(), 1.5),
			"idle: not casting, progress 0, quantity 0, cast time 1.5 s")
	_check(_tp.start_refusal() == &"none_owned" and not _dungeon.use_home_teleport() and _tp_started == 0, "no Home Teleport: cannot cast")
	run.add_rewards(0, 5000)
	_check(run.buy_consumable(&"home_teleport") and _tp.quantity() == 1, "setup: one Home Teleport bought (RunState inventory)")
	_check(_tp.start_refusal() == &"start_room" and not _tp.try_start() and run.consumable_count(&"home_teleport") == 1,
			"in the starting room: cannot cast, item kept")
	_check(not _dungeon.teleport_home(), "teleport_home() itself refuses in the starting room")

	var combat := await _find_combat_room()
	_check(combat >= 0 and _dungeon.current_room.state == Room.State.COMBAT, "setup: in a combat room")
	_check(_tp.start_refusal() == &"combat" and not _tp.try_start(), "during combat: cannot cast")
	_idle = _find_idle_room(combat)
	await _go_idle()
	_check(_idle >= 0 and _dungeon.current_index == _idle and _dungeon.current_room.state != Room.State.COMBAT and _tp.can_start(),
			"in a calm room away from home: can cast")

	# Success.
	var start_index := _dungeon.start_room
	_check(_dungeon.use_home_teleport() and _tp.is_casting() and _tp_started == 1 and _tp.cast_progress() == 0.0 and _tp_state_changes == 1,
			"the cast starts (cast_started, state_changed)")
	_check(not _tp.try_start() and _tp.start_refusal() == &"busy" and _tp_started == 1, "no second cast while casting")
	_check(_effect(&"teleport_ring") != null and _effect(&"teleport_aura") != null, "the blue ring and aura appear")
	var ring := _effect(&"teleport_ring")
	_check(ring != null and ring.z_index == _mage.z_index and ring.get_index() < _mage.get_index() and ring.scale.y < ring.scale.x,
			"the ring is drawn under the Mage (same z, before it) and flattened")
	var small := ring.scale.x if ring else 0.0
	await _ticks(45)
	_check(absf(_tp.cast_progress() - 0.5) <= 0.02 and ring and ring.scale.x > small,
			"halfway: progress %.2f, the ring grows (%.2f -> %.2f)" % [_tp.cast_progress(), small, ring.scale.x if ring else 0.0])
	_check(_dungeon.current_index == _idle and run.consumable_count(&"home_teleport") == 1, "nothing happens before the cast ends")
	var ticks := 45 + await _ticks_until(func() -> bool: return _tp_completed > 0 or not _tp.is_busy(), 120)
	_check(_tp_completed == 1 and absi(ticks - 90) <= 1 and _tp_state_changes == 2, "the teleport happens after 1.5 s (%d ticks)" % ticks)
	var spawn := (_dungeon.current_room.get_node(^"PlayerSpawn") as Node2D).global_position
	_check(_dungeon.current_index == start_index and _mage.global_position.is_equal_approx(spawn), "the Mage is at the starting room's PlayerSpawn")
	_check(run.consumable_count(&"home_teleport") == 0, "the item is spent once")
	_check(not _tp.is_busy() and _tp.cast_progress() == 0.0 and _tp.start_refusal() == &"none_owned", "idle again afterwards")
	await _ticks(1)
	var arrive := _effect(&"teleport_arrive")
	_check(arrive != null and arrive.z_index > _mage.z_index, "the arrival warp plays above the floor")
	_check(_effect(&"teleport_ring") == null and _effect(&"teleport_aura") == null, "no cast effects are left behind")
	await _ticks(2)
	_check(not _dungeon.is_transitioning(), "the transition flag is cleared")

	# Cancellations: the item is kept every time.
	run.add_rewards(0, 1000)
	run.buy_consumable(&"home_teleport")
	await _cancel_case(&"input", func() -> void:
		Input.action_press(&"move_right")
		await _ticks(2)
		Input.action_release(&"move_right"))
	await _cancel_case(&"moved", func() -> void:
		_mage.global_position += Vector2(3, 0)
		await _ticks(1))
	await _cancel_case(&"damage", func() -> void:
		_mage.take_damage(1.0)
		await _ticks(1))
	await _cancel_case(&"dash", func() -> void:
		_check(_mage.try_dash(Vector2.RIGHT), "setup: dash during the cast")
		await _ticks(1))
	await _cancel_case(&"attack", func() -> void:
		Input.action_press(&"attack")
		await _ticks(2)
		Input.action_release(&"attack"))
	await _cancel_case(&"manual", func() -> void:
		_dungeon.use_home_teleport()
		await _ticks(1))
	await _cancel_case(&"room_change", func() -> void:
		_dungeon.enter_room(_find_idle_room(_idle))
		_check(_effect(&"teleport_ring") == null and _effect(&"teleport_aura") == null, "a room change removes the cast effects at once")
		await _ticks(1))
	await _cancel_case(&"victory", func() -> void:
		_dungeon.victory_started.emit()
		await _ticks(1))

	# Level change (forced: a real one needs the boss reward), then the
	# destination follows the new level's start_room.
	await _go_idle()
	_tp.try_start()
	run.boss_defeated = true
	run._relic_claimed = true
	_dungeon.victory = true
	_check(_dungeon.advance_level() and _tp_cancels.back() == &"level_change" and not _tp.is_busy(),
			"a level change cancels the cast")
	_check(run.dungeon_level == 2 and run.consumable_count(&"home_teleport") == 1, "the item is kept into level 2")
	await _ticks(3)
	_idle = _find_idle_room(-1)
	await _go_idle()
	var new_start := _dungeon.start_room
	_tp.try_start()
	await _ticks_until(func() -> bool: return not _tp.is_busy(), 120)
	_check(_dungeon.current_index == new_start and run.consumable_count(&"home_teleport") == 0,
			"level 2: teleports to that level's start_room (%d)" % new_start)

	# The destination is read when the teleport happens, not cached.
	run.add_rewards(0, 1000)
	run.buy_consumable(&"home_teleport")
	await _ticks(3)
	var other := _find_idle_room(-1)
	_idle = _find_idle_room(other)
	await _go_idle()
	_tp.try_start()
	await _ticks(30)
	_dungeon.start_room = other
	await _ticks_until(func() -> bool: return not _tp.is_busy(), 120)
	_check(_dungeon.current_index == other and other != new_start, "a re-planned start_room is the destination (%d)" % other)
	_dungeon.start_room = new_start

	# Duplicate protection: one item, one teleport.
	run.add_rewards(0, 1000)
	run.buy_consumable(&"home_teleport")
	await _ticks(3)
	await _go_idle()
	var completed := _tp_completed
	_tp.try_start()
	await _ticks(89)
	_check(not _tp.try_start() and not _dungeon.teleport_home(), "no second cast or direct teleport during a cast")
	await _ticks_until(func() -> bool: return not _tp.is_busy(), 30)
	_check(_tp_completed == completed + 1 and run.consumable_count(&"home_teleport") == 0 and _dungeon.current_index == _dungeon.start_room,
			"one cast gives exactly one teleport")
	_check(not _dungeon.teleport_home() and not _tp.try_start(), "nothing left to teleport with")

	# Death (last: the run ends).
	run.add_rewards(0, 1000)
	run.buy_consumable(&"home_teleport")
	await _ticks(3)
	await _go_idle()
	_tp.try_start()
	_mage.health.take_damage(_mage.health.max_health * 10.0)
	await _ticks(2)
	_check(_mage.is_dead() and not _tp.is_busy() and _tp_cancels.back() in [&"death", &"damage"]
			and run.consumable_count(&"home_teleport") == 1 and _dungeon.current_index == _idle, "death cancels the cast, no teleport")
	_check(_tp.start_refusal() == &"dead" and not _tp.try_start(), "no cast while dead")
	RunState.seed_override = 0


func _test_trial_and_cleanup() -> void:
	RunState.seed_override = TELEPORT_SEED
	await _load(DUNGEON_SCENE)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_tp = _dungeon.home_teleport
	_tp_cancels.clear()
	_tp.cast_cancelled.connect(func(reason: StringName) -> void: _tp_cancels.append(reason))
	var run := _dungeon.run_state
	run.add_rewards(0, 5000)
	run.buy_consumable(&"home_teleport")

	# A trial started at the altar during the cast (a real E press).
	var trial := _dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)
	_dungeon.enter_room(trial, _dungeon.entry_door(trial))
	await _ticks(3)
	var room := _dungeon.current_room as SurvivalRoom
	_check(room != null and room.state == Room.State.IDLE, "setup: the Survival trial room waits (IDLE)")
	_mage.global_position = room.altar.global_position + Vector2(0, 30)
	_mage.velocity = Vector2.ZERO
	await _ticks(3)
	_check(_tp.try_start(), "a cast can start in the waiting trial room")
	await _ticks(20)
	await _press(&"interact")
	await _ticks(1)
	_check(room.state == Room.State.COMBAT, "E at the altar starts the trial (room in COMBAT)")
	_check(not _tp.is_busy() and _tp_cancels.back() == &"combat", "the trial start cancels the cast at once (reason %s)" % _tp_cancels.back())
	_check(run.consumable_count(&"home_teleport") == 1, "the item is kept")
	await _ticks(10)
	_check(_effect(&"teleport_ring") == null and _effect(&"teleport_aura") == null, "the cast effects are removed")
	_check(_tp.start_refusal() == &"combat" and not _dungeon.use_home_teleport(), "no new cast during the trial")
	_check(_dungeon.teleport_home(), "setup: a direct teleport request during the trial")
	await _ticks(100)
	_check(_dungeon.current_index == trial and room.state == Room.State.COMBAT and run.consumable_count(&"home_teleport") == 1,
			"no escape from the running trial: still there, item kept")

	# A dash's visuals stay in their room.
	_dungeon.enter_room(_find_idle_room(trial))
	await _recover()
	_mage.try_dash(Vector2.RIGHT)
	await _ticks_until(func() -> bool: return not _mage.is_dashing())
	_check(_find(DashTrail) != null and _count_afterimages() > 0, "setup: trail and afterimages still fading after the dash")
	_dungeon.enter_room(_find_idle_room(_dungeon.current_index))
	await process_frame
	_check(_find(DashTrail) == null and _count_afterimages() == 0 and _find_puff() == null, "leaving the room removes the dash visuals")

	# The arrival warp plays in the destination and ends normally ...
	_idle = _find_idle_room(trial)
	await _go_idle()
	_tp.try_start()
	await _ticks_until(func() -> bool: return not _tp.is_busy(), 120)
	await _ticks(1)
	var warp := _dungeon.arrival_effect()
	_check(_dungeon.current_index == _dungeon.start_room and warp != null and _effect(&"teleport_arrive") == warp,
			"the arrival warp plays in the start room")
	var ticks := await _ticks_until(func() -> bool: return _dungeon.arrival_effect() == null, 120)
	_check(ticks >= 40 and ticks <= 60, "it ends after its own duration (%d ticks, 12 frames at 15 FPS)" % ticks)

	# ... and is removed when the Mage leaves before it ends; effects on the Mage stay.
	run.add_rewards(0, 1000)
	run.buy_consumable(&"home_teleport")
	run.buy_consumable(&"health_potion")
	await _go_idle()
	_tp.try_start()
	await _ticks_until(func() -> bool: return not _tp.is_busy(), 120)
	await _ticks(5)
	_check(_dungeon.arrival_effect() != null, "setup: a second warp is playing")
	_mage.take_damage(_mage.health.max_health * 0.5 / _mage.damage_taken_multiplier)
	_dungeon.use_health_potion()
	var heal := _mage.get_children().filter(func(n: Node) -> bool: return n is PixelEffect and not n.is_queued_for_deletion())
	_dungeon.enter_room(_find_idle_room(_dungeon.start_room))
	await process_frame
	_check(_dungeon.arrival_effect() == null and _effect(&"teleport_arrive") == null, "leaving early removes the warp; none shows in the next room")
	_check(heal.size() == 1 and is_instance_valid(heal[0]) and not heal[0].is_queued_for_deletion(),
			"the heal effect on the Mage keeps playing through the room change")
	RunState.seed_override = 0


## Starts a cast in the calm room, runs `action` and checks it cancels with
## `reason`, keeps the item and does not teleport.
func _cancel_case(reason: StringName, action: Callable) -> void:
	await _recover()
	await _go_idle()
	var count := _dungeon.run_state.consumable_count(&"home_teleport")
	var completed := _tp_completed
	var room := _dungeon.current_index
	var started := _tp.try_start()
	await _ticks(10)
	var progress := _tp.cast_progress()
	await action.call()
	_check(started and progress > 0.0 and not _tp.is_casting() and _tp_cancels.size() > 0 and _tp_cancels.back() == reason,
			"cancel on %s (reason %s)" % [reason, _tp_cancels.back() if _tp_cancels.size() > 0 else &"none"])
	await _ticks(100)
	_check(_dungeon.run_state.consumable_count(&"home_teleport") == count and _tp_completed == completed
			and (_dungeon.current_index == room or reason == &"room_change") and _dungeon.current_index != _dungeon.start_room,
			"%s: item kept, no teleport" % reason)
	_check(_effect(&"teleport_ring") == null and _effect(&"teleport_aura") == null, "%s: cast effects removed" % reason)
	_dungeon.victory = false
	_mage.health.increase_max_health(0.0, _mage.health.max_health)


## Enters the calm test room (no door, so its encounter does not start) and
## stands still in it.
func _go_idle() -> void:
	Input.action_release(&"move_right")
	Input.action_release(&"attack")
	_dungeon.enter_room(_idle)
	_mage.velocity = Vector2.ZERO
	await _ticks(3)


## First room that is not home, the boss room or `except` and whose encounter
## is not running.
func _find_idle_room(except: int) -> int:
	for i in _dungeon.rooms.size():
		if i == _dungeon.start_room or i == except or i == _dungeon.boss_index():
			continue
		if _dungeon.is_visited(i) and _dungeon._get_room(i).state == Room.State.COMBAT:
			continue
		return i
	return -1


## Enters rooms through their doors until one starts its encounter.
func _find_combat_room() -> int:
	for i in _dungeon.rooms.size():
		if i == _dungeon.start_room or i == _dungeon.boss_index():
			continue
		_dungeon.enter_room(i, _dungeon.entry_door(i))
		await _ticks(2)
		if _dungeon.current_room.state == Room.State.COMBAT:
			return i
	return -1


## The live cast/arrival effect `id` in the Dungeon, or null.
func _effect(id: StringName) -> PixelEffect:
	for node in _dungeon.get_children():
		if node is PixelEffect and (node as PixelEffect).sheet == EffectLibrary.sheet(id) and not node.is_queued_for_deletion():
			return node
	return null


# --- Helpers ----------------------------------------------------------------------

## Waits for the cooldown, so the next test can dash.
func _recover() -> void:
	_mage.resume_run()
	await _ticks_until(func() -> bool: return _mage.dash_ready() and not _mage.is_dashing() and not _mage.is_dash_invulnerable(), 400)


func _place(pos: Vector2) -> void:
	_mage.global_position = pos
	_mage.velocity = Vector2.ZERO


func _clear_effects() -> void:
	for node in _mage.get_parent().get_children():
		if node is PixelEffect or node is DashTrail or node.is_in_group(Mage.AFTERIMAGE_GROUP):
			node.free()


func _find(type: Variant) -> Node:
	for node in _mage.get_parent().get_children():
		if is_instance_of(node, type) and not node.is_queued_for_deletion():
			return node
	return null


func _find_puff() -> PixelEffect:
	for node in _mage.get_parent().get_children():
		if node is PixelEffect and (node as PixelEffect).sheet == EffectLibrary.sheet(&"dash_puff") and not node.is_queued_for_deletion():
			return node
	return null


func _count_afterimages() -> int:
	var count := 0
	for node in get_nodes_in_group(Mage.AFTERIMAGE_GROUP):
		if not node.is_queued_for_deletion():
			count += 1
	return count


func _load(path: String) -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(path)
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await physics_frame
	await _ticks(2)


func _press(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await _ticks(1)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event(release)


## Until after the next frame's _process (process_frame fires before it).
func _redraw() -> void:
	await process_frame
	await process_frame


## Waits two process frames and returns the Mage's dash cooldown ratio as the
## DashBar last read it. Code resumed by process_frame runs before the nodes'
## _process() of that frame, so the bar shows the value of the previous frame;
## a frame may also hold 0..N physics ticks. Sampling at the previous frame
## matches the bar's own read exactly, whatever the tick count.
func _bar_sample() -> float:
	await process_frame
	var seen := _mage.dash_cooldown_ratio()
	await process_frame
	return seen


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


## Physics ticks until `condition` holds (at most `max_ticks`).
func _ticks_until(condition: Callable, max_ticks: int = 240) -> int:
	var ticks := 0
	while not condition.call() and ticks < max_ticks:
		await physics_frame
		ticks += 1
	return ticks


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
