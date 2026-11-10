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
## Enemy attack rate (cooldowns, projectile speed) gained per level above 1, capped by PACE_CAP.
const PACE_PER_LEVEL := 0.02
const PACE_CAP := 0.3
## Enemy move speed gained per level above 1, capped by MOVE_PACE_CAP (Issue #47:
## split from the attack pace so pursuers stay outrunnable).
const MOVE_PACE_PER_LEVEL := 0.015
const MOVE_PACE_CAP := 0.15
## Bounded catch-up on enemy move speed from the Mage's speed bonus:
## 1 + min(CATCHUP_WEIGHT * (mage multiplier - 1), CATCHUP_CAP).
const CATCHUP_WEIGHT := 0.5
const CATCHUP_CAP := 0.1
## Goblin attack cycle: first dungeon level of each bracket; the swing count per
## bracket comes from the difficulty tier (Difficulty "goblin_swings").
const GOBLIN_SWING_BRACKETS: Array[int] = [1, 3, 5]
## Hard limit on an enemy's scaled walking speed (dashes / charges are separate)
## unless the enemy sets its own Enemy.speed_cap (only the Demon, which is meant to
## catch a Mage that only runs). Kept below the Mage's base speed (150) so the
## other pursuers can always be outrun.
const MAX_PURSUER_SPEED := 140.0
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


## Attack-rate multiplier for dungeon level `level`.
static func enemy_pace(level: int) -> float:
	return 1.0 + minf(PACE_PER_LEVEL * _steps(level), PACE_CAP)


## Move-speed multiplier for dungeon level `level`.
static func enemy_move_pace(level: int) -> float:
	return 1.0 + minf(MOVE_PACE_PER_LEVEL * _steps(level), MOVE_PACE_CAP)


## Index into Difficulty's "goblin_swings" for dungeon level `level`.
static func goblin_swing_bracket(level: int) -> int:
	var bracket := 0
	for i in GOBLIN_SWING_BRACKETS.size():
		if level >= GOBLIN_SWING_BRACKETS[i]:
			bracket = i
	return bracket


## Enemy move-speed catch-up for a Mage speed multiplier `mage_speed_mult` (never below 1, capped).
static func player_catchup(mage_speed_mult: float) -> float:
	return 1.0 + clampf(CATCHUP_WEIGHT * (mage_speed_mult - 1.0), 0.0, CATCHUP_CAP)


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
