class_name RunState
extends Node
## Run-level progression: XP, level, currency and anvil upgrades for the
## current dungeon run. Lives in the Dungeon scene, so it persists across room
## transitions and is recreated (reset) when the run restarts. Nothing is saved
## to disk.
##
## Leveling: reaching xp_to_next_level() XP raises the level by one; leftover
## XP carries over. The XP needed grows by `xp_per_level` each level
## (50, 100 by default). The level is capped at max_level() (MageLevels.cap of
## the dungeon level); XP gained there is discarded. Enemy XP is multiplied by
## xp_multiplier() (MageLevels), so each dungeon level takes 3 level-ups. Each level-up emits `leveled_up`; the owner applies the reward
## (the Dungeon uses max_health_per_level/heal_per_level). Spell bonuses are
## read through spell_damage_multiplier()/spell_cooldown_multiplier().
##
## Upgrades (UPGRADES) are stackable anvil purchases: each can be bought once
## per dungeon level (the anvil restocks when a level starts), up to
## `max_stacks`, at a price that rises with the stacks owned, gated by gold and
## a required Mage level that moves up with the dungeon level (MageLevels).
## Stack counts persist for the whole run and every bonus is count x effect. Items (ITEMS) are collected once per run from
## room pickups. Stat bonuses from both are summed on demand, so re-applying
## them never stacks. After the boss dies, one relic (RELICS) can be chosen
## once; it adds to the same bonus sums. Treasure chests (TREASURES) in the
## optional treasure rooms are claimed once per run: their gold is added once,
## stat keys join the bonus sums and "heal" is applied by the owner.
##
## Economy (current dungeon, full clear): tier-1 rooms (Lv 1) give 51 base XP and
## ~225 gold, tier-2 rooms (Lv 2) 106 base XP and ~456 gold, so a full clear
## pays ~680 gold plus the miniboss bonus gold. All three upgrades cost 800
## together: the player can afford two of them, not everything.
##
## Run configuration: configure() sets the run's difficulty (Difficulty.TIERS)
## and Pact (Pacts.PACTS) once. Pact and active synergy (Pacts.SYNERGIES)
## effect keys join the same on-demand bonus sums, so they cannot stack; the
## enemy_*() getters give the fixed per-enemy scaling the Dungeon applies once
## per enemy. Gold from kills and treasures goes through gold_multiplier().
##
## Ancient Seals (per dungeon level): the Dungeon registers the level's seal
## source ids with set_seal_sources(); collect_seal() takes each one once.
## seals_complete() (SEALS_REQUIRED seals) is needed, besides the Mage level
## cap, to enter the boss room. begin_next_level() clears seals and sources.
##
## Consumables (Issue #49, CONSUMABLES): bought at the anvil with gold up to
## each item's inventory cap (buy_consumable(); no once-per-level rule) and
## spent with use_consumable(). The inventory and the Speed Potion timer last
## for the run (kept between dungeon levels, cleared by reset() and by the
## scene reload on death / restart / new run). The Speed Potion is a separate
## factor on top of move_speed_multiplier(): effective_move_speed_multiplier().

signal changed
signal leveled_up(level: int)
signal upgrade_purchased(id: StringName)
signal item_collected(id: StringName)
signal relic_chosen(id: StringName)
signal treasure_claimed(id: StringName)
## Emitted once when a synergy's required relics become owned.
signal synergy_activated(id: StringName)
## Emitted once per Ancient Seal collected on the current dungeon level.
signal seal_collected(id: StringName)
## Emitted after a consumable was bought / one was spent.
signal consumable_bought(id: StringName)
signal consumable_used(id: StringName)
## Emitted when the Speed Potion effect runs out.
signal speed_potion_expired

## Ancient Seals needed on every dungeon level to unseal the boss gate (on top
## of the Mage level cap). The Dungeon registers one more source than this
## (EncounterPlanner.SEAL_SOURCES), so one can be skipped.
const SEALS_REQUIRED := 3

## Most copies of one item / treasure that stack (counts persist across levels).
const MAX_STACKS := 3
## Twin Cast (single-stack anvil upgrade, owned for the rest of the run once bought):
## projectiles per cast and damage factor of each.
const TWIN_CAST_COUNT := 2
const TWIN_CAST_DAMAGE_FACTOR := 0.7
## Flat multiplier on all enemy damage (regular enemies and bosses), on top of
## the difficulty and dungeon-level scaling.
const ENEMY_DAMAGE_FACTOR := 1.10
## Most extra enemies added to one room or survival wave by scaling.
const MAX_EXTRA_ENEMIES := 4
## Upper limit of move_speed_multiplier() (Issue #47): stacked speed items,
## Bloodstones and endless-mode Wind Relics never push the Mage past this.
const MAX_MOVE_SPEED_MULTIPLIER := 1.4
## Upper limit of effective_move_speed_multiplier() while a Speed Potion is active.
const MAX_MOVE_SPEED_WITH_POTION := 1.6

