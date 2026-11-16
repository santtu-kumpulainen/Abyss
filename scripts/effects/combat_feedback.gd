class_name CombatFeedback
extends Node2D
## Central combat and reward feedback of a Dungeon run (Issue #58 Stage 2). One
## instance lives in the Dungeon scene (group "combat_feedback"); gameplay code
## reaches it through the null-safe static helpers (shake_from(), of()), so
## scenes without it (test rooms) simply get no feedback.
##
## - Damage numbers: damage_number() floats a value that rises, scales and fades.
##   Kinds: ENEMY (white), CRIT (larger gold, with a spark burst) and PLAYER (red).
##   Numbers on one target within `stack_window` stack upwards instead of overlapping.
##   track_enemy() shows every hit of an Enemy (its Health.damaged); a projectile
##   marks a critical hit with mark_crit() just before the damage lands.
## - float_text(): short labels (XP gains, "LEVEL UP!").
## - burst(): a one-shot CPUParticles2D spark burst that frees itself.
## - drop_coins(): CoinPickup coins that scatter and fly to the Mage (presentation
##   of gold that RunState already granted exactly once at the kill).
## - Screen shake: shake(LIGHT / MEDIUM / HEAVY) adds trauma (capped at 1) that
##   decays over time; the offset is max_shake_offset x trauma x shake_scale,
##   rounded to whole pixels, applied to `camera.offset` only (the HUD lives on
##   CanvasLayers and never shakes). shake_scale is a session setting
##   (Full / Reduced / Off, see PauseMenu) kept across restarts.
## Everything is a child of this node and processes with the tree, so it all
## freezes while paused; clear() (room change, level change) and stop() (death,
## victory) remove popups and coins, so nothing carries over.

enum Kind { ENEMY, CRIT, PLAYER }
enum Shake { NONE, LIGHT, MEDIUM, HEAVY }

const GROUP := &"combat_feedback"
const CRIT_META := &"combat_feedback_crit"
## Shake presets for the setting (label, scale).
const SHAKE_SETTINGS := [["Full", 1.0], ["Reduced", 0.5], ["Off", 0.0]]

## Session-wide shake setting (index into SHAKE_SETTINGS); survives scene reloads.
static var shake_setting := 0

@export var camera: Camera2D

@export_group("Damage numbers")
@export var number_rise: float = 34.0
@export var number_time: float = 0.75
@export var number_font_size: int = 18
@export var crit_font_size: int = 26
@export var player_font_size: int = 18
@export var enemy_color := Color(1.0, 0.97, 0.9)
@export var crit_color := Color(1.0, 0.78, 0.2)
@export var player_color := Color(1.0, 0.3, 0.3)
## Seconds during which a target's numbers stack upwards instead of overlapping.
@export var stack_window: float = 0.35
@export var stack_step: float = 14.0
## Height above an enemy's feet where its numbers start.
@export var enemy_number_height: float = 44.0

@export_group("Screen shake")
## Trauma added per tier (LIGHT, MEDIUM, HEAVY); trauma is capped at 1.
@export var shake_light: float = 0.22
@export var shake_medium: float = 0.4
@export var shake_heavy: float = 0.65
## Offset at full trauma, in pixels.
@export var max_shake_offset: float = 9.0
## Trauma lost per second.
@export var shake_decay: float = 1.8

@export_group("Coins")
@export var coin_value: int = 5
@export var max_coins_per_drop: int = 8

var trauma := 0.0
## False after stop() (Mage dead / victory): no new coins, popups or shakes.
var active := true

var _stacks := {}  # target instance id -> [last time, count]
## The running "+N gold" pickup popup (coin_collected()).
var _coin_label: WeakRef
var _coin_sum := 0
var _coin_time := -INF
var _time := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 50
	# Runs while paused only to hold the camera still; every effect child is
	# PAUSABLE (see add_child calls), so popups and coins freeze with the game.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if get_tree().paused:
		# Never leave the world offset behind a pause / relic menu; trauma is kept.
		if camera and is_instance_valid(camera):
			camera.offset = Vector2.ZERO
		return
	_time += delta
	if trauma > 0.0:
		trauma = maxf(trauma - shake_decay * delta, 0.0)
	_apply_shake()


func _exit_tree() -> void:
	trauma = 0.0
	_apply_shake()


## The run's CombatFeedback (null outside a Dungeon run).
static func of(node: Node) -> CombatFeedback:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as CombatFeedback


## Null-safe shake request from any gameplay node.
static func shake_from(node: Node, tier: Shake) -> void:
	var fb := of(node)
	if fb:
		fb.shake(tier)


## Marks the next damage `body` takes as a critical hit (read once by track_enemy()).
static func mark_crit(body: Node) -> void:
	if body != null and is_instance_valid(body):
		body.set_meta(CRIT_META, true)


static func shake_scale() -> float:
	return SHAKE_SETTINGS[shake_setting][1]


static func shake_label() -> String:
	return SHAKE_SETTINGS[shake_setting][0]


## Cycles Full -> Reduced -> Off and returns the new label.
static func cycle_shake_setting() -> String:
	shake_setting = (shake_setting + 1) % SHAKE_SETTINGS.size()
	return shake_label()


func shake(tier: Shake) -> void:
	if not active or tier == Shake.NONE:
		return
	var add: float = [0.0, shake_light, shake_medium, shake_heavy][tier]
	trauma = minf(trauma + add, 1.0)


## Current camera offset from the shake (zero when calm or disabled).
func shake_offset() -> Vector2:
	var strength := max_shake_offset * trauma * shake_scale()
	if strength < 0.5:
		return Vector2.ZERO
	return Vector2.RIGHT.rotated(randf() * TAU) * strength


