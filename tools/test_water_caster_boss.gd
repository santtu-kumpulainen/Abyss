extends SceneTree
## Headless check of Issue #51 Stage 2: the WaveHazard (telegraph, one hit per
## wave, slow, Dash invulnerability, cleanup), the Mage slow (refresh without
## stacking, walking only, never the dash) and the Water Caster miniboss in a
## real Dungeon miniboss room: the big bolt (locked lane, size, flies to the
## wall, impact, one hit), staggered zones (distinct eruption times, a reachable
## safe spot, one hit), the arena wave (lane, telegraph >= 1.2 s, not while its
## zones wait, damage + slow, dodged by stepping out or dashing through),
## behaviour tiers, scaling that never shortens telegraphs, and cleanup on
## death and room unload.
## Stage 2b: wall bounces (exact sequence in a small walled arena, lifetime and
## bounds cleanup), the Water Caster in the Dungeon roster with its level tier
## applied by the Dungeon, a full unscripted encounter in a real Dungeon room
## (all three attacks occur and draw above the room floor), and the user's
## scenes/test/combat_test.tscn run as-is (hazards above its floor, wave lane on
## its floor). Attack-specific checks still force the caster into a room and
## start attacks themselves.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_water_caster_boss.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const COMBAT_TEST := "res://scenes/test/combat_test.tscn"
const BOSS_SCENE := "res://scenes/enemies/water_caster_boss.tscn"
const REGULAR_BOLT := "res://scenes/spells/water_bolt/water_bolt.tres"
const REGULAR_CASTER := "res://scenes/enemies/water_caster.tscn"
const SEED := 31337
const TICK := 1.0 / 60.0


class Dummy extends Node2D:
	var taken := 0.0
	var hits := 0
	var slows: Array = []
	var dash_invulnerable := false

	func take_damage(amount: float) -> void:
		taken += amount
		hits += 1

	func apply_slow(factor: float, duration: float) -> void:
		slows.append([factor, duration])

	func is_dash_invulnerable() -> bool:
		return dash_invulnerable


var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _boss_scene: PackedScene


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	var prog := ProgressionStore.instance(self)
	if prog:
		prog.clear_progress()
	_boss_scene = load(BOSS_SCENE)
	_check(_boss_scene != null, "water_caster_boss.tscn loads")
	_test_look()
	await _test_wave_hazard()
	await _test_bounce_arena()
	RunState.seed_override = SEED
	await _load()
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
	else:
		await _test_unscripted_encounter()
		await _load()
		await _test_level_tier_from_dungeon()
		await _load()
		await _test_mage_slow()
		await _load()
		await _test_bolt()
		await _load()
		await _test_zones()
		await _load()
		await _test_wave()
		await _load()
		await _test_wave_dash()
		_test_tiers()
		await _load()
		await _test_followup_and_cleanup()
		await _load()
		await _test_room_unload()
		await _test_combat_test_scene()
	RunState.seed_override = 0
	if prog:
		prog.clear_progress()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- WaveHazard --------------------------------------------------------------------

func _test_wave_hazard() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var inside := Dummy.new()
	var outside := Dummy.new()
	for d in [inside, outside]:
		d.add_to_group(&"player")
		arena.add_child(d)
	var lane := Rect2(0, 100, 1000, 200)
	inside.global_position = Vector2(600, 200)
	outside.global_position = Vector2(600, 320)
	var wave := WaveHazard.spawn(arena, lane, Vector2.RIGHT, 1.4, 500.0, 12.0, 0.6, 2.5)
	var done := [false]
	wave.finished.connect(func() -> void: done[0] = true)
	_check(wave.lane_contains(inside.global_position) and not wave.lane_contains(outside.global_position),
			"wave: the telegraphed lane is exactly the swept area")
	_check(wave.time_to_reach(inside.global_position) >= 1.2 + 600.0 / 500.0 - 0.01,
			"wave: reaction time = telegraph + travel (%.2fs)" % wave.time_to_reach(inside.global_position))
	await _physics(1.3)
	_check(inside.hits == 0 and wave.phase == WaveHazard.Phase.TELEGRAPH, "wave: harmless during its telegraph")
	await _physics(0.1 + 600.0 / 500.0 + 0.1)
	_check(inside.hits == 1 and is_equal_approx(inside.taken, 12.0) and outside.hits == 0,
			"wave: the front hits a target in the lane once, not one outside it")
	_check(inside.slows.size() == 1 and is_equal_approx(inside.slows[0][0], 0.6) and is_equal_approx(inside.slows[0][1], 2.5),
			"wave: a hit slows (x0.6 for 2.5 s)")
	await _wait_until(func() -> bool: return done[0], 200)
	await _frames(1)
	_check(inside.hits == 1 and done[0] and not is_instance_valid(wave), "wave: never hits twice, then finishes and frees itself")

	# Dash invulnerability while the front passes: no hit, no slow, not even afterwards.
	var dasher := Dummy.new()
	dasher.add_to_group(&"player")
	arena.add_child(dasher)
	dasher.global_position = Vector2(100, 200)
	dasher.dash_invulnerable = true
	inside.hits = 0
	inside.global_position = Vector2(900, 200)
	var wave2 := WaveHazard.spawn(arena, lane, Vector2.RIGHT, 0.2, 500.0, 12.0, 0.6, 2.5)
	await _physics(0.2 + 300.0 / 500.0)
	dasher.dash_invulnerable = false
	await _wait_gone(wave2, 200)
	_check(dasher.hits == 0 and dasher.slows.is_empty() and inside.hits == 1,
			"wave: a dash-invulnerable target the front passes is not hit or slowed")

	# Fast front (more than its thickness per tick): still no tunnelling.
	inside.hits = 0
	inside.global_position = Vector2(500, 200)
	var fast := WaveHazard.spawn(arena, lane, Vector2.LEFT, 0.05, 9000.0, 5.0, 0.6, 2.5)
	await _wait_gone(fast, 60)
	_check(inside.hits == 1, "wave: a very fast front still hits once (swept per tick)")

	# Cleanup: the source dying / leaving, and the room being unloaded.
	var source := Node2D.new()
	source.add_user_signal(&"died")
	arena.add_child(source)
	var owned := WaveHazard.spawn(arena, lane, Vector2.DOWN, 5.0, 500.0, 5.0, 0.6, 2.5, source)
	source.emit_signal(&"died")
	await _frames(1)
	_check(not is_instance_valid(owned), "wave: cleared when its source dies")
	var room := Node2D.new()
	arena.add_child(room)
	var unloaded := WaveHazard.spawn(room, lane, Vector2.UP, 5.0, 500.0, 5.0, 0.6, 2.5)
	arena.remove_child(room)
	await _frames(1)
	_check(not is_instance_valid(unloaded), "wave: freed when its room leaves the tree")
	room.free()
	arena.queue_free()
	await _frames(1)