## Anvil consumables (Issue #49), in shop order. "price" in gold, "max" the
## inventory cap. Health Potion: "heal_fraction" of max HP (through the
## Dungeon's healing, so Blood Pact halves it). Speed Potion: "speed_factor"
## for "duration" seconds of active play (re-use refreshes, never stacks).
## Home Teleport: "cast_time" seconds, consumed only when the teleport succeeds.
const CONSUMABLES := {
	&"health_potion": {"name": "Health Potion", "price": 120, "max": 3,
			"effect": "restore 25% max HP", "heal_fraction": 0.25},
	&"speed_potion": {"name": "Speed Potion", "price": 150, "max": 3,
			"effect": "+25% move speed for 3:00", "speed_factor": 1.25, "duration": 180.0},
	&"home_teleport": {"name": "Home Teleport", "price": 200, "max": 1,
			"effect": "1.5 s cast: return to the start room", "cast_time": 1.5},
}

## Anvil upgrades, in display order. Each stack applies its effect keys once.
## "prices" is the cost of the 1st, 2nd, ... stack, "max_stacks" the stack cap and
## "level" the Mage level needed on dungeon level 1 (RunState.upgrade_level()
## adds MageLevels.offset()). "min_dungeon_level" is the first dungeon level the
## upgrade is sold on. Every upgrade lasts for the current run only (RunState.reset()
## clears it). Twin Cast has no effect keys: its stack is read by has_twin_cast().
## Effect keys: max_health (flat), damage (multiplier bonus), cooldown (multiplier
## reduction), speed (multiplier bonus).
const UPGRADES := {
	&"vitality": {"name": "Vitality", "prices": [100, 150, 200], "max_stacks": 3, "level": 1,
			"effect": "+20 max HP per stack", "max_health": 20.0},
	&"quick_cast": {"name": "Quick Cast", "prices": [200, 300, 400], "max_stacks": 3, "level": 2,
			"effect": "-5% spell cooldown per stack", "cooldown": 0.05},
	&"ember_core": {"name": "Ember Core", "prices": [300, 450, 600], "max_stacks": 3, "level": 3,
			"effect": "+25% spell damage per stack", "damage": 0.25},
	&"twin_cast": {"name": "Twin Cast", "prices": [4000], "max_stacks": 1, "level": 1, "min_dungeon_level": 3,
			"effect": "2 projectiles per cast, 70% damage each (this run)"},
}

## Collectible run items (same effect keys as UPGRADES), placed in rooms by RoomSpec.item.
const ITEMS := {
	&"swift_boots": {"name": "Swift Boots", "effect": "+8% move speed", "speed": 0.08, "color": Color(0.45, 0.9, 1.0)},
	&"ember_shard": {"name": "Ember Shard", "effect": "+15% Fire Ball damage", "damage": 0.15, "color": Color(1.0, 0.5, 0.2)},
	&"heart_crystal": {"name": "Heart Crystal", "effect": "+25 max HP", "max_health": 25.0, "color": Color(1.0, 0.3, 0.45)},
	# Miniboss reward pool ("miniboss": true): offered two at a time after a
	# miniboss (pick one), never placed by RoomSpec.item. Not part of any synergy.
	&"quickening_rune": {"name": "Quickening Rune", "effect": "-8% spell cooldown", "cooldown": 0.08,
			"color": Color(0.55, 0.8, 1.0), "miniboss": true},
	&"warding_charm": {"name": "Warding Charm", "effect": "-10% damage taken", "damage_taken": -0.1,
			"color": Color(0.6, 1.0, 0.6), "miniboss": true},
	&"fury_idol": {"name": "Fury Idol", "effect": "+12% spell damage", "damage": 0.12,
			"color": Color(1.0, 0.35, 0.25), "miniboss": true},
	&"bloodstone": {"name": "Bloodstone", "effect": "+15 max HP, +3% move speed", "max_health": 15.0, "speed": 0.03,
			"color": Color(0.85, 0.2, 0.5), "miniboss": true},
}

## Post-boss relics (same effect keys); exactly one can be chosen per run.
const RELICS := {
	&"wind_relic": {"name": "Wind Relic", "effect": "+5% move speed", "speed": 0.05},
	&"ember_relic": {"name": "Ember Relic", "effect": "+20% Fire Ball damage", "damage": 0.2},
	&"vital_relic": {"name": "Vital Relic", "effect": "+30 max HP, heal 30", "max_health": 30.0},
}

