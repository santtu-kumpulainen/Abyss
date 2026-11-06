class_name LevelScaling
extends RefCounted
## Central dungeon-level scaling: how much harder enemies get per dungeon level
## (Level 1 = unscaled). This is independent of the selected Difficulty tier;
## RunState multiplies the two. Only enemies scale: player stats, XP and gold
## are never scaled by level. Tune the constants below to rebalance.

## Enemy max HP gained per level above 1 (0.25 = +25% each, additive): x1.00 / 1.25 / 1.50 on levels 1-3.
const HEALTH_PER_LEVEL := 0.25
## Enemy damage gained per level above 1.
const DAMAGE_PER_LEVEL := 0.06
## Enemy move speed / attack rate gained per level above 1, capped by PACE_CAP.
const PACE_PER_LEVEL := 0.02
const PACE_CAP := 0.3
## Extra enemies: +1 per dungeon level above 1 in every combat room (and per
## survival wave). From EXTRA_BONUS_FROM_LEVEL, tier-2 combat rooms with at
## least EXTRA_BONUS_MIN_POINTS free safe spawn points get one more. The caller
## (RunState.extra_room_enemies) adds the difficulty extras and applies the
## caps (RunState.MAX_EXTRA_ENEMIES and the free spawn points).
const EXTRA_BONUS_FROM_LEVEL := 3
const EXTRA_BONUS_MIN_POINTS := 4


## Player-output-relative enemy HP: reference output O_ref(D) = BASE * GROWTH^(D-1);
## the HP modifier is clamp(O / O_ref, MIN, MAX). See RunState.player_output().
const OUTPUT_REF_BASE := 1.25
const OUTPUT_REF_GROWTH := 1.5
const OUTPUT_MODIFIER_MIN := 1.0
const OUTPUT_MODIFIER_MAX := 2.0


static func _steps(level: int) -> int:
	return maxi(level - 1, 0)


static func enemy_health(level: int) -> float:
	return 1.0 + HEALTH_PER_LEVEL * _steps(level)


static func enemy_damage(level: int) -> float:
	return 1.0 + DAMAGE_PER_LEVEL * _steps(level)


static func enemy_pace(level: int) -> float:
	return 1.0 + minf(PACE_PER_LEVEL * _steps(level), PACE_CAP)


## Reference player output for dungeon level `level` (1.25 / 1.875 / 2.8125 ...).
static func output_reference(level: int) -> float:
	return OUTPUT_REF_BASE * pow(OUTPUT_REF_GROWTH, _steps(level))


## Enemy HP modifier for a player output `output`: never below the baseline, capped.
static func output_hp_modifier(output: float, level: int) -> float:
	return clampf(output / output_reference(level), OUTPUT_MODIFIER_MIN, OUTPUT_MODIFIER_MAX)


## Level-based extra enemies for a combat room (uncapped).
static func room_extra_enemies(level: int, tier2_room: bool, free_points: int) -> int:
	var bonus := 1 if level >= EXTRA_BONUS_FROM_LEVEL and tier2_room and free_points >= EXTRA_BONUS_MIN_POINTS else 0
	return _steps(level) + bonus


## Level-based extra enemies per survival wave (uncapped).
static func wave_extra_enemies(level: int) -> int:
	return _steps(level)