# --- Look -------------------------------------------------------------------------

## The boss is the regular Water Caster's giant version: same sprite frames and
## animations, the same blue tint family (deeper), and clearly bigger.
func _test_look() -> void:
	var regular := (load(REGULAR_CASTER) as PackedScene).instantiate() as Enemy
	var boss := _boss_scene.instantiate() as WaterCasterBoss
	var reg_sprite := regular.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	var boss_sprite := boss.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	_check(boss.sprite_frames != null and boss.sprite_frames == regular.sprite_frames and boss_sprite.sprite_frames == reg_sprite.sprite_frames,
			"look: uses the regular Water Caster's SpriteFrames (%s)" % boss.sprite_frames.resource_path)
	_check(boss.sprite_frames.has_animation(&"idle") and boss.sprite_frames.has_animation(&"walk") and boss.side_view == regular.side_view,
			"look: idle and walk animations, side view like the regular caster")
	var reg_tint := reg_sprite.self_modulate
	var boss_tint := boss_sprite.self_modulate
	_check(absf(boss_tint.h - reg_tint.h) < 0.04 and boss_tint.b >= reg_tint.b and boss_tint.r <= reg_tint.r,
			"look: the regular caster's blue tint, deeper (%s vs %s)" % [boss_tint, reg_tint])
	var ratio := boss.sprite_scale / regular.sprite_scale
	_check(ratio >= 1.6 and is_equal_approx(boss_sprite.scale.x, boss.sprite_scale),
			"look: a giant version, %.2fx the regular caster's size (%.1f vs %.1f)" % [ratio, boss.sprite_scale, regular.sprite_scale])
	regular.free()
	boss.free()


# --- Projectile bounces ------------------------------------------------------------

## A 400 x 200 box of walls: the big bolt bounces off exactly 2 walls, reflected,
## then the third wall ends it with one impact. Bounds and lifetime end it too.
func _test_bounce_arena() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	for rect: Rect2 in [Rect2(-20, -20, 440, 20), Rect2(-20, 200, 440, 20), Rect2(-20, 0, 20, 200), Rect2(400, 0, 20, 200)]:
		var wall := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		wall.add_child(shape)
		arena.add_child(wall)
		wall.global_position = rect.get_center()
	var caster := _boss_scene.instantiate() as WaterCasterBoss
	var bolt := caster.projectile.duplicate() as Spell
	caster.free()
	var effects := [0, 0]
	arena.child_entered_tree.connect(func(n: Node) -> void:
		if n is PixelEffect:
			effects[0 if (n as PixelEffect).sheet == bolt.impact_effect else 1] += 1)
	await physics_frame
	var shot := bolt.projectile_scene.instantiate() as Projectile
	shot.setup(bolt, Vector2.RIGHT, null)
	arena.add_child(shot)
	shot.global_position = Vector2(200, 100)
	var dirs: Array[Vector2] = []
	shot.bounced.connect(func(_at: Vector2) -> void: dirs.append(shot.direction))
	await _wait_gone(shot, 600)
	_check(dirs.size() == 2 and dirs[0].is_equal_approx(Vector2.LEFT) and dirs[1].is_equal_approx(Vector2.RIGHT)
			and effects[1] == 2 and effects[0] == 1,
			"bounces: off exactly 2 walls (reflected, a splash each), the third wall ends it with one impact (%s)" % [dirs])

	# Leaving its bounds (e.g. through an open doorway) ends it with its impact.
	effects[0] = 0
	var stray := bolt.projectile_scene.instantiate() as Projectile
	stray.setup(bolt, Vector2.DOWN, null)
	stray.bounds = Rect2(150, 50, 100, 30)
	arena.add_child(stray)
	stray.global_position = Vector2(200, 60)
	var stray_id := stray.get_instance_id()
	await _physics((20.0 + Projectile.BOUNDS_MARGIN + 20.0) / bolt.speed)
	_check(_gone(stray_id) and effects[0] == 1, "bounces: a bolt leaving its bounds is removed, with its impact")

	# The lifetime cap always ends it, bounces left or not.
	var short := bolt.duplicate() as Spell
	short.lifetime = 0.5
	var capped := short.projectile_scene.instantiate() as Projectile
	capped.setup(short, Vector2.RIGHT, null)
	arena.add_child(capped)
	capped.global_position = Vector2(200, 100)
	var capped_id := capped.get_instance_id()
	await _physics(0.55)
	_check(_gone(capped_id), "bounces: the lifetime cap ends it")
	arena.queue_free()
	await _frames(1)