## Treasure-room chest rewards (same effect keys, plus "gold" and "heal"),
## each claimable once per run. Kept below the boss relics in strength.
const TREASURES := {
	&"survivor_cache": {"name": "Survivor's Cache", "effect": "+150 gold, restore 50 HP", "gold": 150, "heal": 50.0},
	&"rune_sigil": {"name": "Rune Sigil", "effect": "-10% spell cooldown", "cooldown": 0.1},
}

## Effect keys that give lasting stat bonuses (summed by _bonus_sum()).
const STAT_KEYS: Array[String] = ["max_health", "damage", "cooldown", "speed"]

## XP needed for level 1 -> 2; level N -> N+1 needs N times this.
@export var xp_per_level: int = 50
## Mage max HP gained per level-up.
@export var max_health_per_level: float = 20.0
## Mage HP restored per level-up.
@export var heal_per_level: float = 20.0
## Spell damage bonus per Mage level above 1 (0.05 = +5%). Applied only in
## spell_damage_multiplier().
@export var damage_bonus_per_level: float = 0.05

var level: int = 1
## XP towards the next level (always 0 at MAX_LEVEL).
var xp: int = 0
var currency: int = 0
## Owned anvil upgrade ids (id -> stack count). Counts persist across dungeon
## levels; `_level_purchased` remembers what was bought on the current level.
var purchased := {}
## Owned item ids (id -> stack count, at most MAX_STACKS), in pickup order.
## Counts persist across dungeon levels; `_level_collected` only remembers what
## was picked up on the current level (pickups refresh each level).
var collected := {}
## Set once when the boss dies (its reward is granted through add_rewards()).
var boss_defeated := false
## Latest chosen post-boss relic id (&"" until chosen) and every relic chosen
## this run in order (one per boss; repeats stack).
var relic: StringName = &""
var relics: Array[StringName] = []
## Dungeon level (1 = first dungeon; independent of the Mage's XP `level`),
## the level the run started at and whether it is a level-select replay run
## (replays never save records or unlock difficulties).
var dungeon_level: int = 1
var start_level: int = 1
var is_replay := false
## Seconds played this run / this dungeon level (advanced by the Dungeon).
var run_time: float = 0.0
var level_time: float = 0.0
## Owned treasure ids (id -> stack count, at most MAX_STACKS), in claim order.
## Chests refresh each level through `_level_treasures`.
var treasures := {}
## Encounter enemies defeated this run (including the boss).
var enemies_defeated: int = 0
## Run difficulty (Difficulty.Tier) and Pact id (&"" = none), set by configure().
var difficulty: int = Difficulty.Tier.NORMAL
var pact: StringName = &""
## Gold gained this run, and the parts of it from the difficulty bonus and
## from other multipliers (Pact, treasure bonuses).
var gold_earned: int = 0
var difficulty_bonus_gold: int = 0
var modifier_bonus_gold: int = 0
## Owned consumables (id -> count, at most CONSUMABLES[id]["max"]).
var consumables := {}
## Seconds of Speed Potion effect left (0 = inactive); advanced by the Dungeon
## with active play time through advance_speed_potion().
var speed_potion_remaining: float = 0.0

## Run seed for EncounterPlanner (set once by the Dungeon when the run starts;
## kept by reset()). Each dungeon level is planned from level_seed().
var run_seed: int = 0
## If non-zero, the Dungeon uses this as the next runs' seed instead of a
## random one (tests and bug reproduction).
static var seed_override: int = 0

## If > 0, used instead of MageLevels.xp_multiplier() (see xp_multiplier()).
var xp_multiplier_override: float = 0.0

var _configured := false
var _relic_claimed := false
var _level_collected := {}
var _level_purchased := {}
var _level_treasures := {}
var _xp_fraction := 0.0
var _active_synergies: Array[StringName] = []
## This level's Ancient Seal source ids (set by the Dungeon) and the ones collected.
var _seal_sources: Array[StringName] = []
var _level_seals := {}


func xp_to_next_level() -> int:
	return xp_per_level * level


func is_max_level() -> bool:
	return level >= max_level()


## Mage level cap of the current dungeon level (also the boss gate).
func max_level() -> int:
	return MageLevels.cap(dungeon_level)


## Mage level needed to enter a room needing `base` (RoomSpec.required_level)
## on the current dungeon level.
func room_gate(base: int, is_boss: bool) -> int:
	return MageLevels.gate(base, is_boss, dungeon_level)


## Multiplier on enemy XP for the current dungeon level. A positive
## `xp_multiplier_override` replaces it (tuning / tests that need raw XP).
func xp_multiplier() -> float:
	if xp_multiplier_override > 0.0:
		return xp_multiplier_override
	return MageLevels.xp_multiplier(dungeon_level, xp_per_level)


