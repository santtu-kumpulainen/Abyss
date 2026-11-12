extends SceneTree
## Headless check of Issue #51 Stage 4 (enemy deaths and the Blood Monster
## death blast): the dying enemy leaves combat in the same frame (group,
## collision, AI), `died` / rewards happen once, the detached EnemyCorpse plays
## the death animation and frees itself, each enemy type selects its approved
## death effect, the Giant Goblin plays its own Dying frames, and the Blood
## Monster blast (0.6 s warning, 100 px, Mage 12 x scaling, regular enemies 40 %
## of its max HP, never minibosses / boss / itself, once per target) including
## finite chain reactions, room clear and Dungeon rewards.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_enemy_deaths.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const MAGE := "res://scenes/mage/mage.tscn"
const BASE_ENEMY := "res://scenes/enemies/enemy.tscn"
const DEMON := "res://scenes/enemies/demon.tscn"
const CASTER := "res://scenes/enemies/demon_caster.tscn"
const GOBLIN := "res://scenes/enemies/giant_goblin.tscn"
const BLOOD_MONSTER := "res://scenes/enemies/blood_monster.tscn"
const WATER_CASTER := "res://scenes/enemies/water_caster.tscn"
const WATER_BOSS := "res://scenes/enemies/water_caster_boss.tscn"
const BROOD := "res://scenes/enemies/brood_mother.tscn"
const HEX := "res://scenes/enemies/hexcaller.tscn"
const WARDEN := "res://scenes/enemies/abyss_warden.tscn"
const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const FRAME := 1.0 / 60.0

## scene -> expected death_effect resource (Issue #51 section I).
const EFFECTS := {
	DEMON: "res://scenes/effects/gigapack/skull_smoke.tres",
	CASTER: "res://scenes/effects/violet_burst.tres",
	GOBLIN: "res://scenes/effects/gigapack/green_splatter.tres",
	WATER_CASTER: "res://scenes/effects/gigapack/water_impact.tres",
	WATER_BOSS: "res://scenes/effects/gigapack/water_impact.tres",
	WARDEN: "res://scenes/effects/violet_burst.tres",
	BROOD: "res://scenes/effects/death_bubbles.tres",
	HEX: "res://scenes/effects/death_bubbles.tres",
}

var _failures := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	await _test_lifecycle()
	await _test_no_death_animation()
	await _test_effect_selection()
	await _test_goblin()
	_test_frames_unchanged()
	await _test_blast_damage()
	await _test_blast_scaling()
	await _test_blast_once()
	await _test_chain()
	await _test_room_clear()
	await _test_dungeon_rewards()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Death lifecycle -----------------------------------------------------------------------------

func _test_lifecycle() -> void:
	var demon := await _spawn(DEMON, Vector2(0, 0)) as Enemy
	var deaths := [0]
	demon.died.connect(func() -> void: deaths[0] += 1)
	var corpses_before := _corpses().size()
	var hurtbox := demon.get_node(^"Hurtbox") as Area2D
	demon.take_damage(1000.0)
	# Same frame: out of combat before anything visual has played.
	_check(demon.dying and not demon.is_in_group(&"enemies") and demon.is_queued_for_deletion(),
			"death: enemy leaves the 'enemies' group and is queued for freeing in the same frame")
	_check(demon.collision_layer == 0 and demon.collision_mask == 0 and hurtbox.collision_layer == 0,
			"death: body and hurtbox collision disabled at once")
	_check(not demon.is_physics_processing(), "death: AI (physics processing) stopped at once")
	# Repeated kills / death calls change nothing.
	demon.take_damage(1000.0)
	demon.health.died.emit()
	demon._handle_death()
	_check(deaths[0] == 1, "death: `died` emitted exactly once (%d) despite repeated kills" % deaths[0])
	var corpses := _corpses()
	_check(corpses.size() == corpses_before + 1, "death: exactly one corpse visual spawned (%d)" % (corpses.size() - corpses_before))
	var corpse := corpses.back() as EnemyCorpse
	_check(corpse.get_parent() != demon and corpse.sprite().animation == &"death" and corpse.sprite().is_playing()
			and corpse.sprite().flip_h == demon._sprite.flip_h and corpse.sprite().scale == demon._sprite.scale,
			"corpse: detached copy of the sprite playing 'death'")
	_check(_collision_objects(corpse) == 0, "corpse: has no collision or areas")
	await _physics(1)
	_check(not is_instance_valid(demon), "death: the enemy itself is freed after one frame")
	_check(is_instance_valid(corpse), "corpse: still playing after the enemy is gone")
	# 4 frames at 8 FPS + hold + fade = ~1.1 s.
	await _seconds(1.4)
	_check(not is_instance_valid(corpse), "corpse: frees itself after the animation and fade")
	_check(_pixel_effects().is_empty(), "death effect: freed itself")