# --- Normal Dungeon encounter (no test overrides on the caster) ---------------------

## Enters a planned Water Caster room the normal way and lets the fight run: the
## caster picks its own attacks. All three must occur, their hazards must sit
## in the room above its floor, and its level tier must come from the Dungeon.
func _test_unscripted_encounter() -> void:
	_check(_dungeon.miniboss_scenes.any(func(sc: PackedScene) -> bool: return sc.resource_path == BOSS_SCENE)
			and _dungeon.miniboss_scenes.size() == 3, "roster: Brood Mother, Hexcaller and Water Caster")
	var index := _planned_caster_room()
	_check(index >= 0, "roster: level 1 plans a Water Caster room (3 rooms, 3 types)")
	if index < 0:
		return
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	var room := _dungeon.current_room
	var boss := _caster_in(room)
	_check(boss != null and boss.behaviour_tier == 1 and boss._tier_applied, "encounter: the Dungeon applied level tier 1")
	if boss == null:
		return
	var floor_z := _effective_z(room.get_node(^"Visuals"))
	var area := boss.floor_rect()
	var seen := {}
	var kinds := {"zone": 0, "wave": 0, "burst": 0}
	var bad_z: Array[String] = []
	var lanes_ok := [true]
	boss.attack_started.connect(func(a: StringName) -> void: seen[a] = true)
	# Checked once the node is ready (z_index and lane are set by then).
	room.child_entered_tree.connect(func(n: Node) -> void:
		if not (n is FloorHazard or n is WaveHazard or n is FloorHazard.Burst):
			return
		await physics_frame
		if not is_instance_valid(n):
			return
		kinds["zone" if n is FloorHazard else ("wave" if n is WaveHazard else "burst")] += 1
		if _effective_z(n) <= floor_z:
			bad_z.append("%s z %d" % [n.get_class(), _effective_z(n)])
		if n is WaveHazard:
			lanes_ok[0] = lanes_ok[0] and area.grow(1.0).encloses((n as WaveHazard).lane))
	var centre := area.get_center()
	var sprite := boss.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	var anims := {}
	var ticks := 0
	while ticks < 60 * 45 and not (seen.has(&"bolt") and seen.has(&"zones") and seen.has(&"wave") and anims.has(&"walk")):
		anims[sprite.animation] = true
		# The Mage keeps moving around the room centre and is kept alive.
		_mage.global_position = centre + Vector2(220, 0).rotated(ticks * 0.01)
		_mage.health.current = _mage.health.max_health
		await physics_frame
		ticks += 1
	_check(seen.has(&"bolt") and seen.has(&"zones") and seen.has(&"wave"),
			"encounter: the caster uses all three attacks on its own (%s in %.1f s)" % [seen.keys(), ticks / 60.0])
	_check(anims.has(&"walk") and anims.has(&"idle"), "encounter: walk while repositioning, idle while casting (%s)" % [anims.keys()])
	# Let the last zones erupt (their bursts) before checking what was created.
	await _physics(boss.zone_delay + boss.zone_stagger * boss.zone_count + 0.2)
	_check(kinds["zone"] > 0 and kinds["wave"] > 0 and kinds["burst"] > 0,
			"encounter: zones, a wave and zone eruption bursts were created in the room (%d / %d / %d)" % [kinds["zone"], kinds["wave"], kinds["burst"]])
	_check(bad_z.is_empty(), "encounter: every hazard draws above the room floor (floor z %d) %s" % [floor_z, bad_z])
	_check(lanes_ok[0], "encounter: the wave lane lies on the room floor")


