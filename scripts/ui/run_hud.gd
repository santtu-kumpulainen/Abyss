class_name RunHud
extends CanvasLayer
## Shows the run's level, XP progress and currency, e.g. "Lv 2   XP 30/100   Gold 15",
## or "Lv 3 (MAX)   Gold 15" at the level cap, and the collected run items
## (and lasting treasure bonuses) with their effects below it. show_message() briefly shows a centred
## announcement (e.g. level-up unlocks). The top-right status block shows the
## run's dungeon level / biome, timers, difficulty, Pact (benefit / drawback)
## and active synergies. Below the level line, the objective line shows the
## level's Ancient Seal progress and what still keeps the boss gate shut.

## Reward feedback (Issue #58 Stage 2): the level / XP / gold line pulses when
## XP or gold goes up (gold tint for gold, stronger for a level-up), and
## show_reward() pops a centred banner (name + description, rarity colour) for
## valuable rewards. The banner supersedes the plain message line for that event
## (the message text is kept, only hidden).

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const RARITY_COLORS := {
	Rarity.COMMON: Color(0.92, 0.92, 0.95),
	Rarity.RARE: Color(0.45, 0.75, 1.0),
	Rarity.EPIC: Color(0.8, 0.5, 1.0),
	Rarity.LEGENDARY: Color(1.0, 0.8, 0.3),
}
const RARITY_NAMES := {Rarity.COMMON: "", Rarity.RARE: "Rare", Rarity.EPIC: "Epic", Rarity.LEGENDARY: "Legendary"}

## Seconds a message stays fully visible before fading out.
@export var message_duration: float = 3.0
## Seconds a reward banner stays fully visible.
@export var reward_duration: float = 2.6

@onready var _label: Label = %RunLabel
@onready var _message: Label = %MessageLabel
@onready var _items: Label = %ItemsLabel
@onready var _status: Label = %StatusLabel
@onready var _objective: Label = %ObjectiveLabel

var _run_state: RunState
var _message_tween: Tween
var _shown_second := -1
## Last shown values, to pulse the line only when they go up.
var _last := {}
var _pulse_tween: Tween
var _reward_panel: PanelContainer
var _reward_title: Label
var _reward_desc: Label
var _reward_tween: Tween


func _ready() -> void:
	_build_reward_banner()


## Displays `run_state` and follows its changes.
func set_run_state(run_state: RunState) -> void:
	if _run_state and _run_state.changed.is_connected(_refresh):
		_run_state.changed.disconnect(_refresh)
	_run_state = run_state
	_run_state.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	# The timer line only changes once a second.
	if _run_state and int(_run_state.run_time) != _shown_second:
		_refresh()


## Level, timers, difficulty, Pact and active synergy lines for the status block.
static func status_text(run_state: RunState) -> String:
	var lines: Array[String] = [
		"Level %d - %s%s" % [run_state.dungeon_level, Biomes.biome_name(run_state.dungeon_level),
				" (practice)" if run_state.is_replay else ""],
		"Time %s (level %s)" % [RunState.format_time(run_state.run_time), RunState.format_time(run_state.level_time)],
		"Difficulty: %s" % Difficulty.display_name(run_state.difficulty),
		"Pact: %s" % Pacts.pact_text(run_state.pact),
	]
	for id: StringName in run_state.active_synergies():
		lines.append("Synergy - %s" % Pacts.synergy_text(id))
	if run_state.gold_damage_bonus() > 0.0:
		lines.append("Greed's Reward bonus: +%d%% damage" % roundi(run_state.gold_damage_bonus() * 100.0))
	return "
".join(lines)


## Objective line: Ancient Seals x/3 and what the boss gate still needs.
static func objective_text(run_state: RunState) -> String:
	var seals := "Ancient Seals %d/%d" % [run_state.seals_collected(), RunState.SEALS_REQUIRED]
	if not run_state.seals_complete():
		return "%s - break them to open the Warden's gate" % seals
	if not run_state.is_max_level():
		return "%s - reach Lv %d to open the Warden's gate" % [seals, run_state.max_level()]
	return "%s - the Warden's gate is open" % seals


## " x2" for stacks of two or more, "" for a single copy.
static func _stack_text(count: int) -> String:
	return " x%d" % count if count > 1 else ""


