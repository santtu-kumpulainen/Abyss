extends SceneTree
## Headless check of the Issue #49 minimap home marker (Stage 6): the house
## is drawn on Dungeon.start_room's cell, stays there through room changes,
## matches the Home Teleport destination, follows a new level's start room
## (and any change of start_room, nothing cached) and leaves the rest of the
## minimap unchanged.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_home_marker.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4949
const SCENE := "res://scenes/dungeon/dungeon.tscn"

var _failures := 0
var _dungeon: Dungeon
var _map: DungeonMap
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	await _load()
	await _test_start()
	await _test_room_changes()
	await _test_teleport_destination()
	await _test_new_level()
	await _test_live_start_room()
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_start() -> void:
	_check(_map != null, "the Dungeon has a minimap")
	_check(_map.home_index() == _dungeon.start_room and _dungeon.current_index == _dungeon.start_room,
			"the home marker is on start_room (%d), where the run starts" % _dungeon.start_room)
	await _redraw()
	_check(_drawn_on(_dungeon.start_room), "the house is drawn inside the start room's cell")
	_check(_map.home_marker_rect(_dungeon.start_room).size.x >= 12.0, "readable size (%.0f px)" % _map.home_marker_rect(0).size.x)
	# The map layout itself is unchanged: cells on the grid, existing markers.
	var a := _map.cell_rect(0)
	var b := _map.cell_rect(1)
	var step := (_map.cell_size + _map.gap)
	var delta := Vector2(_dungeon.rooms[1].cell - _dungeon.rooms[0].cell) * step
	_check(a.size == Vector2.ONE * _map.cell_size and (b.position - a.position).is_equal_approx(delta), "cells keep their size and grid spacing")
	_check(_map.marker_color(_dungeon.start_room).a == 0.0, "the start room has no treasure diamond to collide with")


func _test_room_changes() -> void:
	var home := _dungeon.start_room
	var visited := 0
	for i in _dungeon.rooms.size():
		if i == home or i == _dungeon.boss_index() or visited >= 3:
			continue
		_dungeon.enter_room(i)
		await _redraw()
		visited += 1
		if _map.home_index() != home or not _drawn_on(home) or _drawn_on(i):
			_check(false, "after entering room %d the marker stays on the start room" % i)
			return
	_check(visited == 3, "after 3 room changes the house is still on the start room, not the current one")
	_dungeon.enter_room(home)
	await _redraw()
	_check(_drawn_on(home) and _dungeon.current_index == home, "back home: the house is drawn over the current-room cell")


func _test_teleport_destination() -> void:
	_run.add_rewards(0, 1000)
	_run.buy_consumable(HomeTeleport.ITEM)
	var away := _away_room()
	_dungeon.enter_room(away)
	await _ticks(3)
	var marked := _map.home_index()
	_dungeon.home_teleport.try_start()
	for i in 120:
		if not _dungeon.home_teleport.is_busy():
			break
		await physics_frame
	await _redraw()
	_check(_dungeon.current_index == marked and _drawn_on(_dungeon.current_index),
			"Home Teleport lands in the marked room (%d)" % marked)


func _test_new_level() -> void:
	var old_cell := _dungeon.rooms[_dungeon.start_room].cell
	_dungeon.enter_room(_away_room())
	await _ticks(3)
	_run.boss_defeated = true
	_run._relic_claimed = true
	_dungeon.victory = true
	_check(_dungeon.advance_level() and _run.dungeon_level == 2, "setup: level 2 generated")
	await _redraw()
	var home := _dungeon.start_room
	_check(_map.home_index() == home and _drawn_on(home), "level 2: the house is on the new start_room (%d)" % home)
	_check(_map.home_marker_rect(home).get_center().is_equal_approx(_map.cell_rect(home).get_center()),
			"level 2: drawn at the new start cell %s (level 1: %s)" % [_dungeon.rooms[home].cell, old_cell])
	for i in _dungeon.rooms.size():
		if i != home and _drawn_on(i):
			_check(false, "no house on another room after the level change")
			return
	_check(true, "no house on another room after the level change")


func _test_live_start_room() -> void:
	# Nothing is cached: any change of Dungeon.start_room moves the house.
	var home := _dungeon.start_room
	var other := _away_room()
	_dungeon.start_room = other
	_map.queue_redraw()
	await _redraw()
	_check(_map.home_index() == other and _drawn_on(other) and not _drawn_on(home), "the marker reads start_room live (moved to %d)" % other)
	_dungeon.start_room = home
	_map.queue_redraw()
	await _redraw()
	_check(_drawn_on(home), "and back")


# --- Helpers ----------------------------------------------------------------------

## True if the last draw put the house inside room `index`'s cell.
func _drawn_on(index: int) -> bool:
	var drawn := _map.drawn_home_rect()
	return drawn.has_area() and _map.cell_rect(index).encloses(drawn)


func _away_room() -> int:
	for i in _dungeon.rooms.size():
		if i != _dungeon.start_room and i != _dungeon.boss_index():
			return i
	return -1


func _load() -> void:
	change_scene_to_file(SCENE)
	for i in 600:
		if current_scene != null and current_scene.is_node_ready():
			break
		await physics_frame
	await _ticks(2)
	_dungeon = current_scene as Dungeon
	_map = _dungeon.get_node_or_null(^"DungeonMap/Map") as DungeonMap
	_run = _dungeon.run_state


## Until the map has drawn again.
func _redraw() -> void:
	await process_frame
	await process_frame


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