## Encounter seed of the current dungeon level.
func level_seed() -> int:
	return EncounterPlanner.level_seed(run_seed, dungeon_level)


## Sets the run's difficulty and Pact once, before the run starts. Returns
## false (and changes nothing) if already configured or the values are unknown.
func configure(p_difficulty: int, p_pact: StringName = &"", p_start_level: int = 1) -> bool:
	if _configured or not Difficulty.is_valid(p_difficulty) or (not p_pact.is_empty() and not Pacts.PACTS.has(p_pact)):
		return false
	_configured = true
	difficulty = p_difficulty
	pact = p_pact
	start_level = maxi(p_start_level, 1)
	dungeon_level = start_level
	is_replay = start_level > 1
	# A practice run starts at the Mage level a normal run would arrive with
	# (levels only, no items or relics); the Dungeon applies the level-up HP.
	level = MageLevels.arrival_level(start_level)
	_notify()
	return true


## Moves to the next dungeon level once its boss is beaten and the relic was
## chosen. Only level state resets (boss flag, relic choice, level timer);
## the build (upgrades, items, relics, treasures, gold, XP, consumables and
## the Speed Potion timer) is kept.
## Returns false if the boss is alive or no relic was chosen yet.
func begin_next_level() -> bool:
	if not boss_defeated or not _relic_claimed:
		return false
	dungeon_level += 1
	boss_defeated = false
	_relic_claimed = false
	level_time = 0.0
	# Pickups and chests refresh; owned counts are kept.
	_level_collected.clear()
	_level_treasures.clear()
	_level_purchased.clear()
	# Ancient Seals are a per-level objective; the Dungeon registers the new sources.
	_level_seals.clear()
	_seal_sources.clear()
	_notify()
	return true


## Registers this dungeon level's Ancient Seal source ids (the Dungeon does
## this when it plans a level). Seals already collected on this level are kept.
func set_seal_sources(ids: Array[StringName]) -> void:
	_seal_sources = ids.duplicate()
	_notify()


func seal_sources() -> Array[StringName]:
	return _seal_sources.duplicate()


## True if `id` is one of this level's seal sources and was not collected yet.
func can_collect_seal(id: StringName) -> bool:
	return _seal_sources.has(id) and not _level_seals.has(id)


func is_seal_collected(id: StringName) -> bool:
	return _level_seals.has(id)


## Collects Ancient Seal `id` once per dungeon level. Returns false (and
## changes nothing) for unknown sources and seals already collected.
func collect_seal(id: StringName) -> bool:
	if not can_collect_seal(id):
		return false
	_level_seals[id] = true
	_notify()
	seal_collected.emit(id)
	return true


## Ancient Seals collected on this dungeon level.
func seals_collected() -> int:
	return _level_seals.size()


## True once SEALS_REQUIRED seals are collected on this dungeon level.
func seals_complete() -> bool:
	return seals_collected() >= SEALS_REQUIRED


## "mm:ss" (or "h:mm:ss" from one hour).
static func format_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%02d:%02d" % [total / 60, total % 60]


## Raw rewards (no multipliers); the gold counts as earned.
func add_rewards(xp_amount: int, currency_amount: int) -> void:
	currency += maxi(currency_amount, 0)
	gold_earned += maxi(currency_amount, 0)
	xp += maxi(xp_amount, 0)
	var levels_gained: Array[int] = []
	while not is_max_level() and xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		levels_gained.append(level)
	if is_max_level():
		xp = 0
	_notify()
	for new_level in levels_gained:
		leveled_up.emit(new_level)


## True if upgrade `id` was bought on the current dungeon level (not available again until the next).
func is_purchased(id: StringName) -> bool:
	return _level_purchased.has(id)


## Stacks of upgrade `id` owned this run.
func upgrade_stacks(id: StringName) -> int:
	return purchased.get(id, 0)


func upgrade_max_stacks(id: StringName) -> int:
	return UPGRADES[id].get("max_stacks", 1) if UPGRADES.has(id) else 0


## Price of the next stack of `id` (the last price once the cap is reached).
func upgrade_cost(id: StringName) -> int:
	if not UPGRADES.has(id):
		return 0
	var prices: Array = UPGRADES[id]["prices"]
	return roundi(prices[mini(upgrade_stacks(id), prices.size() - 1)] * (1.0 + _bonus_sum(&"upgrade_cost")))


## Mage level needed to buy `id` on the current dungeon level.
func upgrade_level(id: StringName) -> int:
	return (UPGRADES[id].get("level", 1) + MageLevels.offset(dungeon_level)) if UPGRADES.has(id) else 1


