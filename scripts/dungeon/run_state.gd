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
## Upgrades (UPGRADES) are one-time purchases for the current run.

signal changed
signal leveled_up(level: int)
signal upgrade_purchased(id: StringName)

const MAX_LEVEL := 3

## One-time anvil upgrades, in display order. Effect keys:
## max_health (flat), damage (multiplier bonus), cooldown (multiplier reduction).
const UPGRADES := {
	&"vitality": {"name": "Vitality", "cost": 25, "effect": "+20 max HP", "max_health": 20.0},
	&"ember_core": {"name": "Ember Core", "cost": 35, "effect": "+25% spell damage", "damage": 0.25},
	&"quick_cast": {"name": "Quick Cast", "cost": 30, "effect": "-20% spell cooldown", "cooldown": 0.2},
}

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


## True if `id` exists, is not owned yet and is affordable.
func can_purchase(id: StringName) -> bool:
	return UPGRADES.has(id) and not is_purchased(id) and currency >= upgrade_cost(id)


## Buys upgrade `id` once, deducting its cost. Returns false (and changes
## nothing) if it is unknown, already owned or unaffordable.
func purchase(id: StringName) -> bool:
	if not can_purchase(id):
		return false
	currency -= upgrade_cost(id)
	purchased[id] = true
	changed.emit()
	upgrade_purchased.emit(id)
	return true


## Spell damage multiplier from level and upgrades (1.0 = base).
func spell_damage_multiplier() -> float:
	return 1.0 + damage_bonus_per_level * (level - 1) + _upgrade_sum(&"damage")


## Spell cooldown multiplier from upgrades (1.0 = base, lower = faster).
func spell_cooldown_multiplier() -> float:
	return maxf(1.0 - _upgrade_sum(&"cooldown"), 0.1)


func reset() -> void:
	level = 1
	xp = 0
	currency = 0
	purchased.clear()
	changed.emit()


func _upgrade_sum(key: String) -> float:
	var total := 0.0
	for id: StringName in purchased:
		total += UPGRADES[id].get(key, 0.0)
	return total
