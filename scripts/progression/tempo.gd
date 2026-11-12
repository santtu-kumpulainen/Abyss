class_name Tempo
extends RefCounted
## Global game tempo (Issue #51 Stage 5, section K): one place for the ~25 %
## faster enemy pacing of real runs. RunState folds these factors into the
## enemy multipliers it hands to Enemy.apply_scaling(); test scenes that do not
## scale their enemies keep the base values. Player tempo values live in
## mage.tscn and fire_ball.tres.
##
## Never changed by tempo: HP, damage, XP, gold, every telegraph / windup
## duration (Goblin tracking, lock, anticipation and strike included), opening
## delays, dash invulnerability, the Blood Monster dash speed and the wave speed.

## Enemy walking speed multiplier (still capped by Enemy.speed_cap /
## LevelScaling.MAX_PURSUER_SPEED).
const ENEMY_MOVE := 1.25
## Enemy attack rate: cooldowns / ENEMY_ATTACK and projectile speeds x ENEMY_ATTACK
## (through the attack pace multiplier).
const ENEMY_ATTACK := 1.15
## Post-attack recovery pauses / ENEMY_RECOVERY. Fixed: never compounded with
## the difficulty or dungeon-level pace (those pauses are the punish windows).
const ENEMY_RECOVERY := 1.15