func _test_no_death_animation() -> void:
	# The base enemy scene has no SpriteFrames: no corpse, only the shared effect.
	var enemy := await _spawn(BASE_ENEMY, Vector2(0, 0)) as Enemy
	var before := _corpses().size()
	enemy.take_damage(1000.0)
	_check(_corpses().size() == before, "fallback: no death animation -> no corpse, death still handled")
	await _physics(1)
	_check(not is_instance_valid(enemy), "fallback: enemy freed")
	await _seconds(1.0)


# --- Per-enemy effects ---------------------------------------------------------------------------

func _test_effect_selection() -> void:
	for path: String in EFFECTS:
		var expected := load(EFFECTS[path]) as EffectSheet
		var enemy := await _spawn(path, Vector2(0, 0)) as Enemy
		_check(expected != null and expected.texture != null and enemy.death_effect == expected,
				"%s: death effect %s loads" % [path.get_file(), EFFECTS[path].get_file()])
		var before := _pixel_effects()
		var corpse_count := _corpses().size()
		enemy.take_damage(1.0e9)
		var spawned := _pixel_effects().filter(func(e: PixelEffect) -> bool: return not before.has(e))
		_check(spawned.size() == 1 and (spawned[0] as PixelEffect).sheet == expected,
				"%s: plays its own death effect" % path.get_file())
		_check(_corpses().size() == corpse_count + 1, "%s: death animation corpse spawned" % path.get_file())
		await _physics(1)
		_check(not is_instance_valid(enemy), "%s: enemy freed at once" % path.get_file())
	await _seconds(2.0)
	_check(_corpses().is_empty() and _pixel_effects().is_empty(), "all corpses and death effects cleaned themselves up")
	# Blood Monster: its blast is its effect; no extra death sheet.
	var bm := (load(BLOOD_MONSTER) as PackedScene).instantiate() as BloodMonster
	_check(bm.death_effect == null and bm.death_blast_effect == load("res://scenes/effects/blood_blast.tres")
			and bm.death_blast_effect.texture != null, "Blood Monster: no death sheet, red blast effect loads")
	bm.free()
	for id: StringName in [&"green_splatter", &"skull_smoke"]:
		_check(EffectLibrary.has(id) and EffectLibrary.sheet(id).texture != null, "EffectLibrary: %s loads" % id)


# --- Goblin --------------------------------------------------------------------------------------

func _test_goblin() -> void:
	var frames := load("res://scenes/enemies/sprite_frames/giant_goblin.tres") as SpriteFrames
	var ok := frames.has_animation(&"death") and frames.get_frame_count(&"death") == 10 \
			and not frames.get_animation_loop(&"death") and is_equal_approx(frames.get_animation_speed(&"death"), 12.0)
	if ok:
		for i in 10:
			var path := frames.get_frame_texture(&"death", i).resource_path
			ok = ok and path == "res://assets/characters/enemies/Giant Goblin/PNG/PNG Sequences/Dying/Dying_%03d.png" % i
	_check(ok, "Goblin: 'death' = the 10 Craftpix Dying frames in order, 12 FPS, one-shot")
	var goblin := await _spawn(GOBLIN, Vector2(0, 0)) as Enemy
	_check(goblin._sprite.sprite_frames == frames, "Goblin: scene uses giant_goblin.tres")
	goblin.take_damage(1.0e9)
	_check(not goblin.is_in_group(&"enemies") and goblin.collision_layer == 0, "Goblin: leaves combat at once")
	var corpse := _corpses().back() as EnemyCorpse
	_check(corpse.sprite().sprite_frames == frames and corpse.sprite().animation == &"death", "Goblin corpse plays 'death'")
	var finished := [false]
	corpse.sprite().animation_finished.connect(func() -> void: finished[0] = true)
	var n := await _frames_until(func() -> bool: return finished[0], 120)
	_check(finished[0] and corpse.sprite().frame == 9, "Goblin death animation finishes on its last frame (%.2f s)" % (n * FRAME))
	await _seconds(0.8)
	_check(not is_instance_valid(corpse), "Goblin corpse frees itself")