## The Dungeon gives the caster the behaviour tier of the dungeon level (level 3: tier 3).
func _test_level_tier_from_dungeon() -> void:
	_dungeon.run_state.dungeon_level = 3
	_dungeon._plan_level()
	var index := _planned_caster_room()
	_check(index >= 0, "tier: level 3 plans a Water Caster room")
	if index >= 0:
		_dungeon.enter_room(index, _dungeon.entry_door(index))
		await _frames(2)
		var boss := _caster_in(_dungeon.current_room)
		_check(boss != null and boss.behaviour_tier == 3 and boss.zone_count == 5 and boss.bolt_burst == 2 and boss.wave_followup_zones == 2,
				"tier: on dungeon level 3 the Dungeon sets tier 3 (5 zones, 2-bolt burst, zones after the wave)")
	_dungeon.run_state.dungeon_level = 1


## The user's test scene, unmodified: zones and the wave must be visible above
## the TestRoom floor, and the wave lane must lie on that floor.
func _test_combat_test_scene() -> void:
	var old_id := current_scene.get_instance_id()
	change_scene_to_file(COMBAT_TEST)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	var scene := current_scene
	var boss: WaterCasterBoss = null
	for n in scene.get_children():
		if n is WaterCasterBoss:
			boss = n
	var mage := scene.get_node_or_null(^"Mage") as Mage
	var floor_node := scene.get_node_or_null(^"TestRoom/Floor") as Control
	_check(boss != null and mage != null and floor_node != null, "combat_test: Water Caster, Mage and TestRoom floor present")
	if boss == null or mage == null or floor_node == null:
		return
	_check(boss.floor_rect() == floor_node.get_global_rect(), "combat_test: the caster fights on the TestRoom floor %s" % floor_node.get_global_rect())
	var floor_z := _effective_z(floor_node)
	var area := floor_node.get_global_rect()
	var counts := {"zone": 0, "wave": 0}
	var problems: Array[String] = []
	scene.child_entered_tree.connect(func(n: Node) -> void:
		if not (n is FloorHazard or n is WaveHazard):
			return
		# spawn() places the node right after adding it: check on the next tick.
		await physics_frame
		if not is_instance_valid(n):
			return
		counts["zone" if n is FloorHazard else "wave"] += 1
		if _effective_z(n) <= floor_z:
			problems.append("%s under the floor" % n.get_class())
		if n is WaveHazard and not area.grow(1.0).encloses((n as WaveHazard).lane):
			problems.append("wave lane %s off the floor" % (n as WaveHazard).lane)
		if n is FloorHazard and not area.has_point((n as Node2D).global_position):
			problems.append("zone at %s off the floor" % (n as Node2D).global_position))
	var ticks := 0
	while ticks < 60 * 30 and not (counts["zone"] > 0 and counts["wave"] > 0):
		mage.health.current = mage.health.max_health
		await physics_frame
		ticks += 1
	_check(counts["zone"] > 0 and counts["wave"] > 0 and problems.is_empty(),
			"combat_test: zones and the wave appear above the TestRoom floor (floor z %d) and lie on it %s" % [floor_z, problems])


func _planned_caster_room() -> int:
	for i in _dungeon.miniboss_room_indexes():
		if _dungeon.miniboss_pair(i).size() == 1 and _dungeon.miniboss_scene(i) and _dungeon.miniboss_scene(i).resource_path == BOSS_SCENE:
			return i
	return -1


func _caster_in(room: Room) -> WaterCasterBoss:
	for e in room.get_node(^"Enemies").get_children():
		if e is WaterCasterBoss:
			return e
	return null


## Final z of `node`: the sum of z_index up its relative chain.
func _effective_z(node: Node) -> int:
	var z := 0
	var n := node
	while n:
		if n is CanvasItem:
			z += (n as CanvasItem).z_index
			if not (n as CanvasItem).z_as_relative:
				break
		n = n.get_parent()
	return z


# --- Mage slow ---------------------------------------------------------------------

func _test_mage_slow() -> void:
	var start := _dungeon.current_room.get_node(^"PlayerSpawn") as Node2D
	_mage.global_position = start.global_position
	await _physics(0.1)
	var free_speed := await _walk_speed()
	_mage.apply_slow(0.6, 2.5)
	_check(_mage.is_slowed() and is_equal_approx(_mage.slow_multiplier(), 0.6) and _mage.slow_remaining() == 2.5,
			"slow: x0.6 for 2.5 s")
	var slowed_speed := await _walk_speed()
	_check(is_equal_approx(slowed_speed, free_speed * 0.6), "slow: walking speed x0.6 (%.0f -> %.0f px/s)" % [free_speed, slowed_speed])
	_mage.apply_slow(0.6, 2.5)
	_mage.apply_slow(0.8, 1.0)
	_check(is_equal_approx(_mage.slow_multiplier(), 0.6) and is_equal_approx(_mage.slow_remaining(), 2.5),
			"slow: a repeat hit refreshes, never stacks (x%.2f, %.2fs)" % [_mage.slow_multiplier(), _mage.slow_remaining()])
	_mage.global_position = start.global_position
	await _physics(0.05)
	var before := _mage.global_position
	_check(_mage.try_dash(Vector2.RIGHT), "slow: the Mage can dash while slowed")
	await _wait_until(func() -> bool: return not _mage.is_dashing(), 60)
	_check(absf(_mage.global_position.distance_to(before) - _mage.dash_distance) <= 1.0,
			"slow: the dash distance is not reduced (%.1f px)" % _mage.global_position.distance_to(before))
	await _physics(2.6)
	_check(not _mage.is_slowed() and _mage.slow_multiplier() == 1.0, "slow: wears off after its duration")


