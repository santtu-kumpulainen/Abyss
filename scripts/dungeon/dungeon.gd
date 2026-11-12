class_name Dungeon
extends Node2D
## Fixed dungeon run: shows one Room at a time and moves the persistent Mage
## between rooms through linked doors.
##
## Expected children: "Mage" (Mage), "RoomHud" (RoomHud), "RunState" (RunState)
## and "RunHud" (RunHud). Defeated enemies grant their rewards to RunState;
## level-ups and the Vitality upgrade raise the Mage's max HP, and the Mage's
## spell modifiers follow RunState (level + upgrades). UpgradeStations inside
## rooms are given the RunState. Rooms are
## instanced from `rooms` (RoomSpecs on a grid) on first visit and cached
## afterwards, so a cleared room stays cleared (and grants no more rewards)
## when revisited. Doors without a link are sealed. Doors leading to a room
## whose `required_level` is above the Mage's level are level-locked and
## labelled; they open when the level is reached. An optional "DungeonMap/Map"
## child is given this Dungeon to draw the explored rooms.
## Mage level gates move with the dungeon level (MageLevels): see gate_level().
## Items and treasures stack (up to RunState.MAX_STACKS) and their pickups and
## chests refresh on every dungeon level; Practice runs start at the Mage level
## a normal run would arrive with, including the level-up max HP.
## Rooms whose RoomSpec has an `item` get an ItemPickup (`item_pickup_scene`);
## collected items raise max HP / speed / damage through RunState. Defeating a
## Boss marks RunState.boss_defeated and announces the victory; its phase
## changes are announced too. Once every non-boss room is cleared, one extra
## UpgradeStation (`upgrade_station_scene`) is added to the room at
## `final_anvil_cell` (the room outside the boss gate), so the Mage can spend
## gold before the boss without walking back to the start.
## Victory: the first Boss death (while the Mage lives) ends the run once:
## the Mage stops and ignores damage, projectiles are removed, and after
## `victory_delay` seconds the optional "VictoryOverlay" child opens (relic
## choice, then run_summary()). The chosen relic's max HP bonus is applied
## once through RunState.relic_chosen; its other bonuses follow RunState.
## Treasure rooms (RoomSpec.treasure) are optional side rooms: they don't count
## for the full clear or the summary's room count, and their TreasureChests are
## given the RunState; a claimed treasure's "heal" is applied to the Mage once.
## Exits work whenever the current Room's can_exit() allows it.
## The Mage node is kept across rooms, so its HP carries over. Restart
## (reloading the scene) starts a fresh run in `start_room` with a fresh RunState.
## Run setup: on _ready the RunState is configured from the Progression
## autoload's selected difficulty and Pact (so Restart reuses them) and the
## Pact's max HP multiplier is applied once to the fresh Mage. Every encounter
## enemy is scaled once through Enemy.apply_scaling() with RunState's enemy
## multipliers when its Room reports it (Room.enemy_registered, which also
## covers survival waves); combat rooms get the difficulty's extra enemies at
## free safe spawn points. All Mage healing goes through heal_mage() and all
## max HP gains through raise_max_health(). Victory records the difficulty
## with Progression.record_victory() (death never does).
## Endless levels: the victory above is only the end of the current dungeon
## level. Choosing the boss relic calls advance_level(), which resets the level
## (rooms, enemies, boss, anvil, level timer; the RunState's build, XP, gold
## and run timer are kept), fully heals the Mage and starts RunState.dungeon_level
## + 1 in `start_room`. Enemies scale with the level (LevelScaling) on top of
## the difficulty, and Biomes picks the theme / enemy pool per level. Run
## progress (highest level, best run) is saved through Progression.record_run()
## on every level start, boss kill and death, except in replay runs.
## Encounter variation: the run gets a seed (RunState.run_seed, random unless
## RunState.seed_override is set; printed and in run_summary()). On every level
## start EncounterPlanner varies the combat rooms' RoomSpec.enemies from
## RunState.level_seed() (equal-XP swaps, shuffled spawn order); rooms are built
## from room_lineup(), so the same seed always gives the same encounters. The
## treasure rooms are seeded too when built: the rune puzzle order (and its
## plaque) and the survival waves (per-wave equal-XP swaps and order).
## Ancient Seals: every level plans exactly EncounterPlanner.SEAL_SOURCES seal
## rooms (seal_rooms()): both treasure rooms and 2 seeded miniboss rooms (with
## fewer miniboss rooms, "champion" rooms fill up). Each gets an AncientSeal
## (`ancient_seal_scene`) that appears once the room is cleared and is
## registered with RunState (set_seal_sources). Its position is seeded per room
## (level seed + cell) among safe floor points (seal_spawn_points()): clear of
## doors, walls, obstacles, spawn points, enemies, pickups and props. The boss
## room needs RunState.SEALS_REQUIRED seals as well as its Mage level gate
## (can_enter()); its door label shows what is missing.
## Miniboss rooms: miniboss_count() seeded tier-2 combat rooms per level (fixed
## composition: 4 / 5 / 6 / 7, then 8 rooms, 4 of them single; see
## EncounterPlanner.MINIBOSS_ROOM_COMPOSITION, Issue #51) - see miniboss_room_indexes();
## only 2 of them hold a seal - get minibosses from `miniboss_scenes` (the
## roster) through the run's shuffle bag (EncounterPlanner.assign_minibosses:
## even, no repeats before every type appeared) instead of their planned line-up. The
## miniboss is given the XP and gold of that line-up as the normal room would
## spawn it (after the biome's enemy swaps), plus the gold of the extra enemies the room would have spawned as a
## normal room (it spawns none; once per room, miniboss_compensation_gold()) and
## `miniboss_bonus_gold` per miniboss (Issue #51). Clearing
## one reveals its seal and a pick-1-of-2 choice of RunState miniboss items
## (ItemPickups sharing a choice_group). Champion rooms keep their line-up and
## get a ChampionPack (the champion wards its pack until it dies).
## Double- / triple-miniboss rooms (EncounterPlanner.double_miniboss_room_count /
## triple_miniboss_room_count) hold two / three different minibosses (miniboss_pair())
## that split the room's line-up XP and gold (+ the omitted extras' gold) exactly
## (split_reward); each adds its own `miniboss_bonus_gold`, the reward choice is
## given once per room. Each has `double_health_factor` / `triple_health_factor`
## x HP (before the run's scaling, applied once); the Brood Mother has at most
## `double_max_summons` / `triple_max_summons` summons. They spawn at the safe
## spawn points furthest apart (miniboss_spawn_points()). Every miniboss in a
## room shares one `miniboss_entry_delay` (no attack until that long after the
## Mage enters; the countdown runs only once the encounter is active).
## Seeded layout (Issue #45): with `seeded_layout`, `rooms` is an authored
## room pool and every level start places it on the 5x5 grid with
## DungeonLayout (from RunState.level_seed()): `rooms`, `links`, `start_room`
## (0) and `final_anvil_cell` (the boss antechamber) are replaced, so indexes
## and cells are only valid for the current level. boss_index(),
## treasure_index(), item_room_index(), door_to() and entry_door() find rooms
## and doors by role.

signal room_changed(room: Room, index: int)
## Something the map shows changed (room entered or cleared, level gates).
signal map_changed
## Emitted once per level when its boss is defeated.
signal victory_started
## Emitted after the next dungeon level has started (with its number).
signal level_started(dungeon_level: int)