func _test_frames_unchanged() -> void:
	var goblin := load("res://scenes/enemies/sprite_frames/giant_goblin.tres") as SpriteFrames
	var ok := true
	for dir in ["down", "left", "right", "up"]:
		ok = ok and goblin.get_frame_count("idle_" + dir) == 16 and goblin.get_frame_count("walk_" + dir) == 20
	_check(ok and goblin.get_animation_names().size() == 9, "Goblin idle/walk animations kept (16 / 20 frames x 4)")
	for name in ["demon", "blood_monster"]:
		var f := load("res://scenes/enemies/sprite_frames/%s.tres" % name) as SpriteFrames
		_check(f.get_frame_count(&"idle") == 6 and f.get_frame_count(&"walk") == 8 and f.get_frame_count(&"death") == 4
				and not f.get_animation_loop(&"death"), "%s: idle 6 / walk 8 kept, one-shot death 4" % name)


# --- Blood Monster blast -------------------------------------------------------------------------

func _test_blast_damage() -> void:
	var origin := Vector2(2000, 0)
	var mage := await _spawn(MAGE, origin + Vector2(60, 0)) as Mage
	var near := await _spawn(DEMON, origin + Vector2(-80, 0)) as Enemy
	var tough := await _spawn(GOBLIN, origin + Vector2(0, 70)) as Enemy
	var far := await _spawn(DEMON, origin + Vector2(-130, 0)) as Enemy
	var bosses: Array[Enemy] = []
	var spots: Array[Vector2] = [Vector2(-40, -50), Vector2(40, -50), Vector2(0, -90), Vector2(65, -65)]
	for i in 4:
		bosses.append(await _spawn([BROOD, HEX, WATER_BOSS, WARDEN][i], origin + spots[i]) as Enemy)
	var monster := await _spawn(BLOOD_MONSTER, origin) as BloodMonster
	await _physics(2)
	var mage_hp := mage.health.current
	var tough_hp := tough.health.current
	var far_hp := far.health.current
	var boss_hp: Array[float] = []
	for b in bosses:
		boss_hp.append(b.health.current)
	var hits := [-1, -1]
	monster.take_damage(1.0e9)
	var blast := monster.death_blast
	_check(blast != null and blast.is_inside_tree() and blast.phase == FloorHazard.Phase.TELEGRAPH,
			"blast: warning circle appears in the same frame as the death")
	_check(blast != null and is_equal_approx(blast.radius, 100.0) and is_equal_approx(blast.delay, 0.6)
			and blast.global_position == origin, "blast: radius 100 px, 0.6 s warning, at the death position")
	_check(not blast.can_damage(monster), "blast: the dead Blood Monster cannot be damaged by its own blast")
	blast.erupted.connect(func(n: int) -> void:
		hits[0] = n
		hits[1] = blast.hit_targets.size())
	var frames := await _frames_until(func() -> bool: return hits[0] >= 0, 120)
	_check(absf(frames * FRAME - 0.6) <= 2.0 * FRAME, "blast: detonates after %.3f s (0.6 s)" % (frames * FRAME))
	_check(is_equal_approx(mage_hp - mage.health.current, 12.0), "blast: Mage takes 12 (%.1f)" % (mage_hp - mage.health.current))
	_check(not is_instance_valid(near) or near.dying, "blast: nearby Demon (30 HP) killed by 36 damage")
	_check(is_equal_approx(tough_hp - tough.health.current, 36.0),
			"blast: nearby Goblin takes 40%% of 90 = 36 (%.1f)" % (tough_hp - tough.health.current))
	_check(is_equal_approx(far.health.current, far_hp), "blast: Demon 130 px away (outside 100 px) untouched")
	var safe := true
	for i in bosses.size():
		safe = safe and is_equal_approx(bosses[i].health.current, boss_hp[i])
	_check(safe, "blast: Brood Mother, Hexcaller, Water Caster miniboss and Abyss Warden take no damage")
	_check(hits[0] == 3 and hits[1] == 3, "blast: 3 targets hit once each (%d)" % hits[0])
	await _physics(2)
	_check(not is_instance_valid(blast), "blast: frees itself after detonating")
	_check(is_equal_approx(mage_hp - mage.health.current, 12.0) and is_equal_approx(tough_hp - tough.health.current, 36.0),
			"blast: no repeated damage afterwards")
	await _seconds(1.5)
	for node in [mage, tough, far] + bosses:
		if is_instance_valid(node):
			node.free()