## Walking speed measured over a few ticks of held "move_down".
func _walk_speed() -> float:
	var start := _mage.global_position
	Input.action_press(&"move_down")
	await _physics(0.1)
	Input.action_release(&"move_down")
	await physics_frame
	return start.distance_to(_mage.global_position) / 0.1


# --- Water Caster: big bolt --------------------------------------------------------

func _test_bolt() -> void:
	var boss := await _enter_boss()
	if boss == null:
		return
	var regular := load(REGULAR_BOLT) as Spell
	var spell := boss._spell
	_check(spell.collision_radius >= regular.collision_radius * 2.0 and spell.visual_scale >= regular.visual_scale * 2.0,
			"bolt: clearly larger than the regular water bolt (radius %.0f vs %.0f)" % [spell.collision_radius, regular.collision_radius])
	var diagonal := boss.floor_rect().size.length()
	_check(spell.max_bounces == 2 and spell.lifetime <= 6.0 and spell.lifetime * spell.speed > diagonal
			and spell.impact_effect == EffectLibrary.sheet(&"water_impact") and spell.bounce_effect != null,
			"bolt: 2 bounces, a %.0f s lifetime cap, a big water impact and a bounce splash" % spell.lifetime)
	_park(boss, Vector2(300, 0))
	await _physics(0.1)
	var sprite := boss.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	_check(sprite.is_playing() and sprite.animation == &"idle", "look: idles (animated) while standing (%s)" % sprite.animation)
	_check(boss.begin_bolt() and boss.state == Miniboss.State.WINDUP, "bolt: telegraph starts")
	_quiet(boss)
	var aim := boss.bolt_direction()
	await _physics(boss.bolt_windup * 0.8)
	var base := Vector2.ONE * boss.sprite_scale
	_check(sprite.scale.y > base.y * 1.04 and sprite.scale.x < base.x, "look: cast pose stretches the sprite during the windup (%s)" % sprite.scale)
	# The aim is locked: moving during the telegraph does not turn the bolt.
	_mage.global_position += Vector2(0, 160)
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.RECOVER, 200)
	var bolts := _bolts_of(boss)
	_check(bolts.size() == 1 and bolts[0].direction.is_equal_approx(aim), "bolt: fires along the locked, telegraphed lane")
	_check(sprite.scale.is_equal_approx(base), "look: back to normal size after the windup")
	# With the Mage out of the way it bounces off two walls (a splash each,
	# reflected direction, still inside the floor), then the third wall ends it.
	var shot: Projectile = bolts[0]
	_mage.global_position = Vector2(-5000, -5000)
	var impacts := [0]
	var splashes := [0]
	current_scene.child_entered_tree.connect(func(n: Node) -> void:
		if n is PixelEffect and (n as PixelEffect).sheet == spell.impact_effect:
			impacts[0] += 1
		elif n is PixelEffect and (n as PixelEffect).sheet == spell.bounce_effect:
			splashes[0] += 1)
	var bounces: Array = []
	shot.bounced.connect(func(at: Vector2) -> void: bounces.append([at, shot.direction]))
	var floor_rect := boss.floor_rect()
	var inside := [true]
	var age := [0.0]
	var shot_id := shot.get_instance_id()
	await _wait_until(func() -> bool:
		var node := instance_from_id(shot_id) as Projectile
		if node and not node.is_queued_for_deletion():
			age[0] += TICK
			inside[0] = inside[0] and floor_rect.grow(Projectile.BOUNDS_MARGIN).has_point(node.global_position)
			return false
		return true, 600)
	# In a full-size room the 6 s cap usually ends it after 1-2 bounces; the exact
	# 2-bounces-then-wall sequence is checked in a small arena (_test_bounce_arena).
	var reflected := bounces.size() >= 1 and not (bounces[0][1] as Vector2).is_equal_approx(aim)
	_check(_gone(shot_id) and reflected and bounces.size() <= 2 and splashes[0] == bounces.size() and impacts[0] == 1
			and inside[0] and age[0] <= spell.lifetime + TICK,
			"bolt: bounces off the walls (splash each) and ends with one impact within its lifetime (%d bounce(s), %.1f s, stayed in the room)"
			% [bounces.size(), age[0]])

	# A hit damages the Mage once.
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.CHASE, 200)
	_quiet(boss)
	_park(boss, Vector2(260, 0))
	var hp := _mage.health.current
	_check(boss.begin_bolt(), "bolt: second telegraph starts")
	_quiet(boss)
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.RECOVER, 200)
	await _wait_until(func() -> bool: return _bolts_of(boss).is_empty(), 300)
	await _physics(0.2)
	_check(is_equal_approx(hp - _mage.health.current, boss.bolt_damage * _mage.damage_taken_multiplier),
			"bolt: hits the Mage once for its damage (%.1f)" % (hp - _mage.health.current))

	# Tier 2: a 2-shot burst along the same locked lane.
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.CHASE, 200)
	boss.bolt_burst = 2
	_quiet(boss)
	_park(boss, Vector2(0, -320))
	_heal()
	boss.begin_bolt()
	_quiet(boss)
	aim = boss.bolt_direction()
	var fired: Array[Vector2] = []
	var record := func(n: Node) -> void:
		if n is Projectile and (n as Projectile).source == boss:
			fired.append((n as Projectile).direction)
	current_scene.child_entered_tree.connect(record)
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.ACTION, 200)
	_mage.global_position += Vector2(200, 0)
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.RECOVER, 200)
	current_scene.child_entered_tree.disconnect(record)
	_check(fired.size() == 2 and fired.all(func(d: Vector2) -> bool: return d.is_equal_approx(aim)),
			"bolt: a 2-shot burst is fired along the locked lane (%d bolts)" % fired.size())