## First dungeon level on which upgrade `id` is sold.
func upgrade_min_dungeon_level(id: StringName) -> int:
	return UPGRADES[id].get("min_dungeon_level", 1) if UPGRADES.has(id) else 1


## True once Twin Cast was bought this run.
func has_twin_cast() -> bool:
	return upgrade_stacks(&"twin_cast") > 0


## Projectiles per cast (2 only through Twin Cast; no other system changes this).
func projectile_count() -> int:
	return TWIN_CAST_COUNT if has_twin_cast() else 1


## Damage factor of each projectile of a cast.
func projectile_damage_factor() -> float:
	return TWIN_CAST_DAMAGE_FACTOR if has_twin_cast() else 1.0


## True if `id` exists, is sold on this dungeon level, was not bought this level,
## is below its stack cap, is affordable and the Mage level is high enough.
func can_purchase(id: StringName) -> bool:
	return UPGRADES.has(id) and dungeon_level >= upgrade_min_dungeon_level(id) and not is_purchased(id) \
			and upgrade_stacks(id) < upgrade_max_stacks(id) and currency >= upgrade_cost(id) and level >= upgrade_level(id)


## Buys one stack of upgrade `id`, deducting its cost. Returns false (and
## changes nothing) if it is unknown, bought this level, at its stack cap,
## unaffordable or level-locked.
func purchase(id: StringName) -> bool:
	if not can_purchase(id):
		return false
	currency -= upgrade_cost(id)
	purchased[id] = upgrade_stacks(id) + 1
	_level_purchased[id] = true
	_notify()
	upgrade_purchased.emit(id)
	return true


func consumable_count(id: StringName) -> int:
	return consumables.get(id, 0)


func consumable_max(id: StringName) -> int:
	return CONSUMABLES[id]["max"] if CONSUMABLES.has(id) else 0


func consumable_price(id: StringName) -> int:
	return CONSUMABLES[id]["price"] if CONSUMABLES.has(id) else 0


## True if `id` exists, its inventory is below the cap and it is affordable.
func can_buy_consumable(id: StringName) -> bool:
	return CONSUMABLES.has(id) and consumable_count(id) < consumable_max(id) and currency >= consumable_price(id)


## Buys one `id`, deducting its price. Returns false (and changes nothing)
## if it is unknown, the inventory is full or the gold is too low.
func buy_consumable(id: StringName) -> bool:
	if not can_buy_consumable(id):
		return false
	currency -= consumable_price(id)
	consumables[id] = consumable_count(id) + 1
	_notify()
	consumable_bought.emit(id)
	return true


## Spends one `id`. Returns false (and changes nothing) if none is owned.
## The effect is applied by the caller (or by use_speed_potion()).
func use_consumable(id: StringName) -> bool:
	if consumable_count(id) <= 0:
		return false
	consumables[id] = consumable_count(id) - 1
	if consumables[id] == 0:
		consumables.erase(id)
	_notify()
	consumable_used.emit(id)
	return true


func speed_potion_duration() -> float:
	return CONSUMABLES[&"speed_potion"]["duration"]


func is_speed_potion_active() -> bool:
	return speed_potion_remaining > 0.0


## True if a Speed Potion is owned and drinking it would add time (it is not
## spent while the effect is still at its full duration).
func can_use_speed_potion() -> bool:
	return consumable_count(&"speed_potion") > 0 and speed_potion_remaining < speed_potion_duration()


## Drinks a Speed Potion: spends one and sets the effect to its full duration
## (refresh, never stacking). Returns false if none is owned or it is already full.
func use_speed_potion() -> bool:
	if not can_use_speed_potion():
		return false
	speed_potion_remaining = speed_potion_duration()
	return use_consumable(&"speed_potion")


## Advances the Speed Potion effect by `delta` seconds of active play; emits
## `changed` and speed_potion_expired when it runs out.
func advance_speed_potion(delta: float) -> void:
	if speed_potion_remaining <= 0.0 or delta <= 0.0:
		return
	speed_potion_remaining = maxf(speed_potion_remaining - delta, 0.0)
	if speed_potion_remaining == 0.0:
		_notify()
		speed_potion_expired.emit()


## True if item `id` was picked up on the current dungeon level.
func is_collected(id: StringName) -> bool:
	return _level_collected.has(id)


## True if a pickup of item `id` can still be taken: it is a known item, not
## taken on this level and not already at MAX_STACKS.
func can_collect(id: StringName) -> bool:
	return ITEMS.has(id) and not is_collected(id) and stack_count(id) < MAX_STACKS


