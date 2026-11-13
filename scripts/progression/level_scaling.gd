class_name LevelScaling
extends RefCounted
## Central dungeon-level scaling: how much harder enemies get per dungeon level
## (Level 1 = unscaled). This is independent of the selected Difficulty tier;
## RunState multiplies the two. Only enemies scale: player stats, XP and gold
## are never scaled by level. Tune the constants below to rebalance.
##
## Regular enemies, minibosses and the boss each have their own level curve
## (Category, category_of(); Issue #55), so one can be tuned without touching
## the others. The unprefixed constants are the regular-enemy curve.

## Which level curve an enemy uses (see category_of()).
enum Category { REGULAR, MINIBOSS, BOSS }

## Regular enemies.
## Max HP gained per level above 1 (0.25 = +25% each, additive): x1.00 / 1.25 / 1.50 on levels 1-3.
const HEALTH_PER_LEVEL := 0.25
## Damage gained per level above 1.
const DAMAGE_PER_LEVEL := 0.06
## Attack rate (cooldowns, projectile speed) gained per level above 1, capped by PACE_CAP.
const PACE_PER_LEVEL := 0.02
const PACE_CAP := 0.3
## Move speed gained per level above 1, capped by MOVE_PACE_CAP (Issue #47:
## split from the attack pace so pursuers stay outrunnable).
const MOVE_PACE_PER_LEVEL := 0.015
const MOVE_PACE_CAP := 0.15

## Minibosses (Miniboss subclasses); same meaning as the regular constants.
const MINIBOSS_HEALTH_PER_LEVEL := 0.25
const MINIBOSS_DAMAGE_PER_LEVEL := 0.06
const MINIBOSS_PACE_PER_LEVEL := 0.02
const MINIBOSS_PACE_CAP := 0.3
const MINIBOSS_MOVE_PACE_PER_LEVEL := 0.015
const MINIBOSS_MOVE_PACE_CAP := 0.15

## The level boss (Boss); same meaning as the regular constants.
const BOSS_HEALTH_PER_LEVEL := 0.25
const BOSS_DAMAGE_PER_LEVEL := 0.06
const BOSS_PACE_PER_LEVEL := 0.02
const BOSS_PACE_CAP := 0.3
const BOSS_MOVE_PACE_PER_LEVEL := 0.015
const BOSS_MOVE_PACE_CAP := 0.15
## Bounded catch-up on enemy move speed from the Mage's speed bonus:
## 1 + min(CATCHUP_WEIGHT * (mage multiplier - 1), CATCHUP_CAP).
const CATCHUP_WEIGHT := 0.5
const CATCHUP_CAP := 0.1
## Goblin attack cycle: first dungeon level of each bracket; the swing count per
## bracket comes from the difficulty tier (Difficulty "goblin_swings").
const GOBLIN_SWING_BRACKETS: Array[int] = [1, 3, 5]
## Hard limit on an enemy's scaled walking speed (dashes / charges are separate)
## unless the enemy sets its own Enemy.speed_cap (only the Demon, which is meant to
## catch a Mage that only runs). Kept below the Mage's base speed (185) so the
## other pursuers can always be outrun (Issue #51 tempo: 140 -> 175).
const MAX_PURSUER_SPEED := 175.0
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


## Level curve of `enemy`: BOSS for a Boss, MINIBOSS for a Miniboss, else REGULAR
## (elites and enemies summoned by a miniboss are regular).
static func category_of(enemy: Enemy) -> Category:
	if enemy is Boss:
		return Category.BOSS
	if enemy is Miniboss:
		return Category.MINIBOSS
	return Category.REGULAR


## Max HP multiplier for dungeon level `level` on `category`'s curve.
static func enemy_health(level: int, category: Category = Category.REGULAR) -> float:
	var per_level := _pick(category, HEALTH_PER_LEVEL, MINIBOSS_HEALTH_PER_LEVEL, BOSS_HEALTH_PER_LEVEL)
	return 1.0 + per_level * _steps(level)


## Damage multiplier for dungeon level `level` on `category`'s curve.
static func enemy_damage(level: int, category: Category = Category.REGULAR) -> float:
	var per_level := _pick(category, DAMAGE_PER_LEVEL, MINIBOSS_DAMAGE_PER_LEVEL, BOSS_DAMAGE_PER_LEVEL)
	return 1.0 + per_level * _steps(level)


## Attack-rate multiplier for dungeon level `level` on `category`'s curve.
static func enemy_pace(level: int, category: Category = Category.REGULAR) -> float:
	var per_level := _pick(category, PACE_PER_LEVEL, MINIBOSS_PACE_PER_LEVEL, BOSS_PACE_PER_LEVEL)
	var cap := _pick(category, PACE_CAP, MINIBOSS_PACE_CAP, BOSS_PACE_CAP)
	return 1.0 + minf(per_level * _steps(level), cap)


## Move-speed multiplier for dungeon level `level` on `category`'s curve.
static func enemy_move_pace(level: int, category: Category = Category.REGULAR) -> float:
	var per_level := _pick(category, MOVE_PACE_PER_LEVEL, MINIBOSS_MOVE_PACE_PER_LEVEL, BOSS_MOVE_PACE_PER_LEVEL)
	var cap := _pick(category, MOVE_PACE_CAP, MINIBOSS_MOVE_PACE_CAP, BOSS_MOVE_PACE_CAP)
	return 1.0 + minf(per_level * _steps(level), cap)


## `category`'s value out of the three per-category constants.
static func _pick(category: Category, regular: float, miniboss: float, boss: float) -> float:
	match category:
		Category.MINIBOSS:
			return miniboss
		Category.BOSS:
			return boss
	return regular


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