# --- Water Caster: staggered zones -------------------------------------------------

func _test_zones() -> void:
	var boss := await _enter_boss()
	if boss == null:
		return
	for count in [3, 5]:
		await _wait_until(func() -> bool: return boss.state == Miniboss.State.CHASE, 200)
		boss.zone_count = count
		_quiet(boss)
		_park(boss, Vector2(320, 0))
		_heal()
		var at := _mage.global_position
		_check(boss.begin_zones(), "zones x%d: cast starts" % count)
		_quiet(boss)
		await _wait_until(func() -> bool: return boss.state != Miniboss.State.WINDUP, 200)
		var zones := _hazards_of(boss)
		var delays: Array[float] = []
		for z: FloorHazard in zones:
			delays.append(z.time_to_erupt())
		var unique := {}
		for d in delays:
			unique[snappedf(d, 0.01)] = true
		var first: FloorHazard = zones.reduce(func(a: FloorHazard, b: FloorHazard) -> FloorHazard:
			return a if a.time_to_erupt() <= b.time_to_erupt() else b) if not zones.is_empty() else null
		_check(zones.size() == count and unique.size() == count and first != null and first.global_position.distance_to(at) < 1.0,
				"zones x%d: all active at once, each erupting at a different time, the one on the Mage first" % count)
		_check(delays.min() >= boss.zone_delay - 0.05 and delays.max() - delays.min() >= boss.zone_stagger * (count - 1) - 0.05,
				"zones x%d: staggered over %.1fs after a %.1fs telegraph" % [count, delays.max() - delays.min(), delays.min()])
		# A safe spot is reachable at walking speed before the first eruption.
		_check(_safe_spot_reachable(zones, at, _mage.speed * boss.zone_delay), "zones x%d: a safe spot is reachable in time" % count)
		var hp := _mage.health.current
		await _wait_until(func() -> bool: return _hazards_of(boss).is_empty(), 400)
		_check(is_equal_approx(hp - _mage.health.current, boss.zone_damage * _mage.damage_taken_multiplier),
				"zones x%d: standing on the Mage's zone takes one hit only (%.1f)" % [count, hp - _mage.health.current])


func _safe_spot_reachable(zones: Array, from: Vector2, reach: float) -> bool:
	for r in [80.0, 100.0, 120.0, 140.0]:
		if r > reach:
			continue
		for i in 32:
			var p: Vector2 = from + Vector2.RIGHT.rotated(TAU * i / 32.0) * r
			if zones.all(func(z: FloorHazard) -> bool: return z.global_position.distance_to(p) > z.radius + 10.0):
				return true
	return false


# --- Water Caster: wave ------------------------------------------------------------

