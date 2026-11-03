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
##
## Run configuration: configure() sets the run's difficulty (Difficulty.TIERS)
## and Pact (Pacts.PACTS) once. Pact and active synergy (Pacts.SYNERGIES)
## effect keys join the same on-demand bonus sums, so they cannot stack; the
## enemy_*() getters give the fixed per-enemy scaling the Dungeon applies once
## per enemy. Gold from kills and treasures goes through gold_multiplier().

signal changed
signal leveled_up(level: int)
signal upgrade_purchased(id: StringName)
signal item_collected(id: StringName)
signal relic_chosen(id: StringName)
signal treasure_claimed(id: StringName)
## Emitted once when a synergy's required relics become owned.
signal synergy_activated(id: StringName)

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
## Run difficulty (Difficulty.Tier) and Pact id (&"" = none), set by configure().
var difficulty: int = Difficulty.Tier.NORMAL
var pact: StringName = &""
## Gold gained this run, and the parts of it from the difficulty bonus and
## from other multipliers (Pact, treasure bonuses).
var gold_earned: int = 0
var difficulty_bonus_gold: int = 0
var modifier_bonus_gold: int = 0

var _configured := false
var _active_synergies: Array[StringName] = []


func xp_to_next_level() -> int:
	return xp_per_level * level


func is_max_level() -> bool:
	return level >= MAX_LEVEL


## Sets the run's difficulty and Pact once, before the run starts. Returns
## false (and changes nothing) if already configured or the values are unknown.
func configure(p_difficulty: int, p_pact: StringName = &"") -> bool:
	if _configured or not Difficulty.is_valid(p_difficulty) or (not p_pact.is_empty() and not Pacts.PACTS.has(p_pact)):
		return false
	_configured = true
	difficulty = p_difficulty
	pact = p_pact
	_notify()
	return true


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


func is_purchased(id: StringName) -> bool:
	return purchased.has(id)


func upgrade_cost(id: StringName) -> int:
	return roundi(UPGRADES[id]["cost"] * (1.0 + _bonus_sum(&"upgrade_cost"))) if UPGRADES.has(id) else 0


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
	_notify()
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
	_notify()
	item_collected.emit(id)
	return true


## Chooses relic `id` once, after the boss is defeated. Returns false (and
## changes nothing) if it is unknown, a relic was already chosen or the boss lives.
func choose_relic(id: StringName) -> bool:
	if not RELICS.has(id) or not relic.is_empty() or not boss_defeated:
		return false
	relic = id
	_notify()
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
	add_rewards(xp_amount, gold)
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


## Mage movement speed multiplier from upgrades/items (1.0 = base).
func move_speed_multiplier() -> float:
	return 1.0 + _bonus_sum(&"speed")


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


## Enemy max HP multiplier (`treasure_room`: the enemy belongs to a treasure room).
func enemy_health_multiplier(treasure_room: bool = false) -> float:
	var bonus := _bonus_sum(&"enemy_health") + (_bonus_sum(&"treasure_enemy_health") if treasure_room else 0.0)
	return Difficulty.data(difficulty)["enemy_health"] * (1.0 + bonus)


## Multiplier on all damage an enemy deals.
func enemy_damage_multiplier(elite: bool = false, treasure_room: bool = false) -> float:
	var result: float = Difficulty.data(difficulty)["enemy_damage"]
	if treasure_room:
		result *= 1.0 + _bonus_sum(&"treasure_enemy_damage")
	if elite:
		result *= 1.0 + _bonus_sum(&"elite_damage")
	return result


## Enemy move speed and attack rate multiplier.
func enemy_pace_multiplier() -> float:
	return Difficulty.data(difficulty)["enemy_pace"]


## Multiplier on damage an enemy takes from the Mage.
func enemy_vulnerability_multiplier(elite: bool = false) -> float:
	return 1.0 + (_bonus_sum(&"elite_vulnerability") if elite else 0.0)


## Extra enemies for a combat room needing `required_level`.
func extra_room_enemies(required_level: int) -> int:
	return Difficulty.extra_enemies(difficulty, required_level)


## Extra enemies per survival wave.
func extra_wave_enemies() -> int:
	return Difficulty.data(difficulty)["extra_wave"]


## Seconds added to the survival trial.
func survival_time_bonus() -> float:
	return _bonus_sum(&"survival_time")


## True if `id` (Pact, item, treasure, upgrade or relic) is owned this run.
func owns(id: StringName) -> bool:
	return pact == id or relic == id or collected.has(id) or treasures.has(id) or purchased.has(id)


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
	level = 1
	xp = 0
	currency = 0
	purchased.clear()
	collected.clear()
	treasures.clear()
	boss_defeated = false
	relic = &""
	enemies_defeated = 0
	gold_earned = 0
	difficulty_bonus_gold = 0
	modifier_bonus_gold = 0
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
		total += UPGRADES[id].get(key, 0.0)
	for id: StringName in collected:
		total += ITEMS[id].get(key, 0.0)
	for id: StringName in treasures:
		total += TREASURES[id].get(key, 0.0)
	if not relic.is_empty():
		total += RELICS[relic].get(key, 0.0)
	if Pacts.PACTS.has(pact):
		total += Pacts.PACTS[pact].get(key, 0.0)
	for id: StringName in Pacts.SYNERGIES:
		if Pacts.SYNERGIES[id].has(key) and is_synergy_active(id):
			total += Pacts.SYNERGIES[id][key]
	return total