func _apply_shake() -> void:
	if camera and is_instance_valid(camera):
		camera.offset = shake_offset().round()


## Shows every hit `enemy` takes as a damage number (once per enemy).
func track_enemy(enemy: Enemy) -> void:
	if enemy == null or enemy.health == null or enemy.has_meta(&"combat_feedback_tracked"):
		return
	enemy.set_meta(&"combat_feedback_tracked", true)
	enemy.health.damaged.connect(_on_enemy_damaged.bind(enemy))


func _on_enemy_damaged(amount: float, _current: float, enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var crit: bool = enemy.get_meta(CRIT_META, false)
	if crit:
		enemy.remove_meta(CRIT_META)
	# A miniboss punish-window hit is a critical hit too.
	if enemy is Miniboss and (enemy as Miniboss).is_vulnerable():
		crit = true
	var pos := enemy.global_position + Vector2(0, -enemy_number_height)
	# Overkill (instant kills) never shows more than the enemy's max HP.
	damage_number(pos, minf(amount, enemy.health.max_health), Kind.CRIT if crit else Kind.ENEMY, enemy)
	if crit:
		burst(pos + Vector2(0, 14), crit_color, 10, 90.0)
		AudioManager.sfx(self, &"crit_hit")


## Floats `amount` (rounded, at least 1) at `world_pos`. Returns the label (null when inactive).
func damage_number(world_pos: Vector2, amount: float, kind: Kind = Kind.ENEMY, target: Object = null) -> Label:
	if not active or not is_inside_tree():
		return null
	var size := number_font_size
	var color := enemy_color
	var text := str(maxi(roundi(amount), 1))
	match kind:
		Kind.CRIT:
			size = crit_font_size
			color = crit_color
			text += "!"
		Kind.PLAYER:
			size = player_font_size
			color = player_color
			text = "-" + text
	var offset := Vector2(randf_range(-8.0, 8.0), -_stack_index(target) * stack_step)
	return _popup(world_pos + offset, text, color, size, 1.35 if kind == Kind.CRIT else 1.15)


## A short floating label (e.g. "+3 XP"). Returns the label (null when inactive).
func float_text(world_pos: Vector2, text: String, color: Color, size: int = 16) -> Label:
	if not active or not is_inside_tree():
		return null
	return _popup(world_pos, text, color, size, 1.1)


## Next stack slot of `target` (0 when its last number is older than stack_window).
func _stack_index(target: Object) -> int:
	if target == null:
		return 0
	var id := target.get_instance_id()
	var entry: Array = _stacks.get(id, [-INF, 0])
	var index: int = entry[1] + 1 if _time - float(entry[0]) <= stack_window else 0
	_stacks[id] = [_time, index]
	return index


func _popup(world_pos: Vector2, text: String, color: Color, size: int, pop: float) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override(&"outline_size", 5)
	label.size = Vector2(120, size + 8)
	label.pivot_offset = label.size / 2.0
	label.position = world_pos - label.size / 2.0
	label.scale = Vector2.ONE * pop
	label.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, ^"position:y", label.position.y - number_rise, number_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, ^"scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, ^"modulate:a", 0.0, number_time * 0.45).set_delay(number_time * 0.55)
	tween.chain().tween_callback(label.queue_free)
	return label


## One-shot spark burst of `amount` particles at `world_pos`; frees itself.
func burst(world_pos: Vector2, color: Color, amount: int = 12, speed: float = 110.0, lifetime: float = 0.45) -> CPUParticles2D:
	if not active or not is_inside_tree() or amount <= 0:
		return null
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 160)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	p.color = color
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	p.color_ramp = fade
	p.position = world_pos
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Coins for `gold` granted at `world_pos`, flying to `target` (the Mage).
## Returns the coins spawned.
func drop_coins(world_pos: Vector2, gold: int, target: Node2D) -> Array[CoinPickup]:
	var coins: Array[CoinPickup] = []
	if not active or not is_inside_tree() or gold <= 0 or target == null:
		return coins
	var count := clampi(ceili(float(gold) / maxf(coin_value, 1)), 1, max_coins_per_drop)
	for i in count:
		var coin := CoinPickup.new()
		coin.target = target
		coin.position = world_pos
		coin.launch = Vector2.UP.rotated(randf_range(-1.1, 1.1)) * randf_range(70.0, 130.0)
		# Split the gold over the coins (the first ones take the remainder).
		coin.value = gold / count + (1 if i < gold % count else 0)
		coin.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(coin)
		coins.append(coin)
	return coins


## A coin reached `target`: shows a "+N gold" popup above it. Coins arriving
## within a short window add to the same popup instead of stacking new ones.
func coin_collected(value: int, target: Node2D) -> void:
	if value <= 0 or target == null or not is_instance_valid(target):
		return
	var label := _coin_label.get_ref() as Label if _coin_label else null
	if label and not label.is_queued_for_deletion() and _time - _coin_time <= 0.5:
		_coin_sum += value
		label.text = "+%d gold" % _coin_sum
	else:
		_coin_sum = value
		label = float_text(target.global_position + Vector2(0, -92), "+%d gold" % value, crit_color, 16)
		_coin_label = weakref(label) if label else null
	_coin_time = _time


## Live coins (not yet collected).
func coins() -> Array[CoinPickup]:
	var result: Array[CoinPickup] = []
	for child in get_children():
		if child is CoinPickup and not (child as CoinPickup).is_collected():
			result.append(child)
	return result


## Removes every popup, burst and coin (room or level change) and calms the shake.
func clear() -> void:
	for child in get_children():
		child.queue_free()
	_stacks.clear()
	trauma = 0.0
	_apply_shake()


## Ends feedback for this run (Mage died / victory): clears and blocks new effects.
func stop() -> void:
	clear()
	active = false