const DOOR_BY_DIRECTION := {
	Vector2i.RIGHT: &"DoorRight", Vector2i.LEFT: &"DoorLeft",
	Vector2i.UP: &"DoorTop", Vector2i.DOWN: &"DoorBottom",
}

## Rooms of the dungeon; indexes are used by enter_room()/start_room.
@export var rooms: Array[RoomSpec] = []
## Two-way door links between neighbouring cells as "x,y - x,y", e.g. "2,4 - 3,4"
## (the door names follow from the direction).
@export var links: PackedStringArray = []
@export var start_room: int = 0
## If true, `rooms` is a room pool placed by DungeonLayout on every level start
## (`links` and the pool's cells are ignored; see the class description).
@export var seeded_layout := false
## How far inside the destination door the Mage arrives (pixels).
@export var arrival_distance: float = 72.0
## How far past a door's centre (outwards) the Mage must walk to leave the room.
@export var exit_distance: float = 8.0
## Scene instanced for RoomSpec.item pickups (root must be an ItemPickup).
@export var item_pickup_scene: PackedScene
## Anvil added once all non-boss rooms are cleared (root must be an UpgradeStation).
@export var upgrade_station_scene: PackedScene
## Cell of the (non-boss) room that receives that anvil (with seeded_layout it is
## set every level to the boss room's antechamber).
@export var final_anvil_cell := Vector2i(2, 1)
## Its position in room coordinates (clear of doors and spawn points).
@export var final_anvil_position := Vector2(760, 150)
## Scene for Ancient Seal pickups (root must be an AncientSeal).
@export var ancient_seal_scene: PackedScene
## Miniboss rooms per level: 0 follows the dungeon-level progression
## (EncounterPlanner.miniboss_room_count); 1-8 force that count (tests). Two of
## them hold seals; with fewer, champion rooms fill up to EncounterPlanner.SEAL_SOURCES.
@export_range(0, 8) var miniboss_rooms: int = 0
## Anchor of the miniboss reward choices (room coordinates, clear of doors), and
## the seal position if a room has no safe seal spawn point.
@export var seal_position := Vector2(576, 324)
@export_group("Seal spawn safety")
## Grid spacing of the candidate seal points (pixels).
@export var seal_grid_step: float = 32.0
## Least distance from the floor edge (walls and corner decor).
@export var seal_wall_margin: float = 120.0
## Least distance from a door (its doorway and arrival point).
@export var seal_door_clearance: float = 200.0
## Least distance from spawn points, enemies, pickups, anvils and interactables.
@export var seal_clearance: float = 100.0
## Extra margin around solid Obstacle footprints.
@export var seal_obstacle_margin: float = 56.0
@export_group("")
## Miniboss scenes (roots must be Minibosses) dealt to the miniboss rooms.
@export var miniboss_scenes: Array[PackedScene] = []
## Gold bonus of each miniboss (Issue #51: once per miniboss, so a double room
## pays it twice), on top of the replaced encounter's gold and its omitted extras.
@export var miniboss_bonus_gold: int = 40
@export_group("Double miniboss rooms")
## Max HP factor of each miniboss of a double room (Issue #51).
@export var double_health_factor: float = 0.85
## Most living Brood Mother summons in a double room.
@export var double_max_summons: int = 2
## Max HP factor of each miniboss of a triple room (Issue #51).
@export var triple_health_factor: float = 0.75
## Most living Brood Mother summons in a triple room.
@export var triple_max_summons: int = 1
## Seconds after the Mage enters a miniboss room before any of its minibosses
## may attack (shared by all of them; sets each miniboss's opening_delay).
@export var miniboss_entry_delay: float = 1.0
## Minibosses of one room never spawn closer than this to a door (pixels).
@export var miniboss_door_clearance: float = 180.0
@export_group("")
## Reward choice pickup offsets from `seal_position`, one per option.
@export var reward_offsets := PackedVector2Array([Vector2(-130, 80), Vector2(130, 80)])
## Seconds between the boss's death and the victory screen.
@export var victory_delay: float = 1.2
## Where the Home Teleport arrival effect plays, relative to the Mage's feet.
@export var home_arrival_offset := Vector2(0, -45)

var current_room: Room
var current_index: int = -1
## Home Teleport cast (Issue #49); created in _ready.
var home_teleport: HomeTeleport
## The Home Teleport arrival warp while it plays; removed when the Mage leaves
## the room before it ends, so it never shows in another room.
var _arrival_effect: PixelEffect
## The anvil added after the full clear (null until then).
var final_anvil: UpgradeStation
## True once this level's boss is defeated (reset by advance_level()).
var victory := false
## Difficulty tier this run's first boss kill unlocked (-1 = none).
var unlocked_tier: int = -1

## "<room>:<door>" -> [room index, door name]
var _link_map := {}
## Room index -> linked room indexes.
var _neighbours := {}
var _room_cache := {}
var _transitioning := false
var _level_changing := false
var _victory_recorded := false
## Identifies this run in the saved best-run record.
var _run_id := 0
## Run time when the current dungeon level was entered.
var _reach_time := 0.0
## Room index -> planned encounter line-up of the current level (EncounterPlanner).
var _lineups := {}
## Room index -> seal room kind (&"treasure", &"miniboss" or &"champion") of the current level.
var _seal_rooms := {}
## Room index -> miniboss scenes (Array[PackedScene], two in a double room) /
## reward choice item ids of the current level.
var _minibosses := {}
var _reward_choices := {}
## Room index -> unscaled omitted-extras gold of a built miniboss room (miniboss_compensation_gold()).
var _miniboss_compensation := {}
## Miniboss room indexes of the current level (seal holders or not) and the
## ones that hold two minibosses.
var _miniboss_rooms: Array[int] = []
var _double_rooms: Array[int] = []
var _triple_rooms: Array[int] = []
## Authored room pool and its start room index (seeded_layout only).
var _room_pool: Array[RoomSpec] = []
var _pool_start := 0

@onready var mage: Mage = $Mage
@onready var _hud: RoomHud = $RoomHud
@onready var run_state: RunState = $RunState
@onready var _run_hud: RunHud = $RunHud
@onready var _map: DungeonMap = get_node_or_null(^"DungeonMap/Map")
@onready var _victory_overlay: VictoryOverlay = get_node_or_null(^"VictoryOverlay")
@onready var _ability_bar: AbilityBar = get_node_or_null(^"AbilityBar")


func _ready() -> void:
	_build_links()
	var progression := ProgressionStore.instance(get_tree())
	run_state.configure(progression.selected_difficulty, progression.selected_pact,
			clampi(progression.selected_start_level, 1, progression.highest_level))
	_run_id = int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
	run_state.run_seed = RunState.seed_override if RunState.seed_override != 0 else (randi() | 1)
	print("Abyss run seed: %d" % run_state.run_seed)
	_plan_level()
	mage.health.scale_max_health(run_state.max_health_multiplier())
	# A practice run starts at a higher Mage level: grant those level-ups' max HP.
	for i in run_state.level - 1:
		mage.health.increase_max_health(run_state.max_health_per_level * run_state.max_health_multiplier(), 0.0)
	mage.health.increase_max_health(0.0, mage.health.max_health)
	mage.caster.momentum_window = Pacts.MOMENTUM_WINDOW
	run_state.synergy_activated.connect(_on_synergy_activated)
	run_state.leveled_up.connect(_on_leveled_up)
	run_state.upgrade_purchased.connect(_on_upgrade_purchased)
	run_state.item_collected.connect(_on_item_collected)
	run_state.relic_chosen.connect(_on_relic_chosen)
	run_state.treasure_claimed.connect(_on_treasure_claimed)
	run_state.seal_collected.connect(_on_seal_collected)
	run_state.speed_potion_expired.connect(func() -> void: _run_hud.show_message("Speed Potion has worn off"))
	run_state.changed.connect(_apply_spell_modifiers)
	_apply_spell_modifiers()
	mage.died.connect(_on_mage_died)
	_run_hud.set_run_state(run_state)
	if _map:
		_map.set_dungeon(self)
	_record_progress()
	home_teleport = HomeTeleport.new()
	home_teleport.name = "HomeTeleport"
	add_child(home_teleport)
	home_teleport.setup(self)
	home_teleport.cast_cancelled.connect(_on_home_teleport_cancelled)
	if _ability_bar:
		_ability_bar.setup(self)
	enter_room(start_room)
	_run_hud.show_message("Find %d Ancient Seals to unseal the Abyss Warden's gate" % RunState.SEALS_REQUIRED)


