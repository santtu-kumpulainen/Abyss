extends SceneTree
## Headless check of the player-output-relative enemy HP modifier:
##   O        = spell_damage_multiplier (no Greed gold bonus) x projectiles x factor / cooldown multiplier
##   O_ref(D) = 1.25 x 1.5^(D-1)
##   modifier = clamp(O / O_ref(D), 1.0, 2.0)
##   final    = dungeon baseline (1 + 0.25 (D-1)) x modifier x difficulty
## The modifier is snapshotted when a room is created (first entry) and also
## applies to boss rooms; enemy damage, speed, XP and gold are not affected.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_output_hp.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const NORMAL := Difficulty.Tier.NORMAL

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState

## [name, dungeon level, Mage level, shard, ember relic, ember core, quick cast, rune sigil, twin cast,
##  damage, cooldown, projectile factor, O, O_ref, modifier, baseline, final HP multiplier]
## (Issue #55 Stage 3 item values: Shard +8%, Ember Relic +10%, Ember Core +10%, Sigil -5%.)
const ROWS := [
	["typical D1", 1, 2, 1, 0, 0, 1, 0, false, 1.13, 0.95, 1.0, 1.1895, 1.25, 1.0, 1.00, 1.0],
	["typical D2", 2, 5, 1, 1, 0, 2, 0, false, 1.38, 0.90, 1.0, 1.5333, 1.875, 1.0, 1.25, 1.25],
	["typical D3", 3, 8, 2, 2, 1, 3, 1, false, 1.81, 0.80, 1.0, 2.2625, 2.8125, 1.0, 1.50, 1.50],
	["heavy D1", 1, 4, 1, 0, 1, 1, 1, false, 1.33, 0.90, 1.0, 1.4778, 1.25, 1.1822, 1.00, 1.1822],
	["heavy D2", 2, 7, 2, 1, 2, 2, 2, false, 1.76, 0.80, 1.0, 2.2, 1.875, 1.1733, 1.25, 1.4667],
	["heavy D3", 3, 10, 3, 2, 3, 3, 3, true, 2.19, 0.70, 1.4, 4.38, 2.8125, 1.5573, 1.50, 2.336],
]


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	_test_table()
	_test_caps_and_exclusions()
	await _test_snapshot_and_boss()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _build(row: Array) -> RunState:
	var run := RunState.new()
	run.configure(NORMAL)
	run.dungeon_level = row[1]
	run.level = row[2]
	if row[3] > 0:
		run.collected[&"ember_shard"] = row[3]
	for i in row[4]:
		run.relics.append(&"ember_relic")
	if row[5] > 0:
		run.purchased[&"ember_core"] = row[5]
	if row[6] > 0:
		run.purchased[&"quick_cast"] = row[6]
	if row[7] > 0:
		run.treasures[&"rune_sigil"] = row[7]
	if row[8]:
		run.purchased[&"twin_cast"] = 1
	return run


func _test_table() -> void:
	for row in ROWS:
		var run := _build(row)
		var damage := run.spell_damage_multiplier()
		var cooldown := run.spell_cooldown_multiplier()
		var factor := run.projectile_count() * run.projectile_damage_factor()
		var output := run.player_output()
		var ref := LevelScaling.output_reference(run.dungeon_level)
		var modifier := run.output_hp_modifier()
		var final := run.enemy_health_multiplier() * modifier
		var ok := absf(damage - row[9]) < 0.001 and absf(cooldown - row[10]) < 0.001 and absf(factor - row[11]) < 0.001 \
				and absf(output - row[12]) < 0.001 and absf(ref - row[13]) < 0.001 and absf(modifier - row[14]) < 0.001 \
				and absf(LevelScaling.enemy_health(run.dungeon_level) - row[15]) < 0.001 and absf(final - row[16]) < 0.001
		_check(ok, "%s: damage %.2f, cooldown %.2f, projectiles x%.1f, O %.4f, O_ref %.4f, modifier %.4f, baseline %.2f, final HP x%.4f"
				% [row[0], damage, cooldown, factor, output, ref, modifier, LevelScaling.enemy_health(run.dungeon_level), final])
		run.free()
	# Typical builds stay near baseline, heavy builds get a meaningful capped increase.
	var typical: Array[float] = []
	var heavy: Array[float] = []
	for row in ROWS:
		var run := _build(row)
		(typical if row[0].begins_with("typical") else heavy).append(run.output_hp_modifier())
		run.free()
	_check(typical.all(func(m: float) -> bool: return m < 1.1), "typical builds stay within +10%% of baseline (%s)" % [typical])
	_check(heavy.all(func(m: float) -> bool: return m >= 1.15 and m <= 2.0), "heavy builds get +17%% .. +100%% (%s)" % [heavy])


