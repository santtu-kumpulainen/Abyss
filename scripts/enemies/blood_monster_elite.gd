class_name BloodMonsterElite
extends BloodMonster
## Blood Monster Elite (Issue #58 Stage 3): a rarer, stronger Blood Monster
## (scenes/enemies/blood_monster_elite.tscn: bigger, crimson tint, more HP,
## stronger dash and blast, ~2.5x rewards) that keeps all Blood Monster
## behaviour (telegraphed dash, death blast) and adds Blood Frenzy:
##
## - The first time its HP drops to `frenzy_threshold` (alive), it releases a
##   blood nova at its feet: a BloodBlast warning circle of `nova_radius` for
##   `nova_delay` s, then `nova_damage` to the Mage only (never to enemies, so a
##   nova never starts a chain). It happens at most once.
## - It then stays frenzied: `frenzy_dash_speed_mult` x dash speed and
##   `frenzy_cooldown_mult` x special cooldown. The dash windup (its warning) is
##   never shortened, so the lane stays readable.
## - Its death blast (inherited, at most once) uses the elite radius / delay /
##   damage from the scene and a HEAVY shake; a blast that kills other Blood
##   Monsters chains as usual (each blasts once, each target is hit once per blast).
## A pulsing crimson aura under its feet (brighter while frenzied) marks it.

@export_group("Blood Frenzy")
## Share of max HP at which the frenzy starts.
@export_range(0.05, 0.95) var frenzy_threshold: float = 0.5
@export var nova_radius: float = 120.0
## Warning time of the nova (readable: longer than the regular death blast).
@export var nova_delay: float = 0.9
## Damage to the Mage (base; x run damage scaling).
@export var nova_damage: float = 14.0
@export var frenzy_dash_speed_mult: float = 1.2
@export var frenzy_cooldown_mult: float = 0.7
@export_group("Look")
@export var elite_tint := Color(0.62, 0.22, 0.32)
@export var aura_color := Color(0.85, 0.08, 0.15)
@export var aura_radius: float = 54.0
@export_group("")

var frenzied := false
## The nova this elite released (null until the frenzy); never more than one.
var nova: BloodBlast

var _aura_time := 0.0


func _ready() -> void:
	super._ready()
	_sprite.modulate = elite_tint


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_aura_time += delta
	queue_redraw()


func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	nova_damage *= damage_mult


func take_damage(amount: float) -> void:
	super.take_damage(amount)
	if not frenzied and not dying and not health.is_dead() \
			and health.current <= health.max_health * frenzy_threshold:
		_start_frenzy()


## Enters the frenzy once: releases the nova and speeds up the dash.
func _start_frenzy() -> void:
	if frenzied:
		return
	frenzied = true
	dash_speed *= frenzy_dash_speed_mult
	special_cooldown *= frenzy_cooldown_mult
	_sprite.modulate = Color(0.95, 0.3, 0.35)
	AudioManager.sfx(self, &"blood_monster_charge")
	var parent: Node = get_parent()
	while parent != null and not parent is Room:
		parent = parent.get_parent()
	if parent == null:
		parent = _death_visual_parent()
	# Mage-only damage (enemy_damage 0): the nova never hurts enemies or chains.
	nova = BloodBlast.spawn_blast(parent, global_position, nova_radius, nova_delay, nova_damage, 0.0, self, death_blast_effect)


func _spawn_death_blast() -> void:
	super._spawn_death_blast()
	if death_blast:
		death_blast.eruption_shake = CombatFeedback.Shake.HEAVY


func _draw() -> void:
	# Aura first: the base _draw (dash lane) and the sprite draw over it.
	var pulse := 0.5 + 0.5 * sin(_aura_time * (9.0 if frenzied else 4.0))
	var alpha := (0.5 if frenzied else 0.35) + 0.2 * pulse
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, aura_radius, Color(aura_color, alpha * 0.5))
	draw_arc(Vector2.ZERO, aura_radius, 0.0, TAU, 40, Color(aura_color, alpha + 0.2), 3.0)
	draw_set_transform(Vector2.ZERO)
	super._draw()