func _test_blast_scaling() -> void:
	var monster := await _spawn(BLOOD_MONSTER, Vector2(4000, 0)) as BloodMonster
	monster.apply_scaling(2.0, 1.5)
	_check(is_equal_approx(monster.death_blast_damage, 18.0), "blast scaling: Mage damage 12 x 1.5 = 18")
	monster.take_damage(1.0e9)
	var blast := monster.death_blast
	_check(is_equal_approx(blast.damage, 18.0) and is_equal_approx(blast.enemy_damage, 72.0),
			"blast scaling: enemy damage = 40%% of the scaled 180 max HP (%.1f)" % blast.enemy_damage)
	await _seconds(1.5)


func _test_blast_once() -> void:
	var origin := Vector2(6000, 0)
	var mage := await _spawn(MAGE, origin + Vector2(40, 0)) as Mage
	var monster := await _spawn(BLOOD_MONSTER, origin) as BloodMonster
	var mage_hp := mage.health.current
	var blasts := _blast_counter()
	monster.take_damage(1.0e9)
	monster.take_damage(1.0e9)
	monster._handle_death()
	monster._spawn_death_blast()
	_check(blasts.call() == 1, "blast: repeated death calls leave exactly one blast (%d)" % blasts.call())
	await _seconds(1.0)
	_check(is_equal_approx(mage_hp - mage.health.current, 12.0), "blast: Mage damaged once (%.1f)" % (mage_hp - mage.health.current))
	mage.free()
	await _seconds(0.6)


func _test_chain() -> void:
	var origin := Vector2(8000, 0)
	# A -> B (80 px) -> C (160 px, outside A's radius); D far away. B and C are worn down
	# so one blast kills them.
	var a := await _spawn(BLOOD_MONSTER, origin) as BloodMonster
	var b := await _spawn(BLOOD_MONSTER, origin + Vector2(80, 0)) as BloodMonster
	var c := await _spawn(BLOOD_MONSTER, origin + Vector2(160, 0)) as BloodMonster
	var d := await _spawn(BLOOD_MONSTER, origin + Vector2(400, 0)) as BloodMonster
	b.take_damage(80.0)
	c.take_damage(80.0)
	var deaths := {a: 0, b: 0, c: 0, d: 0}
	for m: BloodMonster in deaths:
		m.died.connect(func() -> void: deaths[m] += 1)
	var spawned: Array[BloodBlast] = []
	var collect := func(node: Node) -> void:
		if node is BloodBlast:
			spawned.append(node)
	root.child_entered_tree.connect(collect)
	a.take_damage(1.0e9)
	_check(spawned.size() == 1 and is_instance_valid(b) and not b.dying, "chain: A's blast pending, B still alive")
	var t := await _frames_until(func() -> bool: return spawned.size() >= 2, 120)
	_check(spawned.size() == 2 and absf(t * FRAME - 0.6) <= 2.0 * FRAME and spawned[1].global_position == origin + Vector2(80, 0),
			"chain: A's detonation kills B, which starts its own 0.6 s warning (%.2f s)" % (t * FRAME))
	_check(is_instance_valid(c) and not c.dying, "chain: C (outside A's radius) survives A's blast")
	t = await _frames_until(func() -> bool: return spawned.size() >= 3, 120)
	_check(spawned.size() == 3 and absf(t * FRAME - 0.6) <= 2.0 * FRAME, "chain: B's detonation kills C 0.6 s later (%.2f s)" % (t * FRAME))
	await _seconds(1.5)
	root.child_entered_tree.disconnect(collect)
	_check(spawned.size() == 3, "chain: finite, three blasts in total (%d)" % spawned.size())
	_check(deaths[a] == 1 and deaths[b] == 1 and deaths[c] == 1 and deaths[d] == 0,
			"chain: each monster died once, D untouched (%s)" % str(deaths.values()))
	_check(is_instance_valid(d) and is_equal_approx(d.health.current, d.health.max_health), "chain: D outside every radius at full HP")
	_check(get_nodes_in_group(&"floor_hazards").is_empty(), "chain: no blast lingers")
	d.free()


# --- Room clear and rewards ----------------------------------------------------------------------