func _test_caps_and_exclusions() -> void:
	_check(is_equal_approx(LevelScaling.output_reference(1), 1.25) and is_equal_approx(LevelScaling.output_reference(2), 1.875)
			and is_equal_approx(LevelScaling.output_reference(3), 2.8125), "reference output 1.25 / 1.875 / 2.8125")
	_check(is_equal_approx(LevelScaling.output_hp_modifier(0.3, 1), 1.0) and is_equal_approx(LevelScaling.output_hp_modifier(1.25, 1), 1.0),
			"minimum modifier 1.0: weak output never lowers enemy HP below the baseline")
	_check(is_equal_approx(LevelScaling.output_hp_modifier(100.0, 3), 2.0) and is_equal_approx(LevelScaling.output_hp_modifier(2.5, 1), 2.0),
			"maximum modifier 2.0")
	_check(is_equal_approx(LevelScaling.output_hp_modifier(1.875, 1), 1.5), "modifier is the plain ratio between the caps")
	var run := RunState.new()
	run.configure(NORMAL)
	_check(is_equal_approx(run.player_output(), 1.0) and is_equal_approx(run.output_hp_modifier(), 1.0), "a fresh Mage has output 1.0 and modifier 1.0")
	# Excluded: Greed's gold-based bonus (and Arcane Momentum, which is not in any multiplier).
	var greed := RunState.new()
	greed.configure(NORMAL, &"avarice")
	greed.treasures[&"survivor_cache"] = 1  # completes Greed's Reward (Avarice + Survivor's Cache)
	greed.currency = 100000
	_check(greed.is_synergy_active(&"greeds_reward") and greed.spell_damage_multiplier() > greed.player_output()
			and is_equal_approx(greed.player_output(), 1.0 + greed._bonus_sum(&"damage")),
			"carried gold raises the damage multiplier (%.2f) but not the output (%.2f)" % [greed.spell_damage_multiplier(), greed.player_output()])
	greed.free()
	run.free()
	# Twin Cast is counted as x1.4 exactly once.
	var a := RunState.new()
	a.configure(NORMAL)
	var plain := a.player_output()
	a.purchased[&"twin_cast"] = 1
	_check(is_equal_approx(a.player_output(), plain * 1.4), "Twin Cast multiplies the output by 2 x 0.7 = 1.4")
	a.changed.emit()
	a.changed.emit()
	_check(is_equal_approx(a.player_output(), plain * 1.4), "recalculating does not stack it")
	a.free()


# --- Scene: snapshot at room creation, boss room -----------------------------------------------------

