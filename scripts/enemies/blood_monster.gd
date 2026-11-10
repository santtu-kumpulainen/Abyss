class_name BloodMonster
extends TelegraphedMelee
## Blood Monster (Issue #47): the slow, heavy red elite (and the Goblin's
## biome-2 replacement) with a regular-elite version of the Brood Mother's
## charge. When the Mage is between `special_min_range` and `special_max_range`
## it stops, locks its aim and shows the dash lane (exactly the hit width and
## length) for `special_windup` s, then dashes along it at `dash_speed` up to
## `dash_distance` (stops at walls), hitting the Mage at most once for
## `special_damage` if it comes within `dash_hit_radius`. The lane is fixed at
## the windup start, so a sidestep dodges it. The dash is the shared LaneCharge
## helper; phases, recovery and cooldown come from TelegraphedMelee.

@export_group("Dash")
@export var dash_speed: float = 420.0
@export var dash_distance: float = 260.0
## Hit / lane half-width.
@export var dash_hit_radius: float = 32.0

var _dash := LaneCharge.new()


## The locked dash (aim, distance, hit state).
func dash() -> LaneCharge:
	return _dash


func _lock_special() -> void:
	_dash.begin(global_position, global_position + aim, dash_speed, dash_distance, dash_hit_radius, special_damage)


func _special_active(delta: float) -> bool:
	return _dash.step(self, delta, _find_target())


func _draw() -> void:
	if phase == Phase.WINDUP:
		_dash.draw_lane(self, windup_progress())
