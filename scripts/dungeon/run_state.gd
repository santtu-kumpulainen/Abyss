class_name RunState
extends Node
## Run-level progression: XP, level and currency for the current dungeon run.
## Lives in the Dungeon scene, so it persists across room transitions and is
## recreated (reset) when the run restarts. Nothing is saved to disk.
##
## Leveling: reaching xp_to_next_level() XP raises the level by one; leftover
## XP carries over. The XP needed grows by `xp_per_level` each level
## (50, 100, 150, ... by default). Each level-up emits `leveled_up`; the owner
## applies the reward (the Dungeon uses max_health_per_level/heal_per_level).

signal changed
signal leveled_up(level: int)

## XP needed for level 1 -> 2; level N -> N+1 needs N times this.
@export var xp_per_level: int = 50
## Mage max HP gained per level-up.
@export var max_health_per_level: float = 20.0
## Mage HP restored per level-up.
@export var heal_per_level: float = 20.0

var level: int = 1
## XP towards the next level.
var xp: int = 0
var currency: int = 0


func xp_to_next_level() -> int:
	return xp_per_level * level


func add_rewards(xp_amount: int, currency_amount: int) -> void:
	currency += maxi(currency_amount, 0)
	xp += maxi(xp_amount, 0)
	var levels_gained: Array[int] = []
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		levels_gained.append(level)
	changed.emit()
	for new_level in levels_gained:
		leveled_up.emit(new_level)


func reset() -> void:
	level = 1
	xp = 0
	currency = 0
	changed.emit()
