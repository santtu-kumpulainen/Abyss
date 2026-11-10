class_name Difficulty
extends RefCounted
## Central difficulty configuration: every tier's enemy scaling, extra
## encounter pressure, gold bonus and unlock rule lives in TIERS. Nothing else
## hardcodes difficulty values; RunState combines them with the run's Pact.
##
## Keys: enemy_health / enemy_damage (multipliers), enemy_pace (multiplier on
## enemy attack rate), enemy_move_pace (multiplier on enemy move speed),
## goblin_swings (normal Goblin swings before its special, per
## LevelScaling.GOBLIN_SWING_BRACKETS level bracket, kept within 1-3), extra_lv1 / extra_lv2 (extra enemies in
## Lv 1 / Lv 2+ combat rooms, limited by free safe spawn points), extra_wave
## (extra enemies per survival wave), gold (gold reward multiplier), requires
## (tier that must be completed to unlock, -1 = always available).
## XP and player stats are never scaled by difficulty.

enum Tier { NORMAL, HARD, ABYSSAL }

const TIERS := {
	Tier.NORMAL: {
		"name": "Normal", "color": Color(0.7, 0.9, 0.7),
		"enemy_health": 1.0, "enemy_damage": 1.0, "enemy_pace": 1.0, "enemy_move_pace": 1.0, "goblin_swings": [3, 2, 2],
		"extra_lv1": 0, "extra_lv2": 0, "extra_wave": 0,
		"gold": 1.0, "requires": -1,
	},
	Tier.HARD: {
		"name": "Hard", "color": Color(1.0, 0.7, 0.35),
		"enemy_health": 1.35, "enemy_damage": 1.25, "enemy_pace": 1.1, "enemy_move_pace": 1.05, "goblin_swings": [2, 2, 1],
		"extra_lv1": 0, "extra_lv2": 1, "extra_wave": 1,
		"gold": 1.25, "requires": Tier.NORMAL,
	},
	Tier.ABYSSAL: {
		"name": "Abyssal", "color": Color(0.85, 0.4, 1.0),
		"enemy_health": 1.75, "enemy_damage": 1.5, "enemy_pace": 1.2, "enemy_move_pace": 1.1, "goblin_swings": [2, 1, 1],
		"extra_lv1": 1, "extra_lv2": 2, "extra_wave": 2,
		"gold": 1.5, "requires": Tier.HARD,
	},
}


static func is_valid(tier: int) -> bool:
	return TIERS.has(tier)


static func data(tier: int) -> Dictionary:
	return TIERS.get(tier, TIERS[Tier.NORMAL])


static func display_name(tier: int) -> String:
	return data(tier)["name"]


## Tier unlocked by completing `tier`, or -1 if none.
static func next_tier(tier: int) -> int:
	for t: int in TIERS:
		if TIERS[t]["requires"] == tier:
			return t
	return -1


## Extra enemies for a combat room needing `required_level`.
static func extra_enemies(tier: int, required_level: int) -> int:
	return data(tier)["extra_lv2"] if required_level >= 2 else data(tier)["extra_lv1"]


static func unlock_text(tier: int) -> String:
	var requires: int = data(tier)["requires"]
	return "Available from the start" if requires < 0 else "Unlock: complete a %s run" % display_name(requires)


## Multi-line description for the pre-run menu.
static func summary_text(tier: int) -> String:
	var d := data(tier)
	if tier == Tier.NORMAL:
		return "Baseline balance.\nEnemies: standard HP, damage and speed.\nRewards: standard gold."
	var pressure: Array[String] = []
	if d["extra_lv1"] > 0:
		pressure.append("+%d enemy in Lv 1 rooms" % d["extra_lv1"])
	if d["extra_lv2"] > 0:
		pressure.append("+%d in Lv 2 rooms" % d["extra_lv2"])
	if d["extra_wave"] > 0:
		pressure.append("+%d per survival wave" % d["extra_wave"])
	return "\n".join([
		"Enemies (incl. boss): +%d%% HP, +%d%% damage, +%d%% speed, +%d%% attack rate" % [
			_pct(d["enemy_health"]), _pct(d["enemy_damage"]), _pct(d["enemy_move_pace"]), _pct(d["enemy_pace"])],
		"Pressure: %s" % ", ".join(pressure),
		"Rewards: +%d%% gold (kills, boss, treasure)" % _pct(d["gold"]),
	])


static func _pct(multiplier: float) -> int:
	return roundi((multiplier - 1.0) * 100.0)
