class_name RunSave
extends RefCounted
## Unfinished-run save file (Issue #63): one JSON file in user:// holding the
## state needed to resume the current run (RunState.to_save_data(), the Mage's
## HP and the Dungeon's room progress, see Dungeon.capture_save()).
##
## Format: an envelope {format, version, game_version, saved_at, checksum, data}
## where `data` is the run as a JSON string and `checksum` its MD5, so a
## damaged or hand-edited file is detected. `version` is the save format
## (VERSION; older formats go through _migrate(), newer ones are refused) and
## `game_version` the project's application/config/version: the dungeon is
## rebuilt from the run seed, so a save from another game version is treated
## as outdated rather than restored into a possibly different layout.
##
## Writes are atomic: the data is validated first (invalid data never replaces
## a save), written to a temporary file, read back, then moved over the old
## save. JSON (not ResourceSaver) is used because a loaded .tres can carry
## scripts, and plain data is easier to validate and migrate.
## In headless runs (the test suites) TEST_SAVE_PATH is used, so tests never
## touch the player's save; `path_override` lets tests pick another file.

enum Status { NONE, VALID, INVALID, OUTDATED }

const FORMAT := "abyss_run_save"
const VERSION := 1
const SAVE_PATH := "user://run_save.json"
const TEST_SAVE_PATH := "user://run_save_test.json"

static var path_override := ""


static func path() -> String:
	if not path_override.is_empty():
		return path_override
	return TEST_SAVE_PATH if DisplayServer.get_name() == "headless" else SAVE_PATH


static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


static func exists() -> bool:
	return FileAccess.file_exists(path())


## Validates and writes `data` (a Dungeon.capture_save() dictionary). Returns
## OK, or an error with the existing save left untouched.
static func write(data: Dictionary) -> Error:
	var problem := validate_data(data)
	if not problem.is_empty():
		push_error("RunSave: refusing to write an invalid save (%s)" % problem)
		return ERR_INVALID_DATA
	var body := JSON.stringify(data, "", true, true)
	var envelope := {
		"format": FORMAT, "version": VERSION, "game_version": game_version(),
		"saved_at": int(Time.get_unix_time_from_system()), "checksum": body.md5_text(), "data": body,
	}
	var text := JSON.stringify(envelope, "\t")
	var tmp := path() + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	var err := DirAccess.rename_absolute(tmp, path())
	if err != OK and FileAccess.file_exists(path()):
		# Some platforms refuse to rename over an existing file: move the old save
		# aside first and put it back if the new one cannot take its place.
		var backup := path() + ".bak"
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(path(), backup) == OK:
			err = DirAccess.rename_absolute(tmp, path())
			if err == OK:
				DirAccess.remove_absolute(backup)
			else:
				DirAccess.rename_absolute(backup, path())
	if err != OK:
		DirAccess.remove_absolute(tmp)
	return err


## Reads the save: {"status": Status, "data": Dictionary (VALID only),
## "message": String (why it is not VALID)}. Never changes the file.
static func read() -> Dictionary:
	if not exists():
		return _result(Status.NONE, "No unfinished run")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path()))
	if not parsed is Dictionary or parsed.get("format") != FORMAT:
		return _result(Status.INVALID, "The save file is damaged")
	var envelope: Dictionary = parsed
	var version: Variant = envelope.get("version")
	if not _is_int(version):
		return _result(Status.INVALID, "The save file is damaged")
	if int(version) > VERSION:
		return _result(Status.OUTDATED, "The save was made by a newer version of Abyss")
	if envelope.get("game_version") != game_version():
		return _result(Status.OUTDATED, "The save was made by another version of Abyss (%s)" % str(envelope.get("game_version")))
	var body: Variant = envelope.get("data")
	if not body is String or envelope.get("checksum") != (body as String).md5_text():
		return _result(Status.INVALID, "The save file is damaged")
	var data: Variant = JSON.parse_string(body)
	if not data is Dictionary:
		return _result(Status.INVALID, "The save file is damaged")
	data = _migrate(data, int(version))
	if data.is_empty():
		return _result(Status.OUTDATED, "The save format is no longer supported")
	var problem := validate_data(data)
	if not problem.is_empty():
		return _result(Status.INVALID, "The save file is damaged (%s)" % problem)
	var result := _result(Status.VALID, "")
	result["data"] = data
	return result


## Deletes the save (and a leftover temporary file).
static func delete() -> void:
	for file in [path(), path() + ".tmp", path() + ".bak"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## "" if `data` has the shape Dungeon.restore needs, otherwise the first problem.
## Checks types, ranges and catalog ids; room indexes are checked against the
## rebuilt level by the Dungeon.
static func validate_data(data: Dictionary) -> String:
	if not data.get("run") is Dictionary or not data.get("mage") is Dictionary or not data.get("dungeon") is Dictionary:
		return "missing sections"
	var run_problem := RunState.validate_save_data(data["run"])
	if not run_problem.is_empty():
		return run_problem
	var mage: Dictionary = data["mage"]
	if not _is_number(mage.get("max_health")) or not _is_number(mage.get("health")) \
			or float(mage["max_health"]) <= 0.0 or float(mage["health"]) <= 0.0 \
			or float(mage["health"]) > float(mage["max_health"]) + 0.01:
		return "mage health"
	var dungeon: Dictionary = data["dungeon"]
	for key in ["current_index", "run_id", "unlocked_tier", "layout"]:
		if not _is_int(dungeon.get(key)):
			return "dungeon.%s" % key
	if int(dungeon["current_index"]) < 0:
		return "dungeon.current_index"
	for key in ["in_combat", "victory", "victory_recorded", "final_anvil"]:
		if not dungeon.get(key) is bool:
			return "dungeon.%s" % key
	if not _is_number(dungeon.get("reach_time")) or not dungeon.get("entry_door") is String:
		return "dungeon entry"
	var pos: Variant = dungeon.get("position")
	if not pos is Array or pos.size() != 2 or not _is_number(pos[0]) or not _is_number(pos[1]):
		return "dungeon.position"
	if not dungeon.get("rooms") is Array or (dungeon["rooms"] as Array).is_empty():
		return "dungeon.rooms"
	var seen := {}
	var has_current := false
	for entry: Variant in dungeon["rooms"]:
		if not entry is Dictionary or not _is_int(entry.get("index")) or int(entry["index"]) < 0 \
				or not entry.get("cleared") is bool or not entry.get("pickups") is Array:
			return "dungeon.rooms entry"
		if seen.has(int(entry["index"])):
			return "dungeon.rooms duplicate"
		seen[int(entry["index"])] = true
		has_current = has_current or int(entry["index"]) == int(dungeon["current_index"])
		for pickup: Variant in entry["pickups"]:
			if not pickup is Dictionary or not pickup.get("name") is String or not pickup.get("id") is String \
					or not RunState.ITEMS.has(StringName(pickup["id"])):
				return "dungeon.rooms pickups"
	if not has_current:
		return "dungeon.current room not visited"
	return ""


## Converts data of an older save `version` to the current format ({} = unsupported).
## Version 1 is the first format, so there is nothing to convert yet.
static func _migrate(data: Dictionary, version: int) -> Dictionary:
	return data if version == VERSION else {}


static func _result(status: Status, message: String) -> Dictionary:
	return {"status": status, "data": {}, "message": message}


## JSON numbers load as floats: true for an int, or a float holding a whole number.
static func _is_int(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))


static func _is_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))
