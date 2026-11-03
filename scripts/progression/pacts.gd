class_name Pacts
extends RefCounted
## Pact relics (one, or none, chosen before a run) and relic synergies.
## Pure data: RunState sums these effect keys on demand (like its upgrade and
## item bonuses), so nothing is ever applied twice.
##
## Player-side keys (summed with RunState's bonuses): damage (spell damage
## bonus), cooldown (cooldown reduction), max_health_mult (max HP multiplier
## bonus, negative = less), healing (healing multiplier bonus for every source
## except kill_heal), kill_heal (HP per enemy defeated), damage_taken (bonus
## to all damage the Mage takes), gold_reward (gold reward bonus; not "gold",
## which is a treasure's gold amount), treasure_reward (treasure
## chest gold/heal bonus), upgrade_cost (anvil price bonus), momentum (next
## cast cooldown reduction after a Fire Ball hit), gold_damage (damage bonus
## per 20 carried gold).
## Enemy-side keys (fixed for the run, applied once per enemy at spawn):
## enemy_health (all enemies), elite_vulnerability (damage elites take from
## the Mage), elite_damage (damage elites deal), treasure_enemy_health /
## treasure_enemy_damage (treasure-room enemies only), survival_time (seconds
## added to the survival trial).

const PACTS := {
	&"glass_heart": {
		"name": "Glass Heart", "benefit": "+30% Fire Ball damage", "drawback": "-25% max HP",
		"damage": 0.3, "max_health_mult": -0.25,
	},
	&"swift_casting": {
		"name": "Swift Casting", "benefit": "-30% Fire Ball cooldown", "drawback": "-20% Fire Ball damage",
		"cooldown": 0.3, "damage": -0.2,
	},
	&"avarice": {
		"name": "Avarice", "benefit": "+40% gold rewards", "drawback": "Enemies have +20% HP",
		"gold_reward": 0.4, "enemy_health": 0.2,
	},
	&"blood_pact": {
		"name": "Blood Pact", "benefit": "Heal 4 HP per enemy defeated", "drawback": "All other healing -50%",
		"kill_heal": 4.0, "healing": -0.5,
	},
	&"hunters_mark": {
		"name": "Hunter's Mark", "benefit": "+40% damage to elites and the boss",
		"drawback": "Take +30% damage from elites and the boss",
		"elite_vulnerability": 0.4, "elite_damage": 0.3,
	},
	&"treasure_seeker": {
		"name": "Treasure Seeker", "benefit": "Treasure chest gold and healing x1.75",
		"drawback": "Treasure-room enemies +30% HP and damage; survival trial +20 s",
		"treasure_reward": 0.75, "treasure_enemy_health": 0.3, "treasure_enemy_damage": 0.3, "survival_time": 20.0,
	},
}

## Synergies: active while every group in "requires" has at least one owned
## id (the Pact, a collected item, a claimed treasure, an upgrade or the
## post-boss relic). Add an entry here to add a combination.
const SYNERGIES := {
	&"glass_cannon": {
		"name": "Glass Cannon", "requires": [[&"glass_heart"], [&"ember_shard", &"ember_relic"]],
		"requires_text": "Glass Heart + Ember Shard or Ember Relic",
		"effect": "+25% Fire Ball damage, but take +20% damage from everything",
		"damage": 0.25, "damage_taken": 0.2,
	},
	&"arcane_momentum": {
		"name": "Arcane Momentum", "requires": [[&"swift_casting"], [&"swift_boots", &"wind_relic"]],
		"requires_text": "Swift Casting + Swift Boots or Wind Relic",
		"effect": "A Fire Ball hit makes the next cast (within 1.5 s) recover 50% faster",
		"momentum": 0.5,
	},
	&"greeds_reward": {
		"name": "Greed's Reward", "requires": [[&"avarice"], [&"survivor_cache"]],
		"requires_text": "Avarice + Survivor's Cache (survival trial chest)",
		"effect": "+1% Fire Ball damage per 20 gold carried (max +30%), but anvil prices +25%",
		"gold_damage": 0.01, "upgrade_cost": 0.25,
	},
}

## Gold per gold_damage step, and the cap of that bonus.
const GOLD_DAMAGE_STEP := 20
const GOLD_DAMAGE_CAP := 0.3
## Seconds an Arcane Momentum charge lasts after a hit.
const MOMENTUM_WINDOW := 1.5


static func pact_name(id: StringName) -> String:
	return PACTS[id]["name"] if PACTS.has(id) else "None"


## "Glass Heart (+30% Fire Ball damage / -25% max HP)", or "None".
static func pact_text(id: StringName) -> String:
	if not PACTS.has(id):
		return "None"
	return "%s (%s / %s)" % [PACTS[id]["name"], PACTS[id]["benefit"], PACTS[id]["drawback"]]


static func synergy_text(id: StringName) -> String:
	return "%s: %s" % [SYNERGIES[id]["name"], SYNERGIES[id]["effect"]]