func _process(delta: float) -> void:
	# Only active play counts: not during the boss reward, after victory or death.
	if victory or mage.is_dead():
		return
	run_state.run_time += delta
	run_state.level_time += delta
	run_state.advance_speed_potion(delta)


## Shows room `index`. With `from_door` (a door name in that room) the Mage
## arrives just inside that door facing inwards and an uncleared room starts
## its encounter at once; otherwise the Mage is placed at PlayerSpawn.
func enter_room(index: int, from_door: StringName = &"") -> void:
	if current_room:
		remove_child(current_room)
	_clear_projectiles()
	if _arrival_effect and is_instance_valid(_arrival_effect):
		_arrival_effect.queue_free()
	_arrival_effect = null
	current_index = index
	current_room = _get_room(index)
	_update_level_gates(index)
	add_child(current_room)
	move_child(current_room, 0)

	if from_door.is_empty():
		mage.global_position = (current_room.get_node(^"PlayerSpawn") as Node2D).global_position
	else:
		var door := current_room.get_node(NodePath("Doors/" + from_door)) as Door
		var inward := -_outward(door)
		mage.global_position = door.global_position + inward * arrival_distance
		mage.facing = Mage.direction_name(inward)
		# Doors lock behind the Mage: an IDLE room's open doors lead nowhere yet.
		current_room.start_encounter()
	# A dash (and its visuals) never carries over into the next room.
	mage.cancel_dash()
	mage.velocity = Vector2.ZERO
	_hud.set_room(current_room)
	room_changed.emit(current_room, index)
	map_changed.emit()


## True if room `index` has been entered this run.
func is_visited(index: int) -> bool:
	return _room_cache.has(index)


func is_cleared(index: int) -> bool:
	return is_visited(index) and (_room_cache[index] as Room).state == Room.State.CLEARED


## True when every non-boss, non-treasure room has been cleared this run.
func all_rooms_cleared() -> bool:
	for i in rooms.size():
		if not rooms[i].is_boss and not rooms[i].is_treasure() and not is_cleared(i):
			return false
	return true


## Number of main rooms (boss room included, treasure rooms not) cleared this run.
func rooms_cleared_count() -> int:
	var count := 0
	for i in rooms.size():
		if not rooms[i].is_treasure() and is_cleared(i):
			count += 1
	return count


## Number of main (non-treasure) rooms.
func main_room_count() -> int:
	return rooms.filter(func(r: RoomSpec) -> bool: return not r.is_treasure()).size()


## Tracked run statistics for the victory screen. "items", "upgrades" are
## id lists in collection/purchase order; "treasures" lists claimed treasure
## ids; "relic" is &"" if none was chosen.
func run_summary() -> Dictionary:
	return {
		"level": run_state.level,
		"rooms_cleared": rooms_cleared_count(),
		"rooms_total": main_room_count(),
		"items": run_state.collected.keys(),
		"upgrades": run_state.purchased.keys(),
		"treasures": run_state.treasures.keys(),
		"enemies_defeated": run_state.enemies_defeated,
		"relic": run_state.relic,
		"difficulty": run_state.difficulty,
		"pact": run_state.pact,
		"synergies": run_state.active_synergies(),
		"gold_earned": run_state.gold_earned,
		"difficulty_bonus_gold": run_state.difficulty_bonus_gold,
		"modifier_bonus_gold": run_state.modifier_bonus_gold,
		"unlocked_tier": unlocked_tier,
		"dungeon_level": run_state.dungeon_level,
		"biome": Biomes.biome_name(run_state.dungeon_level),
		"run_time": run_state.run_time,
		"replay": run_state.is_replay,
		"seed": run_state.run_seed,
	}


## Planned encounter enemies of room `index` on the current level (its
## RoomSpec.enemies as varied by EncounterPlanner, before biome mapping).
func room_lineup(index: int) -> Array[PackedScene]:
	var lineup: Array[PackedScene] = []
	lineup.assign(_lineups.get(index, rooms[index].enemies))
	return lineup


## Heals the Mage through the run's healing modifier (Blood Pact: -50%);
## `kill_heal` sources (Blood Pact's own heal) are not reduced. Returns the HP restored.
func heal_mage(amount: float, kill_heal: bool = false) -> float:
	if amount <= 0.0 or mage.is_dead():
		return 0.0
	var before := mage.health.current
	mage.health.increase_max_health(0.0, amount * (1.0 if kill_heal else run_state.healing_multiplier()))
	return mage.health.current - before


## Drinks a Health Potion (Issue #49): heals its share of max HP through
## heal_mage() (so Blood Pact halves it). Not spent at full HP, when dead or
## after victory. Returns true if one was used.
func use_health_potion() -> bool:
	if run_state.consumable_count(&"health_potion") <= 0 or mage.is_dead() or victory:
		return false
	if mage.health.current >= mage.health.max_health:
		_run_hud.show_message("HP is already full")
		return false
	run_state.use_consumable(&"health_potion")
	var fraction: float = RunState.CONSUMABLES[&"health_potion"]["heal_fraction"]
	var healed := heal_mage(mage.health.max_health * fraction)
	EffectLibrary.spawn(&"heal", mage, mage.caster.global_position)
	_run_hud.show_message("Health Potion: +%d HP" % roundi(healed))
	return true


## Drinks a Speed Potion (Issue #49) through RunState.use_speed_potion()
## (refreshes the duration; not spent while it is still full). Not usable when
## dead or after victory. Returns true if one was used.
func use_speed_potion() -> bool:
	if mage.is_dead() or victory or not run_state.use_speed_potion():
		return false
	EffectLibrary.spawn(&"haste", mage, mage.caster.global_position)
	var factor: float = RunState.CONSUMABLES[&"speed_potion"]["speed_factor"]
	_run_hud.show_message("Speed Potion: +%d%% move speed for %s" % [roundi((factor - 1.0) * 100.0),
			RunState.format_time(run_state.speed_potion_remaining)])
	return true


## Uses consumable `id` (ability bar slot keys, Issue #49) through its own
## use_* function. Returns true if it was used (or a teleport cast started).
func use_item(id: StringName) -> bool:
	match id:
		&"health_potion":
			return use_health_potion()
		&"speed_potion":
			return use_speed_potion()
		&"home_teleport":
			return use_home_teleport()
	return false