## Item ids offered by miniboss reward choices (ITEMS with "miniboss").
static func miniboss_reward_pool() -> Array[StringName]:
	var pool: Array[StringName] = []
	for id: StringName in ITEMS:
		if ITEMS[id].get("miniboss", false):
			pool.append(id)
	return pool


## Owned copies of item or treasure `id`.
func stack_count(id: StringName) -> int:
	return collected.get(id, 0) + treasures.get(id, 0)


## Collects item `id` (one stack, once per dungeon level). Returns false (and
## changes nothing) if it is unknown, taken this level or at MAX_STACKS.
func collect_item(id: StringName) -> bool:
	if not can_collect(id):
		return false
	_level_collected[id] = true
	collected[id] = collected.get(id, 0) + 1
	_notify()
	item_collected.emit(id)
	return true


## Chooses relic `id` once per boss, after the boss is defeated. Returns false
## (and changes nothing) if it is unknown, this boss's relic was already
## chosen or the boss lives.
func choose_relic(id: StringName) -> bool:
	if not RELICS.has(id) or _relic_claimed or not boss_defeated:
		return false
	_relic_claimed = true
	relic = id
	relics.append(id)
	_notify()
	relic_chosen.emit(id)
	return true


## True if treasure `id` was claimed on the current dungeon level.
func is_treasure_claimed(id: StringName) -> bool:
	return _level_treasures.has(id)


## Claims treasure `id` (once per dungeon level), paying its gold and adding
## one stack of its bonus (up to MAX_STACKS; at the cap only gold / heal are
## paid). Returns false (and changes nothing) if it is unknown or claimed this level.
func claim_treasure(id: StringName) -> bool:
	if not TREASURES.has(id) or is_treasure_claimed(id):
		return false
	_level_treasures[id] = true
	treasures[id] = mini(treasures.get(id, 0) + 1, MAX_STACKS)
	var gold := _scaled_gold(int(TREASURES[id].get("gold", 0)), treasure_reward_multiplier())
	currency += gold
	gold_earned += gold
	_notify()
	treasure_claimed.emit(id)
	return true


## Grants an enemy's rewards: XP unscaled, gold scaled by gold_multiplier().
## Returns the gold granted.
func grant_enemy_rewards(xp_amount: int, base_gold: int) -> int:
	var gold := _scaled_gold(base_gold, 1.0)
	# XP scales with the dungeon level; the fraction is carried so the budget is exact.
	var scaled := xp_amount * xp_multiplier() + _xp_fraction
	var whole := floori(scaled)
	_xp_fraction = scaled - whole
	add_rewards(whole, gold)
	return gold


## Spell damage multiplier from level, upgrades, items, Pact and synergies (1.0 = base).
func spell_damage_multiplier() -> float:
	return maxf(1.0 + damage_bonus_per_level * (level - 1) + _bonus_sum(&"damage") + gold_damage_bonus(), 0.1)


## Greed's Reward: damage bonus from carried gold (0 when inactive).
func gold_damage_bonus() -> float:
	var per_step := _bonus_sum(&"gold_damage")
	if per_step <= 0.0:
		return 0.0
	return minf(floorf(currency / float(Pacts.GOLD_DAMAGE_STEP)) * per_step, Pacts.GOLD_DAMAGE_CAP)


## Spell cooldown multiplier from upgrades/items (1.0 = base, lower = faster).
func spell_cooldown_multiplier() -> float:
	return maxf(1.0 - _bonus_sum(&"cooldown"), 0.1)


## Mage movement speed multiplier from upgrades/items (1.0 = base), capped at
## MAX_MOVE_SPEED_MULTIPLIER.
func move_speed_multiplier() -> float:
	return clampf(1.0 + _bonus_sum(&"speed"), 0.1, MAX_MOVE_SPEED_MULTIPLIER)


## The Mage's actual movement multiplier: move_speed_multiplier() times the
## Speed Potion factor while it is active, capped at MAX_MOVE_SPEED_WITH_POTION.
## Enemy catch-up pacing keeps using move_speed_multiplier() (no potion).
func effective_move_speed_multiplier() -> float:
	var multiplier := move_speed_multiplier()
	if not is_speed_potion_active():
		return multiplier
	return minf(multiplier * float(CONSUMABLES[&"speed_potion"]["speed_factor"]), MAX_MOVE_SPEED_WITH_POTION)


## Mage max HP multiplier (applies to base max HP and every max HP gain).
func max_health_multiplier() -> float:
	return maxf(1.0 + _bonus_sum(&"max_health_mult"), 0.1)


## Multiplier on all damage the Mage takes.
func damage_taken_multiplier() -> float:
	return maxf(1.0 + _bonus_sum(&"damage_taken"), 0.0)