func _test_snapshot_and_boss() -> void:
	await _load_scene()
	var goblin := _hp("res://scenes/enemies/giant_goblin.tscn")
	# Weak build: modifier 1.0.
	var room_a := await _enter(_dungeon.item_room_index(&"swift_boots"))
	var enemy_a := _goblin(room_a)
	_check(enemy_a != null and is_equal_approx(enemy_a.health.max_health, goblin), "weak build: room A goblin HP is the baseline (%.1f)" % enemy_a.health.max_health)
	# Strengthen the build: Ember Core x3, Quick Cast x3, Shard x3, Sigil x3, Twin Cast.
	_run.purchased[&"ember_core"] = 3
	_run.purchased[&"twin_cast"] = 1
	_run.purchased[&"quick_cast"] = 3
	_run.collected[&"ember_shard"] = 3
	_run.treasures[&"rune_sigil"] = 3
	_run.changed.emit()
	_check(is_equal_approx(_run.output_hp_modifier(), 2.0), "setup: the strong build is capped at modifier 2.0 (O %.2f)" % _run.player_output())
	_check(is_equal_approx(enemy_a.health.max_health, goblin), "an already-entered room does not change when the build improves")
	var room_b := await _enter(_other_tier1_room(_dungeon.item_room_index(&"swift_boots")))
	var enemy_b := _goblin(room_b)
	_check(enemy_b != null and is_equal_approx(enemy_b.health.max_health, goblin * 2.0), "room B, first entered with the strong build: goblin HP x2.0 (%.1f)" % enemy_b.health.max_health)
	var again := await _enter(_dungeon.item_room_index(&"swift_boots"))
	_check(again == room_a and is_equal_approx(_goblin(again).health.max_health, goblin), "revisiting room A keeps its snapshot (x1.0)")
	# Damage, speed, XP and gold are not touched by the modifier.
	var base := (load("res://scenes/enemies/giant_goblin.tscn") as PackedScene).instantiate() as Enemy
	_check(is_equal_approx(enemy_b.contact_damage, base.contact_damage * 1.10) and is_equal_approx(enemy_b.speed, base.speed * Tempo.ENEMY_MOVE)
			and is_equal_approx(enemy_b.attack_cooldown, base.attack_cooldown / Tempo.ENEMY_ATTACK) and enemy_b.xp_reward == base.xp_reward and enemy_b.currency_reward == base.currency_reward,
			"damage (x1.10 only), XP and gold unchanged; speed and cooldown only by the Issue #51 tempo")
	base.free()
	# Boss room: same snapshot rule.
	_run.add_rewards(100000, 0)
	_grant_seals()
	var boss_room := await _enter(_dungeon.boss_index())
	var boss: Boss = null
	for e in boss_room.get_node(^"Enemies").get_children():
		if e is Boss:
			boss = e
	var warden := (load("res://scenes/enemies/abyss_warden.tscn") as PackedScene).instantiate() as Boss
	var warden_hp := (warden.get_node(^"Health") as Health).max_health
	_check(boss != null and is_equal_approx(boss.health.max_health, warden_hp * 1.0 * 2.0),
			"the boss gets the modifier too (%.0f = %.0f x1.00 baseline x2.00)" % [boss.health.max_health, warden_hp])
	_check(is_equal_approx(boss.contact_damage, warden.contact_damage * 1.10) and is_equal_approx(boss.slam_damage, warden.slam_damage * 1.10)
			and is_equal_approx(boss.volley_max_hp_fraction, 0.25), "boss damage sources are unchanged")
	warden.free()


func _goblin(room: Room) -> Enemy:
	for e in room.get_node(^"Enemies").get_children():
		if e is Enemy and e.scene_file_path.ends_with("giant_goblin.tscn"):
			return e
	return null


func _hp(path: String) -> float:
	var e := (load(path) as PackedScene).instantiate()
	var hp := (e.get_node(^"Health") as Health).max_health
	e.free()
	return hp


func _enter(index: int) -> Room:
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	return _dungeon.current_room


func _load_scene() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	paused = false
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
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


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


## Ancient Seals (Issue #43): the boss gate also needs this level's seals; collect them all.
func _grant_seals() -> void:
	for i: int in _dungeon.seal_rooms():
		_run.collect_seal(_dungeon.seal_id(i))


## A Level 1 combat room other than the start room and `except` (seeded layout, Issue #45).
func _other_tier1_room(except: int) -> int:
	for i in range(1, _dungeon.rooms.size()):
		var spec := _dungeon.rooms[i]
		if i != except and spec.required_level == 1 and not spec.is_treasure() and not spec.is_boss:
			return i
	return -1
