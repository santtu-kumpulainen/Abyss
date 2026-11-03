class_name RunState
extends Node
## Run-level progression: XP, level, currency and anvil upgrades for the
## current dungeon run. Lives in the Dungeon scene, so it persists across room
## transitions and is recreated (reset) when the run restarts. Nothing is saved
## to disk.
##
## Leveling: reaching xp_to_next_level() XP raises the level by one; leftover
## XP carries over. The XP needed grows by `xp_per_level` each level
## (50, 100 by default). The level is capped at MAX_LEVEL; XP gained there is
## discarded. Each level-up emits `leveled_up`; the owner applies the reward
## (the Dungeon uses max_health_per_level/heal_per_level). Spell bonuses are
## read through spell_damage_multiplier()/spell_cooldown_multiplier().
##
## Upgrades (UPGRADES) are one-time purchases for the current run, gated by
## gold and a required level. Items (ITEMS) are collected once per run from
## room pickups. Stat bonuses from both are summed on demand, so re-applying
## them never stacks. After the boss dies, one relic (RELICS) can be chosen
## once; it adds to the same bonus sums. Treasure chests (TREASURES) in the
## optional treasure rooms are claimed once per run: their gold is added once,
## stat keys join the bonus sums and "heal" is applied by the owner.
##
## Economy (current dungeon, full clear): tier-1 rooms (Lv 1) give ~56 XP and
## ~246 gold, tier-2 rooms (Lv 2) ~114 XP and ~488 gold, so a Mage reaches the
## boss with roughly 650-730 gold. All three upgrades cost 800 together: the
## player can afford two of them, not everything.

signal changed
signal leveled_up(level: int)
signal upgrade_purchased(id: StringName)
signal item_collected(id: StringName)
signal relic_chosen(id: StringName)
signal treasure_claimed(id: StringName)

const MAX_LEVEL := 3

## One-time anvil upgrades, in display order. "level" is the Mage level needed.
## Effect keys: max_health (flat), damage (multiplier bonus), cooldown
## (multiplier reduction), speed (multiplier bonus).
const UPGRADES := {
	&"vitality": {"name": "Vitality", "cost": 100, "level": 1, "effect": "+20 max HP", "max_health": 20.0},
	&"quick_cast": {"name": "Quick Cast", "cost": 250, "level": 2, "effect": "-20% spell cooldown", "cooldown": 0.2},
	&"ember_core": {"name": "Ember Core", "cost": 450, "level": 3, "effect": "+40% spell damage", "damage": 0.4},
}

## Collectible run items (same effect keys as UPGRADES), placed in rooms by RoomSpec.item.
const ITEMS := {
	&"swift_boots": {"name": "Swift Boots", "effect": "+15% move speed", "speed": 0.15, "color": Color(0.45, 0.9, 1.0)},
	&"ember_shard": {"name": "Ember Shard", "effect": "+15% Fire Ball damage", "damage": 0.15, "color": Color(1.0, 0.5, 0.2)},
	&"heart_crystal": {"name": "Heart Crystal", "effect": "+25 max HP", "max_health": 25.0, "color": Color(1.0, 0.3, 0.45)},
}