## Multiplier on healing from every source except kill_heal().
func healing_multiplier() -> float:
	return maxf(1.0 + _bonus_sum(&"healing"), 0.0)


## HP healed per enemy defeated (Blood Pact; not reduced by healing_multiplier()).
func kill_heal() -> float:
	return _bonus_sum(&"kill_heal")


## Next-cast cooldown reduction after a Fire Ball hit (0 = none).
func cast_momentum() -> float:
	return clampf(_bonus_sum(&"momentum"), 0.0, 0.9)


## Gold reward multiplier: difficulty x (1 + Pact gold bonus).
func gold_multiplier() -> float:
	return Difficulty.data(difficulty)["gold"] * (1.0 + _bonus_sum(&"gold_reward"))


## Treasure chest gold/heal multiplier (on top of gold_multiplier() for gold).
func treasure_reward_multiplier() -> float:
	return 1.0 + _bonus_sum(&"treasure_reward")


## The player's damage output: damage multiplier x projectiles per cast (Twin Cast
## 2 x 0.7 = 1.4) / cooldown multiplier. Includes Mage level, upgrades, items,
## relics, Pact and synergies; excludes Greed's gold-based bonus and Arcane Momentum.
func player_output() -> float:
	var damage := maxf(1.0 + damage_bonus_per_level * (level - 1) + _bonus_sum(&"damage"), 0.1)
	return damage * projectile_count() * projectile_damage_factor() / spell_cooldown_multiplier()


## Extra enemy HP multiplier for the current player output (1.0 .. 2.0). The Dungeon
## snapshots it when a room is created, so it never changes inside a room.
func output_hp_modifier() -> float:
	return LevelScaling.output_hp_modifier(player_output(), dungeon_level)


## Enemy max HP multiplier (`treasure_room`: the enemy belongs to a treasure room;
## `category`: its level curve, see LevelScaling.category_of()).
func enemy_health_multiplier(treasure_room: bool = false,
		category: LevelScaling.Category = LevelScaling.Category.REGULAR) -> float:
	var bonus := _bonus_sum(&"enemy_health") + (_bonus_sum(&"treasure_enemy_health") if treasure_room else 0.0)
	return Difficulty.data(difficulty)["enemy_health"] * LevelScaling.enemy_health(dungeon_level, category) * (1.0 + bonus)


## Multiplier on all damage an enemy deals (`category`: its level curve).
func enemy_damage_multiplier(elite: bool = false, treasure_room: bool = false,
		category: LevelScaling.Category = LevelScaling.Category.REGULAR) -> float:
	var result: float = Difficulty.data(difficulty)["enemy_damage"] * LevelScaling.enemy_damage(dungeon_level, category) \
			* ENEMY_DAMAGE_FACTOR
	if treasure_room:
		result *= 1.0 + _bonus_sum(&"treasure_enemy_damage")
	if elite:
		result *= 1.0 + _bonus_sum(&"elite_damage")
	return result


## Enemy attack rate multiplier (cooldowns, projectile speed): difficulty x
## level x the global Tempo.ENEMY_ATTACK (Issue #51). `category`: the level curve.
func enemy_pace_multiplier(category: LevelScaling.Category = LevelScaling.Category.REGULAR) -> float:
	return Difficulty.data(difficulty)["enemy_pace"] * LevelScaling.enemy_pace(dungeon_level, category) * Tempo.ENEMY_ATTACK


## Divisor of enemy post-attack recovery pauses: the fixed Tempo.ENEMY_RECOVERY,
## never compounded with difficulty or level pace (Issue #51 Stage 5).
func enemy_recovery_multiplier() -> float:
	return Tempo.ENEMY_RECOVERY


## Normal Goblin swings before its special attack (1-3): fewer on harder
## difficulties and deeper dungeon levels (Difficulty "goblin_swings" x LevelScaling brackets).
func goblin_swings_before_special() -> int:
	var swings: Array = Difficulty.data(difficulty)["goblin_swings"]
	return clampi(swings[mini(LevelScaling.goblin_swing_bracket(dungeon_level), swings.size() - 1)], 1, 3)


## Enemy move speed multiplier: difficulty x level x bounded catch-up on the
## Mage's speed bonus x the global Tempo.ENEMY_MOVE (Issue #51).
## Enemy.apply_scaling() also caps the result at LevelScaling.MAX_PURSUER_SPEED.
## `category`: the level curve.
func enemy_move_pace_multiplier(category: LevelScaling.Category = LevelScaling.Category.REGULAR) -> float:
	return Difficulty.data(difficulty)["enemy_move_pace"] * LevelScaling.enemy_move_pace(dungeon_level, category) \
			* LevelScaling.player_catchup(move_speed_multiplier()) * Tempo.ENEMY_MOVE


