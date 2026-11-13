extends SceneTree
## Headless check of Issue #58 Stage 2: CombatFeedback (damage numbers incl.
## crits and stacking, float text, bursts, trauma screen shake with decay, cap,
## setting and pause, cleanup), CoinPickup (magnet flight, exactly-once
## collection, no collection for a dead / freed target, frozen while paused) and
## the Dungeon wiring (enemy hit numbers, crit marks, kill XP float + coins with
## unchanged gold, Mage hit numbers, level-up and reward banner, HUD pulse,
## room-change cleanup, stop on death, Fire Ball crit roll).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_combat_feedback.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	await _test_standalone()
	await _test_coins()
	RunState.seed_override = SEED
	change_scene_to_file(SCENE)
	await _wait_for_scene(0)
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
	else:
		await _test_dungeon_wiring()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	CombatFeedback.shake_setting = 0
	quit(1 if _failures > 0 else 0)


func _test_standalone() -> void:
	var cam := Camera2D.new()
	root.add_child(cam)
	var fb := CombatFeedback.new()
	fb.camera = cam
	root.add_child(fb)
	await process_frame
	_check(CombatFeedback.of(fb) == fb, "CombatFeedback.of() finds the instance")

	var normal := fb.damage_number(Vector2(100, 100), 12.4)
	var crit := fb.damage_number(Vector2(100, 100), 18.0, CombatFeedback.Kind.CRIT)
	var hurt := fb.damage_number(Vector2(100, 100), 7.0, CombatFeedback.Kind.PLAYER)
	_check(normal.text == "12" and crit.text == "18!" and hurt.text == "-7", "numbers: rounded, crit marked '!', Mage damage negative")
	_check(crit.get_theme_font_size(&"font_size") > normal.get_theme_font_size(&"font_size")
			and crit.get_theme_color(&"font_color") != normal.get_theme_color(&"font_color"), "crit numbers are larger and gold")
	_check(fb.damage_number(Vector2.ZERO, 0.2).text == "1", "tiny hits still show at least 1")
	var target := Node.new()
	var a := fb.damage_number(Vector2(50, 50), 5, CombatFeedback.Kind.ENEMY, target)
	var b := fb.damage_number(Vector2(50, 50), 5, CombatFeedback.Kind.ENEMY, target)
	var c := fb.damage_number(Vector2(50, 50), 5, CombatFeedback.Kind.ENEMY, target)
	_check(b.position.y < a.position.y - 5.0 and c.position.y < b.position.y - 5.0, "rapid numbers on one target stack upwards")
	target.free()
	var spark := fb.burst(Vector2(10, 10), Color.RED, 6)
	_check(spark != null and spark.emitting and spark.amount == 6, "burst emits a one-shot particle burst")
	await _seconds(fb.number_time + 0.6)
	_check(fb.get_child_count() == 0, "popups and bursts free themselves (%d left)" % fb.get_child_count())

	# Shake: trauma per tier, cap, decay, camera offset, setting.
	fb.shake(CombatFeedback.Shake.LIGHT)
	_check(is_equal_approx(fb.trauma, fb.shake_light), "LIGHT adds its trauma")
	# Sample the offset directly (a single long headless frame could decay it first).
	var light := fb.shake_offset().round()
	_check(light.length() >= 1.0 and light.length() <= fb.max_shake_offset * fb.shake_light + 1.0,
			"a lone LIGHT shake is visible but small (%s)" % light)
	for i in 5:
		fb.shake(CombatFeedback.Shake.HEAVY)
	_check(is_equal_approx(fb.trauma, 1.0), "trauma is capped at 1")
	await process_frame
	await process_frame
	_check(cam.offset != Vector2.ZERO and cam.offset.length() <= fb.max_shake_offset + 1.0
			and cam.offset == cam.offset.round(), "shake moves the camera offset, whole pixels, within max (%s)" % cam.offset)
	paused = true
	var held := fb.trauma
	await _seconds(0.2)
	_check(is_equal_approx(fb.trauma, held) and cam.offset == Vector2.ZERO,
			"while paused the shake holds its trauma and the camera is centred (menus never sit on an offset)")
	paused = false
	await _seconds(1.0 / fb.shake_decay + 0.2)
	_check(fb.trauma == 0.0 and cam.offset == Vector2.ZERO, "shake decays back to a still camera")
	CombatFeedback.shake_setting = 2
	fb.shake(CombatFeedback.Shake.HEAVY)
	await process_frame
	_check(CombatFeedback.shake_label() == "Off" and cam.offset == Vector2.ZERO, "shake setting Off keeps the camera still")
	_check(CombatFeedback.cycle_shake_setting() == "Full", "the setting cycles back to Full")
	fb.shake(CombatFeedback.Shake.NONE)

	fb.stop()
	_check(not fb.active and fb.damage_number(Vector2.ZERO, 5) == null and fb.float_text(Vector2.ZERO, "x", Color.WHITE) == null,
			"stop(): no new popups")
	fb.shake(CombatFeedback.Shake.HEAVY)
	_check(fb.trauma == 0.0, "stop(): no new shake")
	fb.queue_free()
	cam.queue_free()
	await process_frame
	_check(CombatFeedback.of(root) == null, "no CombatFeedback left -> helpers are null-safe")
	CombatFeedback.shake_from(root, CombatFeedback.Shake.HEAVY)
	CombatFeedback.mark_crit(null)