## Home Teleport key (Issue #49): starts the cast, or cancels a running one.
## Shows the reason when it cannot start. Returns true if a cast started.
func use_home_teleport() -> bool:
	if home_teleport.is_casting():
		home_teleport.cancel(&"manual")
		return false
	if home_teleport.try_start():
		_run_hud.show_message("Home Teleport: stand still...")
		return true
	var reasons := {
		&"none_owned": "No Home Teleport (buy one at the Anvil)",
		&"start_room": "You are already in the starting room",
		&"combat": "Cannot teleport during combat",
	}
	var reason := home_teleport.start_refusal()
	if reasons.has(reason):
		_run_hud.show_message(reasons[reason])
	return false


## True while a door transition, a teleport or a level change is under way.
func is_transitioning() -> bool:
	return _transitioning or _level_changing


## Moves the Mage to the current `start_room` (read now, so it follows the
## level's layout) through enter_room(), deferred like a door transition, and
## spends one Home Teleport only once the Mage has arrived. `on_finished`
## (optional) gets true after the teleport, or false if it was dropped
## because the Mage died, the run ended or a level change began meanwhile.
## Returns false (changing nothing) if it cannot start now.
func teleport_home(on_finished: Callable = Callable()) -> bool:
	# Only the cast's completion may teleport: never during a running cast.
	if (is_transitioning() or victory or mage.is_dead() or current_index == start_room
			or run_state.consumable_count(HomeTeleport.ITEM) <= 0 or home_teleport.is_casting()):
		return false
	_transitioning = true
	_teleport_home.call_deferred(on_finished)
	return true


func _teleport_home(on_finished: Callable) -> void:
	# No teleport out of a room that entered combat meanwhile (e.g. a trial).
	var ok := (not mage.is_dead() and not victory and not _level_changing
			and not (current_room and current_room.state == Room.State.COMBAT))
	if ok:
		enter_room(start_room)
		run_state.use_consumable(HomeTeleport.ITEM)
		# The beam's ground splash sits near the bottom of its cell: lift it to the feet.
		_arrival_effect = EffectLibrary.spawn(&"teleport_arrive", self, mage.global_position + home_arrival_offset)
		_run_hud.show_message("Teleported to the starting room")
	if on_finished.is_valid():
		on_finished.call(ok)
	# Let physics settle in the new room before checking doors again.
	await get_tree().physics_frame
	_transitioning = false


## The arrival warp still playing in the current room, or null.
func arrival_effect() -> PixelEffect:
	return _arrival_effect if _arrival_effect and is_instance_valid(_arrival_effect) and not _arrival_effect.is_queued_for_deletion() else null


func _on_home_teleport_cancelled(reason: StringName) -> void:
	if reason not in [&"death", &"victory", &"level_change", &"failed"]:
		_run_hud.show_message("Home Teleport cancelled")


## Raises the Mage's max HP by `amount` x the run's max HP multiplier, then
## heals `heal` through heal_mage().
func raise_max_health(amount: float, heal: float = 0.0) -> void:
	mage.health.increase_max_health(amount * run_state.max_health_multiplier(), 0.0)
	heal_mage(heal)


## Mage level needed to enter room `index` on the current dungeon level.
func gate_level(index: int) -> int:
	return run_state.room_gate(rooms[index].required_level, rooms[index].is_boss)


## True if room `index` can be entered: the Mage's level reaches its gate and,
## for the boss room, this level's Ancient Seals are complete.
func can_enter(index: int) -> bool:
	return run_state.level >= gate_level(index) and (not rooms[index].is_boss or run_state.seals_complete())


## Room index -> seal room kind (&"treasure", &"miniboss", &"champion") on this level.
func seal_rooms() -> Dictionary:
	return _seal_rooms.duplicate()


## RunState seal id of room `index` (unique per cell).
func seal_id(index: int) -> StringName:
	return StringName("seal_%d_%d" % [rooms[index].cell.x, rooms[index].cell.y])


## Miniboss room indexes of the current level (only 2 of them are seal sources).
func miniboss_room_indexes() -> Array[int]:
	return _miniboss_rooms.duplicate()


## Miniboss rooms planned per level: the `miniboss_rooms` override, else the
## dungeon level's progression.
func miniboss_count() -> int:
	return miniboss_rooms if miniboss_rooms > 0 \
			else EncounterPlanner.miniboss_room_count(run_state.dungeon_level, run_state.level_seed())


## True if room `index` holds two minibosses on this level.
func is_double_miniboss(index: int) -> bool:
	return _double_rooms.has(index)


## True if room `index` holds three minibosses on this level.
func is_triple_miniboss(index: int) -> bool:
	return _triple_rooms.has(index)


## Miniboss scenes of room `index` on this level: none, one, or for a double
## room two different ones (both drawn from the run's shuffle bag, see
## EncounterPlanner.assign_minibosses()).
func miniboss_pair(index: int) -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	scenes.assign(_minibosses.get(index, []))
	return scenes


## First miniboss scene planned for room `index` on this level (null if none).
func miniboss_scene(index: int) -> PackedScene:
	var scenes: Array = _minibosses.get(index, [])
	return scenes[0] if not scenes.is_empty() else null


## Item ids offered (pick one) after the miniboss of room `index` on this level.
func reward_choices(index: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_reward_choices.get(index, []))
	return ids


## True if room `index` is a seal source whose seal was collected on this level.
func is_seal_collected(index: int) -> bool:
	return _seal_rooms.has(index) and run_state.is_seal_collected(seal_id(index))


## Door label of the boss gate: what is still missing ("" once it is open).
func boss_gate_label(index: int) -> String:
	var gate := gate_level(index)
	var level_ok := run_state.level >= gate
	if run_state.seals_complete():
		return "" if level_ok else "BOSS Lv %d" % gate
	var seals := "SEALS %d/%d" % [run_state.seals_collected(), RunState.SEALS_REQUIRED]
	return seals if level_ok else "%s  Lv %d" % [seals, gate]


## Index of the boss room (-1 if none).
func boss_index() -> int:
	for i in rooms.size():
		if rooms[i].is_boss:
			return i
	return -1


## Index of the treasure room of kind `kind` (RoomSpec.Treasure; -1 if none).
func treasure_index(kind: RoomSpec.Treasure) -> int:
	for i in rooms.size():
		if rooms[i].treasure == kind:
			return i
	return -1


## Index of the room whose RoomSpec.item is `id` (-1 if none).
func item_room_index(id: StringName) -> int:
	for i in rooms.size():
		if rooms[i].item == id:
			return i
	return -1


## Name of the door in room `index` that leads to room `other` (&"" if not linked).
func door_to(index: int, other: int) -> StringName:
	if index < 0 or other < 0:
		return &""
	return DOOR_BY_DIRECTION.get(rooms[other].cell - rooms[index].cell, &"") if get_neighbours(index).has(other) else &""


## A linked door of room `index`: its door to the first linked room that is not
## the boss room (the boss room's own door if that is its only link; &"" if none).
func entry_door(index: int) -> StringName:
	var others := get_neighbours(index).filter(func(j: int) -> bool: return not rooms[j].is_boss)
	var target: int = others[0] if not others.is_empty() else (get_neighbours(index)[0] if not get_neighbours(index).is_empty() else -1)
	return door_to(index, target)


## Indexes of the rooms linked to room `index`.
func get_neighbours(index: int) -> Array:
	return _neighbours.get(index, [])


## Room index at grid `cell`, or -1.
func index_at(cell: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i].cell == cell:
			return i
	return -1