## Multiplier on damage an enemy takes from the Mage.
func enemy_vulnerability_multiplier(elite: bool = false) -> float:
	return 1.0 + (_bonus_sum(&"elite_vulnerability") if elite else 0.0)


## Extra enemies for a combat room needing `required_level` that has
## `free_points` free safe spawn points: the difficulty's extras plus the
## level's (LevelScaling.room_extra_enemies), capped at MAX_EXTRA_ENEMIES and
## at the free points. Boss and treasure rooms never ask for extras.
func extra_room_enemies(required_level: int, free_points: int) -> int:
	var total := Difficulty.extra_enemies(difficulty, required_level) + LevelScaling.room_extra_enemies(
			dungeon_level, required_level >= 2, free_points)
	return clampi(total, 0, mini(MAX_EXTRA_ENEMIES, maxi(free_points, 0)))


## Extra enemies per survival wave (difficulty + level, capped at MAX_EXTRA_ENEMIES).
func extra_wave_enemies() -> int:
	return mini(Difficulty.data(difficulty)["extra_wave"] + LevelScaling.wave_extra_enemies(dungeon_level), MAX_EXTRA_ENEMIES)


## True if `id` (Pact, item, treasure, upgrade or relic) is owned this run.
func owns(id: StringName) -> bool:
	return pact == id or relics.has(id) or collected.has(id) or treasures.has(id) or purchased.has(id)


func is_synergy_active(id: StringName) -> bool:
	if not Pacts.SYNERGIES.has(id):
		return false
	for group: Array in Pacts.SYNERGIES[id]["requires"]:
		if not group.any(owns):
			return false
	return true


## Inactive synergies that owning `id` as well would activate (UI hints).
func synergies_completed_by(id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for synergy: StringName in Pacts.SYNERGIES:
		if is_synergy_active(synergy):
			continue
		var groups: Array = Pacts.SYNERGIES[synergy]["requires"]
		if groups.all(func(group: Array) -> bool: return group.has(id) or group.any(owns)):
			result.append(synergy)
	return result


## Active synergy ids, in Pacts.SYNERGIES order.
func active_synergies() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in Pacts.SYNERGIES:
		if is_synergy_active(id):
			result.append(id)
	return result


func reset() -> void:
	level = MageLevels.arrival_level(start_level)
	xp = 0
	currency = 0
	purchased.clear()
	_level_purchased.clear()
	collected.clear()
	treasures.clear()
	_level_collected.clear()
	_level_treasures.clear()
	_xp_fraction = 0.0
	boss_defeated = false
	relic = &""
	relics.clear()
	_relic_claimed = false
	_level_seals.clear()
	dungeon_level = start_level
	run_time = 0.0
	level_time = 0.0
	enemies_defeated = 0
	gold_earned = 0
	difficulty_bonus_gold = 0
	modifier_bonus_gold = 0
	consumables.clear()
	speed_potion_remaining = 0.0
	_active_synergies.clear()
	_notify()


## `base` gold scaled by gold_multiplier() and `extra`; tracks the bonus parts.
func _scaled_gold(base: int, extra: float) -> int:
	base = maxi(base, 0)
	var with_difficulty := roundi(base * float(Difficulty.data(difficulty)["gold"]))
	var total := roundi(base * gold_multiplier() * extra)
	difficulty_bonus_gold += with_difficulty - base
	modifier_bonus_gold += total - with_difficulty
	return total


## Emits `changed`, then synergy_activated for each newly active synergy.
func _notify() -> void:
	var now := active_synergies()
	var new_ids := now.filter(func(id: StringName) -> bool: return not _active_synergies.has(id))
	_active_synergies = now
	changed.emit()
	for id: StringName in new_ids:
		synergy_activated.emit(id)


## Sum of effect `key` over purchased upgrades, collected items, claimed
## treasures, the relic, the Pact and active synergies.
func _bonus_sum(key: String) -> float:
	var total := 0.0
	for id: StringName in purchased:
		total += UPGRADES[id].get(key, 0.0) * purchased[id]
	for id: StringName in collected:
		total += ITEMS[id].get(key, 0.0) * collected[id]
	for id: StringName in treasures:
		total += TREASURES[id].get(key, 0.0) * treasures[id]
	for id: StringName in relics:
		total += RELICS[id].get(key, 0.0)
	if Pacts.PACTS.has(pact):
		total += Pacts.PACTS[pact].get(key, 0.0)
	for id: StringName in Pacts.SYNERGIES:
		if Pacts.SYNERGIES[id].has(key) and is_synergy_active(id):
			total += Pacts.SYNERGIES[id][key]
	return total