func _refresh() -> void:
	_shown_second = int(_run_state.run_time)
	_status.text = status_text(_run_state)
	_objective.text = objective_text(_run_state)
	var item_lines: Array[String] = []
	for id: StringName in _run_state.collected:
		item_lines.append("%s%s (%s)" % [RunState.ITEMS[id]["name"], _stack_text(_run_state.collected[id]), RunState.ITEMS[id]["effect"]])
	# Treasures with lasting stat bonuses are listed like items.
	for id: StringName in _run_state.treasures:
		var data: Dictionary = RunState.TREASURES[id]
		if RunState.STAT_KEYS.any(func(key: String) -> bool: return data.has(key)):
			item_lines.append("%s%s (%s)" % [data["name"], _stack_text(_run_state.treasures[id]), data["effect"]])
	_items.text = "
".join(item_lines)
	_items.visible = not item_lines.is_empty()
	_pulse_on_gain()
	if _run_state.is_max_level():
		_label.text = "Lv %d (MAX)   Gold %d" % [_run_state.level, _run_state.currency]
		return
	_label.text = "Lv %d   XP %d/%d   Gold %d" % [
		_run_state.level, _run_state.xp, _run_state.xp_to_next_level(), _run_state.currency]


## Shows `text` centred near the top, then fades it out.
func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_message.show()
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(message_duration)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)
	_message_tween.tween_callback(_message.hide)


## Pulses the level line when XP, gold or the level went up since the last refresh.
func _pulse_on_gain() -> void:
	var now := {"level": _run_state.level, "xp": _run_state.xp, "gold": _run_state.currency}
	if _last.is_empty() or _last.get("run") != _run_state.get_instance_id():
		_last = now
		_last["run"] = _run_state.get_instance_id()
		return
	var level_up: bool = now["level"] > _last["level"]
	var gold_up: bool = now["gold"] > _last["gold"]
	var xp_up: bool = now["xp"] > _last["xp"]
	_last.merge(now, true)
	if level_up:
		pulse_counter(Color(0.75, 0.55, 1.0), 1.25)
	elif gold_up:
		pulse_counter(Color(1.0, 0.85, 0.35), 1.12)
	elif xp_up:
		pulse_counter(Color(0.6, 0.85, 1.0), 1.08)


## Briefly scales and tints the level / XP / gold line.
func pulse_counter(color: Color, pop: float) -> void:
	if not is_inside_tree() or _label == null:
		return
	if _pulse_tween:
		_pulse_tween.kill()
	_label.pivot_offset = Vector2(0, _label.size.y / 2.0)
	_label.scale = Vector2.ONE * pop
	_label.modulate = color
	_pulse_tween = create_tween().set_parallel()
	_pulse_tween.tween_property(_label, ^"scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_label, ^"modulate", Color.WHITE, 0.45)


## Pops a centred reward banner: `title` in the rarity colour (with its rarity
## name), `description` below. A newer banner replaces the current one. The plain
## message line is hidden meanwhile (its text is kept).
func show_reward(title: String, description: String, rarity: Rarity = Rarity.RARE) -> void:
	if _reward_panel == null:
		return
	var color: Color = RARITY_COLORS[rarity]
	var tag: String = RARITY_NAMES[rarity]
	_reward_title.text = title if tag.is_empty() else "%s  -  %s" % [title, tag]
	_reward_title.add_theme_color_override(&"font_color", color)
	_reward_desc.text = description
	_reward_desc.visible = not description.is_empty()
	var style := _reward_panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	if style:
		style.border_color = color
	if _message_tween:
		_message_tween.kill()
	_message.hide()
	if _reward_tween:
		_reward_tween.kill()
	_reward_panel.show()
	_reward_panel.modulate.a = 1.0
	_reward_panel.reset_size()
	_reward_panel.pivot_offset = _reward_panel.size / 2.0
	_reward_panel.scale = Vector2(0.6, 0.6)
	_reward_tween = create_tween()
	_reward_tween.tween_property(_reward_panel, ^"scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_interval(reward_duration)
	_reward_tween.tween_property(_reward_panel, ^"modulate:a", 0.0, 0.5)
	_reward_tween.tween_callback(_reward_panel.hide)


## Title text of the visible reward banner ("" when hidden).
func reward_text() -> String:
	return _reward_title.text if _reward_panel and _reward_panel.visible else ""


func _build_reward_banner() -> void:
	var holder := CenterContainer.new()
	holder.name = "RewardBanner"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 92.0
	holder.offset_bottom = 200.0
	add_child(holder)
	_reward_panel = PanelContainer.new()
	_reward_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_reward_panel.add_theme_stylebox_override(&"panel", style)
	holder.add_child(_reward_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reward_panel.add_child(box)
	_reward_title = _banner_label(24)
	box.add_child(_reward_title)
	_reward_desc = _banner_label(16)
	_reward_desc.add_theme_color_override(&"font_color", Color(0.92, 0.92, 0.95))
	box.add_child(_reward_desc)
	_reward_panel.hide()


func _banner_label(size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	return label