func _test_wave() -> void:
	var boss := await _enter_boss()
	if boss == null:
		return
	_park(boss, Vector2(-300, 40))
	var floor_rect := boss.floor_rect()
	# Not while its zones are still waiting to erupt.
	boss.begin_zones()
	_quiet(boss)
	await _wait_until(func() -> bool: return boss.state != Miniboss.State.WINDUP, 200)
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.CHASE, 200)
	_check(not boss.wave_allowed() and not boss.begin_wave(), "wave: never starts while its zones are waiting to erupt")
	_quiet(boss)
	await _wait_until(func() -> bool: return _hazards_of(boss).is_empty(), 400)
	_quiet(boss)
	_heal()
	_park(boss, Vector2(-300, 40))
	_check(boss.begin_wave(), "wave: starts once the zones have erupted")
	_quiet(boss)
	var wave := boss.current_wave()
	_check(wave != null and wave.direction == Vector2.LEFT and is_equal_approx(wave.lane.size.x, floor_rect.size.x)
			and wave.lane.size.y < floor_rect.size.y * 0.8 and wave.lane.size.y >= floor_rect.size.y * 0.4
			and wave.lane_contains(_mage.global_position),
			"wave: a horizontal lane over the whole floor length, %.0f%% of its height, on the Mage, away from the caster"
			% (100.0 * wave.lane.size.y / floor_rect.size.y))
	_check(wave.time_to_sweep() >= 1.2 and wave.time_to_reach(_mage.global_position) >= 1.2,
			"wave: telegraphed for %.1fs before it can hit" % wave.time_to_sweep())
	_check(not boss.begin_bolt() and not boss.begin_zones(), "wave: no other attack starts while it is on the floor")
	_quiet(boss)
	var hp := _mage.health.current
	await _wait_gone(wave, 400)
	_check(is_equal_approx(hp - _mage.health.current, boss.wave_damage * _mage.damage_taken_multiplier) and _mage.is_slowed()
			and is_equal_approx(_mage.slow_multiplier(), boss.wave_slow_factor),
			"wave: one hit (%.1f) and a slow (x%.1f)" % [hp - _mage.health.current, _mage.slow_multiplier()])

	# The next wave goes the other way (vertical); stepping out of the lane avoids it.
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.CHASE, 200)
	_mage.clear_slow()
	_quiet(boss)
	_heal()
	_park(boss, Vector2(0, -200))
	boss.begin_wave()
	_quiet(boss)
	wave = boss.current_wave()
	_check(wave != null and wave.direction == Vector2.UP and is_equal_approx(wave.lane.size.y, floor_rect.size.y)
			and wave.lane.size.x < floor_rect.size.x * 0.8, "wave: the next wave is vertical, towards the Mage")
	var side := Vector2(wave.lane.end.x + 40.0, _mage.global_position.y) if wave.lane.end.x + 40.0 < floor_rect.end.x \
			else Vector2(wave.lane.position.x - 40.0, _mage.global_position.y)
	_mage.global_position = side
	hp = _mage.health.current
	await _wait_gone(wave, 400)
	_check(is_equal_approx(hp, _mage.health.current) and not _mage.is_slowed(), "wave: stepping out of the lane avoids it")


func _test_wave_dash() -> void:
	var boss := await _enter_boss()
	if boss == null:
		return
	_park(boss, Vector2(-300, 0))
	_check(boss.begin_wave(), "wave dash: wave starts")
	_quiet(boss)
	var wave := boss.current_wave()
	var hp := _mage.health.current
	# Dash into the front just before it arrives.
	await _wait_until(func() -> bool: return wave.time_to_reach(_mage.global_position) <= 2.0 * TICK, 400)
	_check(_mage.try_dash(-wave.direction), "wave dash: the Mage dashes into the front")
	await _wait_gone(wave, 400)
	_check(is_equal_approx(hp, _mage.health.current) and not _mage.is_slowed(), "wave dash: dashing through the front avoids the hit and the slow")


# --- Tiers and scaling -------------------------------------------------------------

func _test_tiers() -> void:
	var counts := []
	for level in [1, 2, 3, 6]:
		var b := _boss_scene.instantiate() as WaterCasterBoss
		var base := [b.bolt_cooldown, b.zone_cooldown, b.wave_cooldown]
		b.apply_level_tier(level)
		var factor := 1.0 - b.tier_cooldown_step * (b.behaviour_tier - 1)
		var ok := is_equal_approx(b.bolt_cooldown, base[0] * factor) and is_equal_approx(b.zone_cooldown, base[1] * factor) \
				and is_equal_approx(b.wave_cooldown, base[2] * factor)
		counts.append([b.behaviour_tier, b.zone_count, b.bolt_burst, b.wave_followup_zones, ok])
		b.apply_level_tier(1)
		_check(b.behaviour_tier == clampi(level, 1, 3), "tiers: applying a tier twice changes nothing (level %d)" % level)
		b.free()
	_check(counts == [[1, 3, 1, 0, true], [2, 4, 2, 0, true], [3, 5, 2, 2, true], [3, 5, 2, 2, true]],
			"tiers: L1 3 zones / L2 4 zones + 2-bolt burst / L3+ 5 zones + 2 zones after the wave; cooldowns -10%% per tier %s" % [counts])

	# Scaling (level x difficulty) never shortens a telegraph.
	var s := _boss_scene.instantiate() as WaterCasterBoss
	var tele := [s.bolt_windup, s.zone_windup, s.zone_delay, s.zone_stagger, s.wave_cast, s.wave_telegraph, s.wave_speed]
	var dmg := [s.bolt_damage, s.zone_damage, s.wave_damage, s.wave_cooldown]
	root.add_child(s)
	s.apply_scaling(1.5, 1.4, 1.3, 1.0)
	_check([s.bolt_windup, s.zone_windup, s.zone_delay, s.zone_stagger, s.wave_cast, s.wave_telegraph, s.wave_speed] == tele,
			"scaling: telegraphs, staggers and the wave speed never scale")
	_check(is_equal_approx(s.bolt_damage, dmg[0] * 1.4) and is_equal_approx(s.zone_damage, dmg[1] * 1.4)
			and is_equal_approx(s.wave_damage, dmg[2] * 1.4) and is_equal_approx(s.wave_cooldown, dmg[3] / 1.3)
			and is_equal_approx(s._spell.damage, s.bolt_damage),
			"scaling: damage x1.4 and cooldowns / pace 1.3 for all three attacks")
	s.queue_free()


# --- Follow-up zones and cleanup ---------------------------------------------------