func _test_coins() -> void:
	var fb := CombatFeedback.new()
	root.add_child(fb)
	var target := Node2D.new()
	target.position = Vector2(330, 300)  # within the 170 px magnet radius
	root.add_child(target)
	await process_frame
	var coins := fb.drop_coins(Vector2(200, 300), 23, target)
	_check(coins.size() == 5, "23 gold drops 5 coins (5 gold each, rounded up)")
	_check(fb.drop_coins(Vector2.ZERO, 999, target).size() == fb.max_coins_per_drop, "coins per drop are capped")
	for coin in fb.coins():
		if not coins.has(coin):
			coin.free()
	var got := [0]
	for coin in coins:
		coin.collected.connect(func() -> void: got[0] += 1)
	paused = true
	var start := coins[0].global_position
	await _seconds(0.3)
	_check(coins[0].global_position == start, "coins freeze while paused")
	paused = false
	await _seconds(0.6)
	_check(coins.all(func(c: CoinPickup) -> bool: return not is_instance_valid(c) or c.is_attracting() or c.is_collected()),
			"coins within the magnet radius fly to the target")
	await _seconds(1.5)
	_check(got[0] == 5 and fb.coins().is_empty(), "every coin is collected exactly once (%d)" % got[0])

	# Far target: the auto-attract delay still pulls coins in smoothly (no teleport).
	target.position = Vector2(2000, 300)
	var far := fb.drop_coins(Vector2(200, 300), 5, target)[0]
	var last := far.global_position
	var max_step := 0.0
	for i in 40:
		await process_frame
		if not is_instance_valid(far):
			break
		max_step = maxf(max_step, far.global_position.distance_to(last))
		last = far.global_position
	_check(max_step <= far.max_speed / 30.0 + 1.0, "coin movement is smooth (largest step %.1f px)" % max_step)
	if is_instance_valid(far):
		var once := [0]
		far.collected.connect(func() -> void: once[0] += 1)
		far._collect()
		far._collect()
		_check(once[0] == 1 and far.is_collected(), "a double collect fires once")

	# Freed target: coins fade out uncollected.
	var gone := [0]
	var lost := fb.drop_coins(Vector2(200, 300), 10, target)
	for coin in lost:
		coin.collected.connect(func() -> void: gone[0] += 1)
	target.queue_free()
	await _seconds(0.6)
	_check(gone[0] == 0 and fb.coins().all(func(c: CoinPickup) -> bool: return not lost.has(c) or c.modulate.a < 1.0),
			"coins for a freed target are never collected")
	fb.queue_free()
	await process_frame


