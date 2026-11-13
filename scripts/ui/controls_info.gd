class_name ControlsInfo
extends RefCounted
## Player controls list (Issue #55), shared by the main menu's Settings >
## Controls screen and the Home room floor guide (ControlsGuide), so both always
## show the same thing. Key names are read from the project's InputMap at
## runtime (key_text()), never hardcoded, so the list follows the real bindings.
##
## Each entry: "actions" (InputMap actions whose keys are shown together) or
## "key" (fixed text for input that has no action, e.g. mouse aiming), "text"
## (what it does) and optional "hold" (true: shown as "(hold)").

## Gameplay controls, in display order.
const GAMEPLAY: Array[Dictionary] = [
	{"actions": [&"move_up", &"move_left", &"move_down", &"move_right"], "text": "Move"},
	{"key": "Mouse", "text": "Aim"},
	{"actions": [&"attack"], "hold": true, "text": "Cast Fire Ball"},
	{"actions": [&"dash"], "text": "Dash"},
	{"actions": [&"interact"], "text": "Interact (Anvil, chests, altars, runes)"},
	{"actions": [&"ability_slot_1", &"ability_slot_2", &"ability_slot_3"], "text": "Use item slots (drag to reorder)"},
]

## Keys that only work while an Anvil menu is open (it then owns keys 1-7).
const ANVIL: Array[Dictionary] = [
	{"actions": [&"upgrade_1", &"upgrade_2", &"upgrade_3", &"upgrade_4"], "text": "Buy upgrade"},
	{"actions": [&"buy_supply_1", &"buy_supply_2", &"buy_supply_3"], "text": "Buy supply"},
]

## Names of mouse buttons by MouseButton index.
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left Click",
	MOUSE_BUTTON_RIGHT: "Right Click",
	MOUSE_BUTTON_MIDDLE: "Middle Click",
}


## Display name of the first key / button bound to `action` ("" if unbound).
static func action_key(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key:
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			if code != KEY_NONE:
				return OS.get_keycode_string(code)
		var mouse := event as InputEventMouseButton
		if mouse:
			return MOUSE_NAMES.get(mouse.button_index, "Mouse %d" % mouse.button_index)
	return ""


## Key text of `entry`: its fixed "key", or its actions' keys. Three or more
## consecutive digits become a range ("1-4"); other keys are joined with spaces
## ("W A S D"). "(hold)" is appended for hold entries.
static func key_text(entry: Dictionary) -> String:
	var text: String = entry.get("key", "")
	if text.is_empty():
		var keys: Array[String] = []
		for action: StringName in entry.get("actions", []):
			keys.append(action_key(action))
		text = _digit_range(keys) if _is_digit_run(keys) else " ".join(keys)
	if entry.get("hold", false):
		text += " (hold)"
	return text


## Every InputMap action named by GAMEPLAY and ANVIL.
static func listed_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Dictionary in GAMEPLAY + ANVIL:
		for action: StringName in entry.get("actions", []):
			result.append(action)
	return result


## Floor-guide line for the Anvil keys ("At the Anvil: 1-4 upgrades, 5-7 supplies").
static func anvil_line() -> String:
	return "At the Anvil: %s upgrades, %s supplies" % [key_text(ANVIL[0]), key_text(ANVIL[1])]


## `text` without its "(...)" detail, for the compact floor guide.
static func short_text(text: String) -> String:
	var cut := text.find(" (")
	return text.substr(0, cut) if cut >= 0 else text


static func _is_digit_run(keys: Array[String]) -> bool:
	if keys.size() < 3:
		return false
	for i in keys.size():
		if keys[i].length() != 1 or not keys[i].is_valid_int():
			return false
		if i > 0 and keys[i].to_int() != keys[i - 1].to_int() + 1:
			return false
	return true


static func _digit_range(keys: Array[String]) -> String:
	return "%s-%s" % [keys[0], keys[-1]]