func _physics_process(_delta: float) -> void:
	# Exits only work once the room allows it (by default after victory;
	# doors are also open while a room is IDLE).
	if _transitioning or current_room == null or mage.is_dead() or not current_room.can_exit():
		return
	for door in current_room.get_doors():
		if not door.is_open():
			continue
		var offset := mage.global_position - door.global_position
		var outward := _outward(door)
		# Past the doorway's centre, going out, within the doorway's width.
		if offset.dot(outward) > exit_distance and absf(offset.dot(outward.orthogonal())) < door.size.x / 2.0:
			var target: Array = _link_map[_key(current_index, door.name)]
			_transition.call_deferred(target[0], target[1])
			_transitioning = true
			return


func _transition(index: int, door_name: StringName) -> void:
	enter_room(index, door_name)
	# Let physics settle in the new room before checking doors again.
	await get_tree().physics_frame
	_transitioning = false


func _get_room(index: int) -> Room:
	if not _room_cache.has(index):
		var spec := rooms[index]
		var level := run_state.dungeon_level
		var room := Biomes.map_scene(spec.scene, level, "room_map").instantiate() as Room
		var theme := Biomes.theme_for(level)
		if theme and not spec.is_treasure():
			(room.get_node(^"Visuals") as RoomVisuals).theme = theme
		# Connected before the room is ready, so scene-placed enemies are scaled too.
		# The player-output HP modifier is snapshotted here, when the room is first created
		# (just before the Mage enters), and also covers enemies registered later (waves).
		room.enemy_registered.connect(_scale_enemy.bind(spec.is_treasure(), run_state.output_hp_modifier()))
		var lineup := room_lineup(index)
		var pool: Array[PackedScene] = []
		for scene in lineup:
			pool.append(Biomes.map_scene(scene, level, "enemy_map"))
		if _minibosses.has(index):
			# The extras this room would have spawned as a normal room (same rule and
			# spawn points as below); their gold is paid by the minibosses instead.
			var omitted := run_state.extra_room_enemies(spec.required_level, room.safe_extra_points(pool.size()).size())
			_add_miniboss(room, index, lineup, pool, EncounterPlanner.extra_enemies_gold(pool, omitted))
		elif not lineup.is_empty():
			room.add_encounter_enemies(pool)
			if not spec.is_boss and not spec.is_treasure():
				var free := room.safe_extra_points(pool.size()).size()
				room.add_extra_enemies(pool, run_state.extra_room_enemies(spec.required_level, free), pool.size())
		if room is SurvivalRoom:
			var trial := room as SurvivalRoom
			trial.extra_per_wave = run_state.extra_wave_enemies()
			# Seeded waves: same sizes and XP per wave, varied types and order.
			trial.wave_enemies = EncounterPlanner.vary_waves(trial.wave_enemies, trial.wave_sizes, hash([run_state.level_seed(), index]))
		elif room is RunePuzzleRoom:
			var puzzle := room as RunePuzzleRoom
			puzzle.sequence = EncounterPlanner.rune_order(puzzle.sequence, hash([run_state.level_seed(), index]))
		if not spec.item.is_empty() and item_pickup_scene:
			var pickup := item_pickup_scene.instantiate() as ItemPickup
			pickup.item_id = spec.item
			pickup.position = spec.item_position
			room.get_node(^"Decor").add_child(pickup, true)
		if _seal_rooms.has(index) and ancient_seal_scene:
			var seal := ancient_seal_scene.instantiate() as AncientSeal
			seal.name = &"AncientSeal"
			seal.seal_id = seal_id(index)
			seal.position = EncounterPlanner.pick_point(seal_spawn_points(room), hash([run_state.level_seed(), "seal", spec.cell]))
			if seal.position == Vector2.INF:
				push_error("Dungeon: no safe Ancient Seal spot in room %d; using seal_position" % index)
				seal.position = seal_position
			room.get_node(^"Decor").add_child(seal, true)
		if _seal_rooms.get(index) == &"champion":
			var pack := ChampionPack.new()
			pack.name = &"ChampionPack"
			pack.ward_broken.connect(func() -> void: _run_hud.show_message("The champion falls - the ward breaks!"))
			room.add_child(pack)
			room.state_changed.connect(func(state: Room.State) -> void:
				if state == Room.State.COMBAT:
					_run_hud.show_message("Champion pack! Slay the crowned champion to break its ward."))
		# get_doors() needs the room to be ready; read the Doors node directly.
		for door: Door in room.get_node(^"Doors").get_children():
			door.sealed = not _link_map.has(_key(index, door.name))
		# Connected once per room instance (rooms are cached), so rewards cannot repeat.
		room.enemy_defeated.connect(_on_enemy_defeated)
		room.cleared.connect(_on_room_cleared)
		for node in room.find_children("*", "", true, false):
			if node is UpgradeStation:
				(node as UpgradeStation).run_state = run_state
			elif node is ItemPickup:
				(node as ItemPickup).run_state = run_state
			elif node is TreasureChest:
				(node as TreasureChest).run_state = run_state
			elif node is AncientSeal:
				(node as AncientSeal).run_state = run_state
			elif node is Boss:
				var boss := node as Boss
				boss.phase_changed.connect(func(p: int) -> void:
					_run_hud.show_message("%s grows stronger! Phase %d" % [boss.display_name, p]))
		_room_cache[index] = room
	return _room_cache[index]


## Unit vector from the room's interior out through `door` (doors sit on walls).
func _outward(door: Door) -> Vector2:
	var visuals := current_room.get_node(^"Visuals") as RoomVisuals
	var center := current_room.to_global(visuals.floor_rect.get_center())
	var v := door.global_position - center
	return Vector2(signf(v.x), 0.0) if absf(v.x) / visuals.floor_rect.size.x > absf(v.y) / visuals.floor_rect.size.y \
		else Vector2(0.0, signf(v.y))


func _on_room_cleared() -> void:
	map_changed.emit()
	_spawn_final_anvil()


## Adds the pre-boss anvil once, after the last non-boss room is cleared.
func _spawn_final_anvil() -> void:
	if final_anvil or upgrade_station_scene == null or not all_rooms_cleared():
		return
	var index := index_at(final_anvil_cell)
	if index < 0 or rooms[index].is_boss:
		push_error("Dungeon: final_anvil_cell %s is not a non-boss room" % final_anvil_cell)
		return
	final_anvil = upgrade_station_scene.instantiate() as UpgradeStation
	final_anvil.name = &"UpgradeStation"
	final_anvil.position = final_anvil_position
	final_anvil.run_state = run_state
	_get_room(index).get_node(^"Decor").add_child(final_anvil, true)
	_run_hud.show_message("Dungeon cleared! An anvil awaits before the boss gate.")


## Applies the run's enemy modifiers once to `enemy` (Enemy.apply_scaling() ignores repeats).
func _scale_enemy(enemy: Enemy, treasure_room: bool, output_modifier: float = 1.0) -> void:
	var elite := enemy.elite or enemy is Boss
	enemy.apply_scaling(run_state.enemy_health_multiplier(treasure_room) * output_modifier,
			run_state.enemy_damage_multiplier(elite, treasure_room),
			run_state.enemy_pace_multiplier(), run_state.enemy_vulnerability_multiplier(elite),
			run_state.enemy_move_pace_multiplier(), run_state.enemy_recovery_multiplier())
	if enemy is Goblin:
		(enemy as Goblin).swings_before_special = run_state.goblin_swings_before_special()
	if enemy is Miniboss:
		# Behaviour tier by dungeon level (Issue #51); its cooldowns are already pace-scaled above.
		(enemy as Miniboss).configure_for_level(run_state.dungeon_level)


