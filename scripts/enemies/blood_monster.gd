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
##
## Death blast (Issue #51 Stage 4): on death it leaves combat at once and leaves
## a BloodBlast at its feet: a `death_blast_delay` s warning circle of
## `death_blast_radius`, then `death_blast_damage` to the Mage (scaled like its
## other attacks) and `death_blast_enemy_fraction` x its max HP to regular
## enemies (never minibosses or the boss). It blasts at most once.

@export_group("Dash")
@export var dash_speed: float = 420.0
@export var dash_distance: float = 260.0
## Hit / lane half-width.
@export var dash_hit_radius: float = 32.0

@export_group("Death blast")
@export var death_blast_radius: float = 100.0
## Warning time before the detonation.
@export var death_blast_delay: float = 0.6
## Damage to the Mage (base; x run damage scaling).
@export var death_blast_damage: float = 12.0
## Damage to each regular enemy, as a share of this monster's max HP.
@export_range(0.0, 1.0) var death_blast_enemy_fraction: float = 0.4
## Explosion sheet played at the detonation (fitted to the blast).
@export var death_blast_effect: EffectSheet
@export_group("")

var _dash := LaneCharge.new()
## The blast this monster left (null until it died); never more than one.
var death_blast: BloodBlast
var _blast_spawned := false


## The locked dash (aim, distance, hit state).
func dash() -> LaneCharge:
	return _dash


func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	death_blast_damage *= damage_mult


func _on_died() -> void:
	_spawn_death_blast()
	super._on_died()


## Leaves the death blast once, under the room (freed with it), else the scene.
func _spawn_death_blast() -> void:
	if _blast_spawned:
		return
	_blast_spawned = true
	var parent: Node = get_parent()
	while parent != null and not parent is Room:
		parent = parent.get_parent()
	if parent == null:
		parent = _death_visual_parent()
	death_blast = BloodBlast.spawn_blast(parent, global_position, death_blast_radius, death_blast_delay,
			death_blast_damage, health.max_health * death_blast_enemy_fraction, self, death_blast_effect)


func _lock_special() -> void:
	_dash.begin(global_position, global_position + aim, dash_speed, dash_distance, dash_hit_radius, special_damage)


func _special_active(delta: float) -> bool:
	return _dash.step(self, delta, _find_target())


func _draw() -> void:
	if phase == Phase.WINDUP:
		_dash.draw_lane(self, windup_progress())
