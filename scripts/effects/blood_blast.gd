class_name BloodBlast
extends FloorHazard
## Blood Monster death explosion (Issue #51 Stage 4, section L), built on
## FloorHazard: a pulsing red warning circle of exactly `radius` for `delay` s
## (0.6 s), then one eruption that damages
##   - the Mage ("player" group) by `damage` (the monster's scaled blast damage),
##   - regular enemies ("enemies" group) by `enemy_damage` (a share of the dead
##     monster's max HP), summons included,
## each living target inside at most once. Minibosses (Miniboss), the boss (Boss),
## dying enemies and `excluded` (the dead monster) are never damaged. The
## eruption plays the shared Burst ring plus `erupt_effect`; nothing lingers.
## A Blood Monster killed by a blast leaves its own blast (chain reaction); each
## monster blasts at most once (BloodMonster guard), so chains are finite.
## Lives under the room, so an unloaded room never detonates later.

const BLAST_COLOR := Color(1.0, 0.18, 0.12)

## Damage dealt to each regular enemy inside.
var enemy_damage := 0.0
## Never damaged by this blast (the Blood Monster that left it).
var excluded: Node
## Every target this blast damaged (at most once each).
var hit_targets: Array[Node2D] = []


## Adds a blast at global `pos` under `parent` and returns it.
static func spawn_blast(parent: Node, pos: Vector2, p_radius: float, p_delay: float, p_mage_damage: float,
		p_enemy_damage: float, p_excluded: Node = null, p_effect: EffectSheet = null) -> BloodBlast:
	var blast := BloodBlast.new()
	blast.radius = p_radius
	blast.delay = p_delay
	blast.damage = p_mage_damage
	blast.enemy_damage = p_enemy_damage
	blast.excluded = p_excluded
	blast.color = BLAST_COLOR
	blast.erupt_effect = p_effect
	blast.target_group = &"player"
	parent.add_child(blast)
	blast.global_position = pos
	return blast


## True if `node` may be damaged by a blast: a living, non-excluded Mage or
## regular enemy (never a Miniboss or the Boss).
func can_damage(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or node == excluded or node.is_queued_for_deletion():
		return false
	if node is Miniboss or node is Boss:
		return false
	if node is Enemy:
		var enemy := node as Enemy
		return not enemy.dying and not enemy.health.is_dead()
	if not node.has_method(&"take_damage"):
		return false
	return not (node.has_method(&"is_dead") and node.call(&"is_dead"))


func _hit() -> int:
	# Collect first: damage may kill enemies (and start chain blasts) mid-loop.
	var victims: Array[Node2D] = []
	for group: StringName in [&"player", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var target := node as Node2D
			if target and not victims.has(target) and not hit_targets.has(target) and can_damage(target) and contains(target):
				victims.append(target)
	var hits := 0
	for target in victims:
		if not can_damage(target):
			continue
		var amount := enemy_damage if target is Enemy else damage
		if amount <= 0.0:
			continue
		hit_targets.append(target)
		target.take_damage(amount)
		HitFeedback.knock(target, target.global_position - global_position)
		hits += 1
	return hits


func _draw() -> void:
	super._draw()
	if phase == Phase.TELEGRAPH:
		# Steady warning pulse over the whole telegraph (FloorHazard adds the fast
		# "about to erupt" pulse in its last IMMINENT_TIME s).
		var pulse := 0.5 + 0.5 * sin(_time * 14.0)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(1.0, 0.35, 0.3, 0.35 + 0.45 * pulse), OUTLINE_WIDTH + 2.0)
