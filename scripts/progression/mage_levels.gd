class_name MageLevels
extends RefCounted
## Mage level cap, room / boss gates and XP budget per dungeon level (D).
## Each dungeon level takes LEVEL_UPS_PER_DUNGEON level-ups of the Mage to get
## from its first room to its boss; the Mage's level is never reset, so the
## gates move up with D instead:
##   arrival(D)  = 3 * (D - 1) + 1   Mage level when level D starts (= cap(D - 1))
##   cap(D)      = 3 * D + 1         highest Mage level in level D, and its boss gate
##   offset(D)   = 3 * (D - 1)
##   room gate   = RoomSpec.required_level + offset(D)
##   boss gate   = cap(D)
## Examples: D1 rooms Lv 1 / 2, boss Lv 4. D2 rooms Lv 4 / 5, boss Lv 7.
## D3 rooms Lv 7 / 8, boss Lv 10.
## XP: ordinary pre-boss rooms hold PRE_BOSS_BASE_XP XP (kills of the authored
## rooms, no extra enemies). Enemy XP is multiplied by xp_multiplier(D) so that
## budget covers the three level-ups of level D with XP_SLACK headroom:
##   cost(D)          = xp_per_level * (m + (m + 1) + (m + 2)),  m = arrival(D)
##   xp_multiplier(D) = XP_SLACK * cost(D) / PRE_BOSS_BASE_XP
## With xp_per_level 50: cost = 300 / 750 / 1200 and the multiplier is
## 2.29 / 5.74 / 9.18 for D1 / D2 / D3 (a test checks the budget on the real dungeon).

const LEVEL_UPS_PER_DUNGEON := 3
## XP of all non-boss, non-treasure rooms of scenes/dungeon/dungeon.tscn (unscaled).
const PRE_BOSS_BASE_XP := 170
## Budget headroom: a run must clear about 77% of the pre-boss XP to reach the boss gate.
const XP_SLACK := 1.3


static func offset(dungeon_level: int) -> int:
	return LEVEL_UPS_PER_DUNGEON * (maxi(dungeon_level, 1) - 1)


## Mage level on arrival at dungeon level `dungeon_level`.
static func arrival_level(dungeon_level: int) -> int:
	return offset(dungeon_level) + 1


## Highest Mage level in `dungeon_level` (also its boss gate).
static func cap(dungeon_level: int) -> int:
	return LEVEL_UPS_PER_DUNGEON * maxi(dungeon_level, 1) + 1


## Mage level needed to enter a room whose RoomSpec.required_level is `base`.
static func gate(base: int, is_boss: bool, dungeon_level: int) -> int:
	return cap(dungeon_level) if is_boss else base + offset(dungeon_level)


## XP needed for the level-ups of `dungeon_level` (arrival level to cap).
static func level_up_cost(dungeon_level: int, xp_per_level: int) -> int:
	var total := 0
	for m in range(arrival_level(dungeon_level), cap(dungeon_level)):
		total += xp_per_level * m
	return total


static func xp_multiplier(dungeon_level: int, xp_per_level: int) -> float:
	return XP_SLACK * level_up_cost(dungeon_level, xp_per_level) / float(PRE_BOSS_BASE_XP)