func _test_room_clear() -> void:
	var room := Room.new()
	var container := Node2D.new()
	container.name = "Enemies"
	room.add_child(container)
	var doors := Node2D.new()
	doors.name = "Doors"
	room.add_child(doors)
	var monster := (load(BLOOD_MONSTER) as PackedScene).instantiate() as BloodMonster
	var demon := (load(DEMON) as PackedScene).instantiate() as Enemy
	for e: Enemy in [monster, demon]:
		e.target_group = &"nobody"
		container.add_child(e)
	monster.position = Vector2(10000, 0)
	demon.position = Vector2(10070, 0)
	room.start_on_ready = true
	root.add_child(room)
	await _physics(3)
	var defeated: Array[Enemy] = []
	var cleared := [0]
	room.enemy_defeated.connect(func(e: Enemy) -> void: defeated.append(e))
	room.cleared.connect(func() -> void: cleared[0] += 1)
	_check(room.state == Room.State.COMBAT and room.enemies_remaining == 2, "room: combat with 2 enemies")
	monster.take_damage(1.0e9)
	_check(room.enemies_remaining == 1 and defeated == [monster], "room: dead Blood Monster leaves the count in the same frame")
	_check(monster.death_blast.get_parent() == room, "room: the blast lives under the room (freed with it)")
	await _seconds(0.75)
	_check(defeated.size() == 2 and defeated[1] == demon and room.state == Room.State.CLEARED and cleared[0] == 1,
			"room: blast kill counts as a defeat and clears the room once")
	room.free()
	await _physics(1)
	# Clear is not delayed by visuals: the last kill clears in the same frame while its corpse plays.
	room = Room.new()
	container = Node2D.new()
	container.name = "Enemies"
	room.add_child(container)
	doors = Node2D.new()
	doors.name = "Doors"
	room.add_child(doors)
	var goblin := (load(GOBLIN) as PackedScene).instantiate() as Enemy
	goblin.target_group = &"nobody"
	goblin.position = Vector2(12000, 0)
	container.add_child(goblin)
	room.start_on_ready = true
	root.add_child(room)
	await _physics(3)
	goblin.take_damage(1.0e9)
	_check(room.state == Room.State.CLEARED and not _corpses().is_empty(), "room: cleared in the death frame while the corpse still plays")
	_check(_corpses().all(func(c: Node) -> bool: return c.get_parent() != container),
			"room: corpses are never in the Enemies container")
	await _seconds(1.5)
	room.free()


func _test_dungeon_rewards() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(DUNGEON)
	await _frames_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _physics(3)
	var dungeon := current_scene as Dungeon
	var run := dungeon.run_state
	var room := dungeon.current_room
	var far := dungeon.mage.global_position + Vector2(5000, 0)
	var monster := (load(BLOOD_MONSTER) as PackedScene).instantiate() as BloodMonster
	var demon := (load(DEMON) as PackedScene).instantiate() as Enemy
	monster.target_group = &"nobody"
	demon.target_group = &"nobody"
	room.add_summoned_enemy(monster, far)
	room.add_summoned_enemy(demon, far + Vector2(60, 0))
	await _physics(2)
	var kills := run.enemies_defeated
	var gold := run.gold_earned
	monster.take_damage(1.0e9)
	monster.take_damage(1.0e9)
	_check(run.enemies_defeated == kills + 1 and run.gold_earned > gold,
			"dungeon: Blood Monster rewards granted in the death frame, once")
	var after_monster := run.gold_earned
	await _seconds(1.0)
	_check(run.enemies_defeated == kills + 2 and run.gold_earned > after_monster,
			"dungeon: the blast-killed Demon grants its normal rewards")
	var final_gold := run.gold_earned
	await _seconds(1.0)
	_check(run.enemies_defeated == kills + 2 and run.gold_earned == final_gold, "dungeon: no duplicate rewards later")


# --- Helpers -------------------------------------------------------------------------------------

## Spawns `path` at `pos`. Enemies target `target_group` (default: nobody, so they stand still).
func _spawn(path: String, pos: Vector2, target_group: StringName = &"nobody") -> Node2D:
	var node := (load(path) as PackedScene).instantiate() as Node2D
	if node is Enemy:
		(node as Enemy).target_group = target_group
	root.add_child(node)
	node.global_position = pos
	await _physics(2)
	return node


func _corpses() -> Array[Node]:
	return get_nodes_in_group(EnemyCorpse.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


func _pixel_effects() -> Array:
	var out := []
	for node in root.get_children():
		if node is PixelEffect and not node.is_queued_for_deletion():
			out.append(node)
	return out


## Callable returning how many BloodBlasts were added to the root since it was made.
func _blast_counter() -> Callable:
	var count := [0]
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is BloodBlast:
			count[0] += 1)
	return func() -> int: return count[0]


func _collision_objects(node: Node) -> int:
	var n := 1 if node is CollisionObject2D else 0
	for child in node.get_children():
		n += _collision_objects(child)
	return n


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


func _seconds(s: float) -> void:
	await _physics(ceili(s * 60.0))
	await process_frame


func _frames_until(condition: Callable, max_frames: int) -> int:
	for i in max_frames:
		if condition.call():
			return i
		await physics_frame
	return max_frames


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
