class_name ControlsGuide
extends Node2D
## In-world controls guide (Issue #55): a dark stone plate on the Home room
## floor listing ControlsInfo's gameplay controls and Anvil keys. It is centred
## on this node, drawn on the floor (z_index above the floor tiles, below every
## character and object) and never takes mouse input or has collision, so it
## cannot block movement, casting or interaction.

const TITLE_COLOR := Color(0.75, 0.55, 1, 1)
## Same gold as the Anvil prompt and the ability bar key labels.
const KEY_COLOR := Color(1, 0.9, 0.55, 1)
const TEXT_COLOR := Color(0.9, 0.9, 0.95, 1)
const NOTE_COLOR := Color(0.7, 0.7, 0.78, 1)

@export var title_size: int = 18
@export var font_size: int = 14
@export var plate_color := Color(0.05, 0.04, 0.08, 0.6)
@export var border_color := Color(0.45, 0.38, 0.6, 0.7)

## The plate (built in _ready); its rect is centred on this node.
var panel: PanelContainer


func _ready() -> void:
	panel = PanelContainer.new()
	panel.name = "Plate"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = plate_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override(&"panel", style)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 2)
	panel.add_child(rows)
	rows.add_child(_label("Controls", title_size, TITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 2)
	rows.add_child(grid)
	for entry: Dictionary in ControlsInfo.GAMEPLAY:
		grid.add_child(_label(ControlsInfo.key_text(entry), font_size, KEY_COLOR, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_label(ControlsInfo.short_text(entry["text"]), font_size, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT))
	rows.add_child(_label(ControlsInfo.anvil_line(), font_size - 1, NOTE_COLOR, HORIZONTAL_ALIGNMENT_CENTER))
	panel.resized.connect(_center)
	add_child(panel)
	_center()


## Plate rect in this node's parent coordinates (room coordinates in a Room).
func plate_rect() -> Rect2:
	return Rect2(position + panel.position, panel.size) if panel else Rect2(position, Vector2.ZERO)


## Every text line shown, top to bottom (title, controls as "keys what", Anvil line).
func shown_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if panel == null:
		return lines
	for node in panel.find_children("*", "Label", true, false):
		lines.append((node as Label).text)
	return lines


func _center() -> void:
	panel.position = -panel.size / 2.0


func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"outline_size", 4)
	return label