func _test_dungeon_wiring() -> void:
	var fb := _dungeon.feedback
	var cam := _dungeon.get_node_or_null(^"Camera") as Camera2D
	_check(fb != null and cam != null and fb.camera == cam and cam.anchor_mode == Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
			and cam.offset == Vector2.ZERO, "Dungeon has a top-left Camera2D (unchanged framing) and CombatFeedback")
	_check(is_equal_approx(_mage.caster.crit_chance, RunState.CRIT_CHANCE) and is_equal_approx(_mage.caster.crit_multiplier, RunState.CRIT_MULTIPLIER),
			"the Mage's caster gets the run's crit chance")
	# Crit roll on the projectile.
	_mage.caster.crit_chance = 1.0
	await _wait_until(_mage.caster.can_cast)
	var p := _mage.caster.try_cast(_mage.global_position + Vector2(200, 0))
	_check(p != null and is_equal_approx(p.crit_multiplier, RunState.CRIT_MULTIPLIER), "a crit roll makes the projectile critical")
	if p:
		p.queue_free()
	_mage.caster.crit_chance = 0.0
	await _wait_until(_mage.caster.can_cast)
	p = _mage.caster.try_cast(_mage.global_position + Vector2(200, 0))
	_check(p != null and is_equal_approx(p.crit_multiplier, 1.0), "no crit chance: normal projectile")
	if p:
		p.queue_free()
	_mage.caster.crit_chance = RunState.CRIT_CHANCE

	# Enemy hits and kills in a combat room.
	var index := _first_combat_room()
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(3)
	var room := _dungeon.current_room
	var enemies := _enemies(room)
	_check(enemies.size() >= 2, "combat room has enemies")
	var enemy := enemies[0] as Enemy
	enemy.take_damage(3.0)
	await process_frame
	_check(_labels(fb).any(func(l: Label) -> bool: return l.text == str(roundi(3.0 * enemy.damage_taken_multiplier))),
			"an enemy hit shows its damage number")
	CombatFeedback.mark_crit(enemy)
	enemy.take_damage(4.0)
	await process_frame
	_check(_labels(fb).any(func(l: Label) -> bool: return l.text.ends_with("!")) and not enemy.has_meta(CombatFeedback.CRIT_META),
			"a marked hit shows a crit number and clears the mark")
	var before_count := _labels(fb).size()
	fb.track_enemy(enemy)
	enemy.take_damage(1.0)
	await process_frame
	_check(_labels(fb).size() == before_count + 1, "tracking an enemy twice still shows one number per hit")
	# End to end: a critical projectile deals x1.5 to an Enemy.
	var other := enemies[1] as Enemy
	_mage.caster.crit_chance = 1.0
	await _wait_until(_mage.caster.can_cast)
	var crit_shot := _mage.caster.try_cast(_mage.global_position + Vector2(200, 0))
	_mage.caster.crit_chance = RunState.CRIT_CHANCE
	var hp := other.health.current
	crit_shot._on_body_entered(other)
	var expected := crit_shot.spell.damage * crit_shot.damage_factor * RunState.CRIT_MULTIPLIER * other.damage_taken_multiplier
	_check(is_equal_approx(hp - other.health.current, minf(expected, hp)) and not other.has_meta(CombatFeedback.CRIT_META),
			"a critical Fire Ball deals x%.1f damage (%.1f) and leaves no crit mark" % [RunState.CRIT_MULTIPLIER, hp - other.health.current])
	await process_frame
	var gold_before := _run.currency
	var xp_reward := enemy.xp_reward
	enemy.take_damage(999999.0)
	await _frames(2)
	var gold := _run.currency - gold_before
	_check(gold > 0 and fb.coins().size() == clampi(ceili(gold / 5.0), 1, fb.max_coins_per_drop),
			"a kill drops coins for the gold granted (%d gold)" % gold)
	_check(xp_reward <= 0 or _labels(fb).any(func(l: Label) -> bool: return l.text.begins_with("+") and l.text.ends_with("XP")),
			"a kill floats its XP")
	await _seconds(2.0)
	_check(fb.coins().is_empty() and _run.currency == gold_before + gold, "coins reach the Mage; gold is counted exactly once")

	# Mage hit.
	_mage.take_damage(5.0)
	await process_frame
	_check(_labels(fb).any(func(l: Label) -> bool: return l.text == "-%d" % roundi(5.0 * _mage.damage_taken_multiplier)),
			"a Mage hit shows a red damage number")

	# Level-up and HUD pulse.
	var hud := _dungeon.get_node(^"RunHud") as RunHud
	_run.add_rewards(_run.xp_to_next_level(), 0)
	await process_frame
	_check(_labels(fb).any(func(l: Label) -> bool: return l.text.begins_with("LEVEL UP")), "level-up floats LEVEL UP")
	_check((hud.get_node(^"%RunLabel") as Label).modulate != Color.WHITE, "the HUD level line pulses on a level-up")

	# Valuable reward banner.
	_run.collect_item(&"swift_boots")
	await process_frame
	_check(hud.reward_text().contains("Swift Boots") and hud.reward_text().contains("Rare"), "an item shows a Rare reward banner (%s)" % hud.reward_text())
	_check((hud.get_node(^"%MessageLabel") as Label).text.contains("Swift Boots"), "the plain message text is kept for the banner event")

	# Room change clears everything.
	fb.damage_number(Vector2(300, 300), 9)
	fb.shake(CombatFeedback.Shake.HEAVY)
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(2)
	_check(fb.get_child_count() == 0 and fb.trauma == 0.0 and cam.offset == Vector2.ZERO, "a room change clears popups, coins and shake")

	# Death stops feedback.
	_mage.take_damage(999999.0)
	await _frames(2)
	_check(not fb.active and fb.get_child_count() == 0, "Mage death stops all feedback")


func _first_combat_room() -> int:
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if i != _dungeon.start_room and not spec.is_boss and not spec.is_treasure() and not spec.enemies.is_empty() \
				and not _dungeon.miniboss_room_indexes().has(i) and spec.required_level <= 1:
			return i
	return -1


func _labels(fb: CombatFeedback) -> Array:
	return fb.get_children().filter(func(n: Node) -> bool: return n is Label and not n.is_queued_for_deletion())


func _enemies(room: Room) -> Array:
	return room.get_node(^"Enemies").get_children().filter(func(n: Node) -> bool: return n is Enemy and not n.is_queued_for_deletion())


func _wait_for_scene(old_id: int) -> void:
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	if _dungeon:
		_mage = _dungeon.mage
		_run = _dungeon.run_state


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


func _seconds(s: float) -> void:
	await create_timer(s, true).timeout


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