func _on_enemy_defeated(enemy: Enemy) -> void:
	run_state.enemies_defeated += 1
	var gold := run_state.grant_enemy_rewards(enemy.xp_reward, enemy.currency_reward)
	# Summons (miniboss adds) grant nothing, not even Blood Pact's kill heal.
	if not enemy.summoned:
		heal_mage(run_state.kill_heal(), true)
	if enemy is Boss and not run_state.boss_defeated:
		run_state.boss_defeated = true
		_run_hud.show_message("%s defeated! +%d gold. Victory!" % [(enemy as Boss).display_name, gold])
		_start_victory()


## Ends the run once: freezes the Mage, removes projectiles, then opens the
## victory screen. Skipped if the Mage already died (Game Over wins).
func _start_victory() -> void:
	if victory or mage.is_dead():
		return
	victory = true
	if not _victory_recorded and not run_state.is_replay:
		# The first boss kill completes the run for difficulty unlocks.
		_victory_recorded = true
		unlocked_tier = ProgressionStore.instance(get_tree()).record_victory(run_state.difficulty)
	_record_progress()
	mage.end_run()
	_clear_projectiles()
	victory_started.emit()
	if victory_delay <= 0.0:
		_open_victory_overlay()
		return
	# A child Timer is freed with the scene if the run is restarted first.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = victory_delay
	timer.timeout.connect(_open_victory_overlay)
	add_child(timer)
	timer.start()


func _open_victory_overlay() -> void:
	if _victory_overlay:
		_victory_overlay.open(self)


## Starts the next dungeon level after the boss relic was chosen. Returns false
## (changing nothing) unless the boss is dead, its relic was chosen and no
## level change is under way, so it cannot run twice per boss.
func advance_level() -> bool:
	if _level_changing or not victory or mage.is_dead() or not run_state.begin_next_level():
		return false
	_level_changing = true
	_transitioning = false
	home_teleport.cancel(&"level_change")
	if current_room:
		remove_child(current_room)
	for room: Room in _room_cache.values():
		room.queue_free()
	_room_cache.clear()
	current_room = null
	current_index = -1
	final_anvil = null
	victory = false
	_clear_projectiles()
	mage.resume_run()
	mage.health.increase_max_health(0.0, mage.health.max_health)
	_reach_time = run_state.run_time
	_record_progress()
	_plan_level()
	enter_room(start_room)
	var level := run_state.dungeon_level
	var text := "Level %d" % level
	if Biomes.is_transition(level):
		text += " - entering %s!" % Biomes.biome_name(level)
	_run_hud.show_message(text)
	_level_changing = false
	level_started.emit(level)
	return true


## Unscaled gold room `index` pays for the extra enemies it does not spawn as a
## miniboss room (set when the room is built; 0 if not built or no miniboss room).
func miniboss_compensation_gold(index: int) -> int:
	return _miniboss_compensation.get(index, 0)


## Puts room `index`'s minibosses into the encounter in place of `lineup`
## (Issue #51 economy). `pool` is the resolved line-up the room would spawn as a
## normal room (`lineup` after the biome's enemy_map, built once in _get_room()).
## The resolved line-up's XP, and its gold + `compensation_gold` (the omitted
## extra enemies' gold, from the same `pool`, once per room), are split exactly
## between the minibosses, so the room pays what the normal room's encounter
## would; each miniboss adds miniboss_bonus_gold (no XP bonus). All of it is
## unscaled: RunState.grant_enemy_rewards() applies the XP / gold multipliers once per kill.
func _add_miniboss(room: Room, index: int, lineup: Array[PackedScene], pool: Array[PackedScene],
		compensation_gold: int = 0) -> void:
	var scenes := miniboss_pair(index)
	var double := scenes.size() > 1
	var triple := scenes.size() > 2
	_miniboss_compensation[index] = compensation_gold
	var xp_shares := EncounterPlanner.split_reward(EncounterPlanner.lineup_xp(pool), scenes.size())
	var gold_shares := EncounterPlanner.split_reward(EncounterPlanner.lineup_gold(pool) + compensation_gold, scenes.size())
	var points := room.get_node(^"SpawnPoints")
	var enemies := room.get_node(^"Enemies") as Node2D
	# Group rooms: the safe spawn points furthest apart (room coordinates).
	var spots: Array[Vector2] = []
	if double:
		spots = miniboss_spawn_points(room, scenes.size())
	var names: Array[String] = []
	for k in scenes.size():
		var boss := scenes[k].instantiate() as Miniboss
		boss.xp_reward = xp_shares[k]
		boss.currency_reward = gold_shares[k] + miniboss_bonus_gold
		if k < spots.size():
			boss.position = spots[k] - _room_position(room, enemies)
		else:
			boss.position = (points.get_child(k % points.get_child_count()) as Node2D).position \
					if points.get_child_count() > 0 else seal_position
		boss.detection_radius = room.spawn_detection_radius
		# One shared room-entry delay for every miniboss of the room (read in _ready;
		# it only counts down once the encounter is active, i.e. after the Mage entered).
		boss.opening_delay = miniboss_entry_delay
		if double:
			# Read before _ready (Health resets current HP to max_health). The run's
			# level / difficulty scaling multiplies it once more in _scale_enemy().
			(boss.get_node(^"Health") as Health).max_health *= triple_health_factor if triple else double_health_factor
			if boss is BroodMother:
				(boss as BroodMother).max_summons = mini((boss as BroodMother).max_summons,
						triple_max_summons if triple else double_max_summons)
		enemies.add_child(boss, true)
		names.append(boss.display_name)
	var who := names[0] if names.size() == 1 else "%s and %s" % [", ".join(names.slice(0, -1)), names[-1]]
	room.state_changed.connect(func(state: Room.State) -> void:
		if state == Room.State.COMBAT:
			_run_hud.show_message(("%s %s an Ancient Seal!" % [who, "guard" if double else "guards"]) if _seal_rooms.has(index)
					else ("%s %s! Defeat %s for a reward." % [who, "attack" if double else "attacks", "them" if double else "it"])))
	var ids := _collectable_choices(index)
	if item_pickup_scene == null:
		return
	for k in mini(ids.size(), reward_offsets.size()):
		var pickup := item_pickup_scene.instantiate() as ItemPickup
		pickup.item_id = ids[k]
		pickup.choice_group = &"miniboss_reward"
		pickup.position = seal_position + reward_offsets[k]
		room.get_node(^"Decor").add_child(pickup, true)