## Post-boss relics (same effect keys); exactly one can be chosen per run.
const RELICS := {
	&"wind_relic": {"name": "Wind Relic", "effect": "+10% move speed", "speed": 0.1},
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
## Spell damage bonus per level above 1 (0.1 = +10%).
@export var damage_bonus_per_level: float = 0.1

var level: int = 1
## XP towards the next level (always 0 at MAX_LEVEL).
var xp: int = 0
var currency: int = 0
## Purchased upgrade ids (id -> true).
var purchased := {}
## Collected item ids (id -> true), in pickup order.
var collected := {}
## Set once when the boss dies (its reward is granted through add_rewards()).
var boss_defeated := false
## Chosen post-boss relic id (&"" until chosen).
var relic: StringName = &""
## Claimed treasure ids (id -> true), in claim order.
var treasures := {}
## Encounter enemies defeated this run (including the boss).
var enemies_defeated: int = 0


func xp_to_next_level() -> int:
	return xp_per_level * level


func is_max_level() -> bool:
	return level >= MAX_LEVEL


func add_rewards(xp_amount: int, currency_amount: int) -> void:
	currency += maxi(currency_amount, 0)
	xp += maxi(xp_amount, 0)
	var levels_gained: Array[int] = []
	while not is_max_level() and xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		levels_gained.append(level)
	if is_max_level():
		xp = 0
	changed.emit()
	for new_level in levels_gained:
		leveled_up.emit(new_level)


func is_purchased(id: StringName) -> bool:
	return purchased.has(id)


func upgrade_cost(id: StringName) -> int:
	return UPGRADES[id]["cost"] if UPGRADES.has(id) else 0


func upgrade_level(id: StringName) -> int:
	return UPGRADES[id].get("level", 1) if UPGRADES.has(id) else 1


## True if `id` exists, is not owned yet, is affordable and the level is high enough.
func can_purchase(id: StringName) -> bool:
	return UPGRADES.has(id) and not is_purchased(id) and currency >= upgrade_cost(id) 		and level >= upgrade_level(id)


## Buys upgrade `id` once, deducting its cost. Returns false (and changes
## nothing) if it is unknown, already owned, unaffordable or level-locked.
func purchase(id: StringName) -> bool:
	if not can_purchase(id):
		return false
	currency -= upgrade_cost(id)
	purchased[id] = true
	changed.emit()
	upgrade_purchased.emit(id)
	return true


func is_collected(id: StringName) -> bool:
	return collected.has(id)


## Collects item `id` once. Returns false (and changes nothing) if it is
## unknown or already collected this run.
func collect_item(id: StringName) -> bool:
	if not ITEMS.has(id) or is_collected(id):
		return false
	collected[id] = true
	changed.emit()
	item_collected.emit(id)
	return true


## Chooses relic `id` once, after the boss is defeated. Returns false (and
## changes nothing) if it is unknown, a relic was already chosen or the boss lives.
func choose_relic(id: StringName) -> bool:
	if not RELICS.has(id) or not relic.is_empty() or not boss_defeated:
		return false
	relic = id
	changed.emit()
	relic_chosen.emit(id)
	return true


func is_treasure_claimed(id: StringName) -> bool:
	return treasures.has(id)


## Claims treasure `id` once, adding its gold. Returns false (and changes
## nothing) if it is unknown or already claimed this run.
func claim_treasure(id: StringName) -> bool:
	if not TREASURES.has(id) or is_treasure_claimed(id):
		return false
	treasures[id] = true
	currency += int(TREASURES[id].get("gold", 0))
	changed.emit()
	treasure_claimed.emit(id)
	return true


## Spell damage multiplier from level, upgrades and items (1.0 = base).
func spell_damage_multiplier() -> float:
	return 1.0 + damage_bonus_per_level * (level - 1) + _bonus_sum(&"damage")


## Spell cooldown multiplier from upgrades/items (1.0 = base, lower = faster).
func spell_cooldown_multiplier() -> float:
	return maxf(1.0 - _bonus_sum(&"cooldown"), 0.1)


## Mage movement speed multiplier from upgrades/items (1.0 = base).
func move_speed_multiplier() -> float:
	return 1.0 + _bonus_sum(&"speed")


func reset() -> void:
	level = 1
	xp = 0
	currency = 0
	purchased.clear()
	collected.clear()
	treasures.clear()
	boss_defeated = false
	relic = &""
	enemies_defeated = 0
	changed.emit()


## Sum of effect `key` over purchased upgrades, collected items, claimed treasures and the relic.
func _bonus_sum(key: String) -> float:
	var total := 0.0
	for id: StringName in purchased:
		total += UPGRADES[id].get(key, 0.0)
	for id: StringName in collected:
		total += ITEMS[id].get(key, 0.0)
	for id: StringName in treasures:
		total += TREASURES[id].get(key, 0.0)
	if not relic.is_empty():
		total += RELICS[relic].get(key, 0.0)
	return total