func _test_followup_and_cleanup() -> void:
	var boss := await _enter_boss()
	if boss == null:
		return
	boss.wave_followup_zones = 2
	_park(boss, Vector2(-300, 0))
	boss.begin_wave()
	_quiet(boss)
	var wave := boss.current_wave()
	var lane := wave.lane
	var dir := wave.direction
	await _wait_gone(wave, 400)
	var zones := _hazards_of(boss)
	var far_half := zones.all(func(z: FloorHazard) -> bool:
		return (z.global_position - lane.get_center()).dot(dir) > 0.0 and lane.grow(1.0).has_point(z.global_position))
	_check(zones.size() == 2 and far_half and not is_equal_approx(zones[0].time_to_erupt(), zones[1].time_to_erupt()),
			"tier 3: two staggered zones at the far end of the lane after the wave")

	# Death: zones, the wave and the bolts all go with the caster.
	await _wait_until(func() -> bool: return boss.state == Miniboss.State.CHASE, 200)
	_quiet(boss)
	_park(boss, Vector2(0, -300))
	boss.begin_bolt()
	_quiet(boss)
	await _wait_until(func() -> bool: return not _bolts_of(boss).is_empty(), 200)
	boss.state = Miniboss.State.CHASE
	boss._wave_left = 0.0
	for z in _hazards_of(boss):
		z.queue_free()
	await _frames(1)
	boss.begin_wave()
	_quiet(boss)
	boss._spawn_zone(_mage.global_position + Vector2(0, 200), 5.0)
	_check(boss.current_wave() != null and not _bolts_of(boss).is_empty() and not _hazards_of(boss).is_empty(),
			"cleanup: a wave, a zone and a bolt are out")
	boss.take_damage(boss.health.max_health * 100.0)
	await _frames(2)
	var zones_left := get_nodes_in_group(&"floor_hazards").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var bolts_left := current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile and not n.is_queued_for_deletion())
	_check(get_nodes_in_group(WaveHazard.GROUP).is_empty() and zones_left.is_empty() and bolts_left.is_empty(),
			"cleanup: the caster's death removes its wave, zones and bolts")


func _test_room_unload() -> void:
	var boss := await _enter_boss()
	if boss == null:
		return
	_park(boss, Vector2(-300, 0))
	boss.begin_wave()
	_quiet(boss)
	var wave := boss.current_wave()
	_dungeon.enter_room((_dungeon.current_index + 1) % _dungeon.rooms.size())
	await _frames(2)
	_check(not is_instance_valid(wave) and get_nodes_in_group(WaveHazard.GROUP).is_empty(),
			"cleanup: leaving the room removes the wave")


# --- Helpers -----------------------------------------------------------------------

## Builds a planned miniboss room with the Water Caster miniboss in it, enters
## it and starts the encounter. Returns the caster (its attacks are paused).
func _enter_boss() -> WaterCasterBoss:
	var indexes := _dungeon.miniboss_room_indexes()
	var index := -1
	for i in indexes:
		if _dungeon.miniboss_pair(i).size() == 1:
			index = i
			break
	if index < 0:
		_check(false, "setup: a single miniboss room exists")
		return null
	_dungeon._minibosses[index] = [_boss_scene]
	_dungeon.enter_room(index)
	await _frames(2)
	_dungeon.current_room.start_encounter()
	await _frames(1)
	var boss: WaterCasterBoss = null
	for e in _dungeon.current_room.get_node(^"Enemies").get_children():
		if e is WaterCasterBoss:
			boss = e
	_check(boss != null and boss.display_name == "Water Caster", "setup: Water Caster miniboss in a Dungeon room")
	if boss:
		_quiet(boss)
		_heal()
	return boss


## Pauses the caster's own attack choice (cooldowns far away); tests start attacks themselves.
func _quiet(boss: WaterCasterBoss) -> void:
	boss._bolt_left = 999.0
	boss._zone_left = 999.0
	boss._wave_left = 999.0


func _park(boss: Node2D, offset: Vector2) -> void:
	_mage.global_position = boss.global_position + offset
	_mage.velocity = Vector2.ZERO


func _heal() -> void:
	_mage.health.current = _mage.health.max_health


func _hazards_of(source: Node) -> Array:
	return get_nodes_in_group(&"floor_hazards").filter(func(h: FloorHazard) -> bool:
		return h.source == source and not h.is_queued_for_deletion())


func _bolts_of(source: Node) -> Array:
	return current_scene.get_children().filter(func(n: Node) -> bool:
		return n is Projectile and (n as Projectile).source == source and not n.is_queued_for_deletion())


func _load() -> void:
	paused = false
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	if _dungeon:
		_mage = _dungeon.mage


func _physics(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds - 0.0001:
		await physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second


## Waits (physics ticks) until `node` has been freed.
func _wait_gone(node: Node, max_frames: int = 300) -> void:
	var id := node.get_instance_id()
	await _wait_until(func() -> bool: return _gone(id), max_frames)


func _gone(id: int) -> bool:
	var node := instance_from_id(id) as Node
	return node == null or node.is_queued_for_deletion()


func _wait_until(condition: Callable, max_frames: int = 300) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