## The reward choices of room `index` that can still be collected when the room
## is built. A planned id at its stack cap (or already taken this level) is
## replaced from the miniboss pool, preferring ids no other miniboss room offers,
## so the choice keeps two options while the pool allows it.
func _collectable_choices(index: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in reward_choices(index):
		if run_state.can_collect(id) and not ids.has(id):
			ids.append(id)
	var offered := {}
	for other: int in _reward_choices:
		if other != index:
			for id: StringName in _reward_choices[other]:
				offered[id] = true
	for allow_offered in [false, true]:
		for id in RunState.miniboss_reward_pool():
			if ids.size() >= reward_offsets.size():
				return ids
			if not ids.has(id) and run_state.can_collect(id) and (allow_offered or not offered.has(id)):
				ids.append(id)
	return ids


## Plans the current dungeon level's encounters and Ancient Seal rooms (rooms
## not built yet use it) and registers the seal sources with RunState.
func _plan_level() -> void:
	var level_seed := run_state.level_seed()
	if seeded_layout:
		_place_rooms(level_seed)
	_lineups = EncounterPlanner.plan(rooms, level_seed)
	_seal_rooms.clear()
	_miniboss_compensation.clear()
	for i in rooms.size():
		if rooms[i].is_treasure():
			_seal_rooms[i] = &"treasure"
	var bosses := clampi(miniboss_count(), 1, EncounterPlanner.MAX_MINIBOSS_ROOMS)
	# Exactly SEAL_SOURCES: the treasure rooms, then miniboss rooms, then champions.
	var boss_seals := mini(bosses, maxi(EncounterPlanner.SEAL_SOURCES - _seal_rooms.size(), 0))
	var champions := maxi(EncounterPlanner.SEAL_SOURCES - _seal_rooms.size() - boss_seals, 0)
	var picked := EncounterPlanner.pick_seal_rooms(rooms, _seal_room_candidates(), bosses + champions, level_seed)
	_miniboss_rooms.assign(picked.slice(0, bosses))
	for k in range(bosses, picked.size()):
		_seal_rooms[picked[k]] = &"champion"
	for i in EncounterPlanner.pick_seal_minibosses(_miniboss_rooms, boss_seals, level_seed):
		_seal_rooms[i] = &"miniboss"
	_triple_rooms = EncounterPlanner.pick_triple_minibosses(_miniboss_rooms,
			EncounterPlanner.triple_miniboss_room_count(run_state.dungeon_level), level_seed)
	_double_rooms = EncounterPlanner.pick_double_minibosses(_miniboss_rooms,
			EncounterPlanner.double_miniboss_room_count(run_state.dungeon_level), level_seed, _triple_rooms)
	_minibosses = EncounterPlanner.assign_minibosses(_miniboss_rooms, _double_rooms, miniboss_scenes,
			run_state.run_seed, run_state.dungeon_level, _triple_rooms)
	_reward_choices = EncounterPlanner.assign_rewards(_miniboss_rooms, RunState.miniboss_reward_pool(), reward_offsets.size(), level_seed)
	if _seal_rooms.size() != EncounterPlanner.SEAL_SOURCES or _miniboss_rooms.size() != bosses:
		push_error("Dungeon: %d Ancient Seal sources (need %d), %d of %d miniboss rooms"
				% [_seal_rooms.size(), EncounterPlanner.SEAL_SOURCES, _miniboss_rooms.size(), bosses])
	var ids: Array[StringName] = []
	for i: int in _seal_rooms:
		ids.append(seal_id(i))
	run_state.set_seal_sources(ids)


## Places the room pool for the current level (seeded_layout): replaces rooms,
## links, start_room and final_anvil_cell and rebuilds the door links. Keeps
## the previous layout if the pool does not fit DungeonLayout.
func _place_rooms(level_seed: int) -> void:
	if _room_pool.is_empty():
		_room_pool = rooms.duplicate()
		_pool_start = start_room
	var layout := DungeonLayout.generate(_room_pool, _pool_start, level_seed)
	if layout.is_empty():
		return
	# A new array: the authored one may be shared with the PackedScene.
	rooms = layout["rooms"]
	links = layout["links"]
	start_room = 0
	final_anvil_cell = layout["anvil_cell"]
	_build_links()


## `count` (2-3) spawn positions (room coordinates) for the minibosses of a
## group room: of the room's SpawnPoints that lie inside the floor, at least
## `miniboss_door_clearance` from every door and clear of obstacles, the set
## whose closest pair is furthest apart (ties: lower marker order), so they
## start on different sides of the room. Falls back to all markers if too few are safe.
func miniboss_spawn_points(room: Room, count: int) -> Array[Vector2]:
	var floor_area := (room.get_node(^"Visuals") as RoomVisuals).floor_rect.grow(-48.0)
	var blocked: Array[Rect2] = []
	for node in room.find_children("*", "", true, false):
		if node is Obstacle:
			var o := node as Obstacle
			blocked.append(Rect2(_room_position(room, o) - o.footprint / 2.0, o.footprint).grow(seal_obstacle_margin))
	var doors: Array[Vector2] = []
	for door in room.get_node(^"Doors").get_children():
		doors.append(_room_position(room, door as Node2D))
	var all_points: Array[Vector2] = []
	var safe: Array[Vector2] = []
	for marker in room.get_node(^"SpawnPoints").get_children():
		var p := _room_position(room, marker as Node2D)
		all_points.append(p)
		if floor_area.has_point(p) and not blocked.any(func(r: Rect2) -> bool: return r.has_point(p)) \
				and doors.all(func(d: Vector2) -> bool: return p.distance_to(d) >= miniboss_door_clearance):
			safe.append(p)
	if safe.size() < count:
		push_warning("Dungeon: only %d safe miniboss spawn points in %s; using all markers" % [safe.size(), room.name])
		safe = all_points
	var best: Array[Vector2] = []
	var best_gap := -1.0
	for combo: Array in _combinations(safe.size(), count):
		var gap := INF
		for a in combo.size():
			for b in range(a + 1, combo.size()):
				gap = minf(gap, safe[combo[a]].distance_to(safe[combo[b]]))
		if gap > best_gap + 0.001:
			best_gap = gap
			best.clear()
			for c: int in combo:
				best.append(safe[c])
	return best


## Index combinations (ascending) of `size` out of `n`.
func _combinations(n: int, size: int) -> Array:
	if size <= 0:
		return [[]]
	var result: Array = []
	for first in n:
		for rest: Array in _combinations(n - first - 1, size - 1):
			result.append([first] + rest.map(func(r: int) -> int: return r + first + 1))
	return result


## Safe Ancient Seal points of `room` (room coordinates, built but not yet in the
## tree): floor grid points `seal_wall_margin` inside the floor, at least
## `seal_door_clearance` from every door and `seal_clearance` from spawn
## points, enemies, pickups, anvils and interactables, and outside every
## Obstacle footprint grown by `seal_obstacle_margin`. Deterministic order.
func seal_spawn_points(room: Room) -> PackedVector2Array:
	var area := (room.get_node(^"Visuals") as RoomVisuals).floor_rect.grow(-seal_wall_margin)
	var keep_away: Array = []  # [position, distance]
	var blocked: Array[Rect2] = []
	for door in room.get_node(^"Doors").get_children():
		keep_away.append([(door as Node2D).position, seal_door_clearance])
	for node in room.find_children("*", "", true, false):
		if node is Obstacle:
			var o := node as Obstacle
			blocked.append(Rect2(_room_position(room, o) - o.footprint / 2.0, o.footprint).grow(seal_obstacle_margin))
		elif node is Marker2D and node.get_parent().name == &"SpawnPoints" or node is Enemy or node is ItemPickup \
				or node is UpgradeStation or node is Interactable or node is AncientSeal:
			keep_away.append([_room_position(room, node as Node2D), seal_clearance])
	var points := PackedVector2Array()
	var y := area.position.y
	while y <= area.end.y:
		var x := area.position.x
		while x <= area.end.x:
			var p := Vector2(x, y)
			if not blocked.any(func(r: Rect2) -> bool: return r.has_point(p)) \
					and keep_away.all(func(k: Array) -> bool: return p.distance_to(k[0]) >= k[1]):
				points.append(p)
			x += seal_grid_step
		y += seal_grid_step
	return points


## Position of `node` in `room` coordinates (works before the room enters the tree).
func _room_position(room: Room, node: Node2D) -> Vector2:
	var xf := Transform2D.IDENTITY
	var current: Node = node
	while current != null and current != room:
		if current is Node2D:
			xf = (current as Node2D).transform * xf
		current = current.get_parent()
	return xf.origin


## Combat rooms that may hold a seal: tier 2 (Mage level gate above 1), with an
## encounter and no item pickup, not the boss / treasure / pre-boss anvil room,
## and reachable from `start_room` without passing the boss room.
func _seal_room_candidates() -> Array[int]:
	var reachable := {start_room: true}
	var queue: Array[int] = [start_room]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j: int in get_neighbours(i):
			if not reachable.has(j) and not rooms[j].is_boss:
				reachable[j] = true
				queue.append(j)
	var result: Array[int] = []
	for i in rooms.size():
		var spec := rooms[i]
		if reachable.has(i) and spec.required_level >= 2 and not spec.is_boss and not spec.is_treasure() \
				and spec.item.is_empty() and spec.cell != final_anvil_cell and not spec.enemies.is_empty():
			result.append(i)
	return result


## Refreshes the boss gate and announces the seal count.
func _on_seal_collected(_id: StringName) -> void:
	if current_index >= 0:
		_update_level_gates(current_index)
	map_changed.emit()
	var count := run_state.seals_collected()
	if not run_state.seals_complete():
		_run_hud.show_message("Ancient Seal %d/%d claimed! %d more to unseal the Warden's gate."
				% [count, RunState.SEALS_REQUIRED, RunState.SEALS_REQUIRED - count])
	elif run_state.is_max_level():
		_run_hud.show_message("All Ancient Seals claimed! The Warden's gate is open.")
	else:
		_run_hud.show_message("All Ancient Seals claimed! Reach Lv %d to open the Warden's gate." % run_state.max_level())


## Saves run progress (highest level, best run); replay runs save nothing.
func _record_progress() -> void:
	if run_state.is_replay:
		return
	ProgressionStore.instance(get_tree()).record_run(_run_id, run_state.dungeon_level, run_state.run_time,
			_reach_time, run_state.difficulty, Biomes.biome_id(run_state.dungeon_level))


func _on_mage_died() -> void:
	_record_progress()


## RunState only emits this once per boss.
func _on_relic_chosen(id: StringName) -> void:
	var bonus: float = RunState.RELICS[id].get("max_health", 0.0)
	if bonus > 0.0:
		raise_max_health(bonus, bonus)


func _on_leveled_up(new_level: int) -> void:
	raise_max_health(run_state.max_health_per_level, run_state.heal_per_level)
	if current_index >= 0:
		_update_level_gates(current_index)
	map_changed.emit()
	var unlocked := rooms.filter(func(r: RoomSpec) -> bool: return run_state.room_gate(r.required_level, r.is_boss) == new_level)
	if unlocked.any(func(r: RoomSpec) -> bool: return r.is_boss):
		if run_state.seals_complete():
			_run_hud.show_message("Level %d! The boss gate is open." % new_level)
		else:
			_run_hud.show_message("Level %d! The boss gate still needs Ancient Seals (%d/%d)."
					% [new_level, run_state.seals_collected(), RunState.SEALS_REQUIRED])
	elif not unlocked.is_empty():
		_run_hud.show_message("Level %d! Deeper rooms unlocked." % new_level)
	else:
		_run_hud.show_message("Level %d!" % new_level)


## Level-locks the doors of room `index` that lead to rooms above the Mage's level.
func _update_level_gates(index: int) -> void:
	var room := _get_room(index)
	for door: Door in room.get_node(^"Doors").get_children():
		var key := _key(index, door.name)
		if not _link_map.has(key):
			continue
		var target_index: int = _link_map[key][0]
		var target: RoomSpec = rooms[target_index]
		door.level_locked = not can_enter(target_index)
		door.lock_label = boss_gate_label(target_index) if target.is_boss else "Lv %d" % gate_level(target_index)


func _on_upgrade_purchased(id: StringName) -> void:
	var bonus: float = RunState.UPGRADES[id].get("max_health", 0.0)
	if bonus > 0.0:
		raise_max_health(bonus, bonus)


## RunState only emits this once per treasure per run.
func _on_treasure_claimed(id: StringName) -> void:
	var data: Dictionary = RunState.TREASURES[id]
	var heal: float = data.get("heal", 0.0)
	if heal > 0.0:
		heal_mage(heal * run_state.treasure_reward_multiplier())
	_run_hud.show_message("%s: %s" % [data["name"], data["effect"]])


## RunState only emits this once per item per run.
func _on_item_collected(id: StringName) -> void:
	var data: Dictionary = RunState.ITEMS[id]
	var bonus: float = data.get("max_health", 0.0)
	if bonus > 0.0:
		raise_max_health(bonus, bonus)
	_run_hud.show_message("%s: %s" % [data["name"], data["effect"]])


## Idempotent: recomputed from RunState, so bonuses never stack twice.
func _apply_spell_modifiers() -> void:
	mage.caster.set_modifiers(run_state.spell_damage_multiplier(), run_state.spell_cooldown_multiplier())
	mage.caster.set_projectiles(run_state.projectile_count(), run_state.projectile_damage_factor())
	mage.speed_multiplier = run_state.effective_move_speed_multiplier()
	mage.base_speed_multiplier = run_state.move_speed_multiplier()
	mage.damage_taken_multiplier = run_state.damage_taken_multiplier()
	mage.caster.momentum = run_state.cast_momentum()


func _on_synergy_activated(id: StringName) -> void:
	# Deferred so it is not replaced by the pickup/treasure message emitted right after.
	_run_hud.show_message.call_deferred("Synergy! %s" % Pacts.synergy_text(id))


func _clear_projectiles() -> void:
	for child in get_children():
		if child is Projectile:
			child.queue_free()


func _key(index: int, door_name: StringName) -> String:
	return "%d:%s" % [index, door_name]


## Fills _link_map/_neighbours from `links`; door names follow from the cell offsets.
func _build_links() -> void:
	_link_map.clear()
	_neighbours.clear()
	for link in links:
		var ends := link.split(" - ")
		var a := index_at(_parse_cell(ends[0])) if ends.size() == 2 else -1
		var b := index_at(_parse_cell(ends[1])) if ends.size() == 2 else -1
		if a < 0 or b < 0 or not DOOR_BY_DIRECTION.has(rooms[b].cell - rooms[a].cell):
			push_error("Bad dungeon link (needs two neighbouring room cells): %s" % link)
			continue
		var door_a: StringName = DOOR_BY_DIRECTION[rooms[b].cell - rooms[a].cell]
		var door_b: StringName = DOOR_BY_DIRECTION[rooms[a].cell - rooms[b].cell]
		_link_map[_key(a, door_a)] = [b, door_b]
		_link_map[_key(b, door_b)] = [a, door_a]
		_neighbours[a] = _neighbours.get(a, []) + [b]
		_neighbours[b] = _neighbours.get(b, []) + [a]


func _parse_cell(text: String) -> Vector2i:
	var parts := text.strip_edges().split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-99, -99)


func _exit_tree() -> void:
	# Cached rooms outside the tree are not freed with the scene.
	for room: Room in _room_cache.values():
		if room != current_room and is_instance_valid(room):
			room.free()
