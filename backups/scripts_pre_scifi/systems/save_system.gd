extends Node
## Versioned JSON save file in the user data directory.
## Writes go to a temporary file first and are then swapped in, so a crash mid-write
## never corrupts the existing save.

signal saved
signal save_failed(reason: String)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 2
const GAME_ID := "little_bot_big_world"

var save_path := SAVE_PATH
var _pending_timer := -1.0
## Optional provider for the live player transform; the world registers it.
var player_snapshot_provider: Callable


func _process(delta: float) -> void:
	if _pending_timer >= 0.0:
		_pending_timer -= delta
		if _pending_timer < 0.0:
			save_game()


## Debounced save, used after small events (fragments, reveals) so bursts write once.
## Redirects saving to a separate file (used by automated tests so real saves are untouched).
func use_slot(path: String) -> void:
	save_path = path


func _temp_path() -> String:
	return save_path.get_basename() + ".tmp"


func _backup_path() -> String:
	return save_path.get_basename() + ".bak"


func request_save(delay: float = 1.5) -> void:
	if _pending_timer < 0.0 or delay < _pending_timer:
		_pending_timer = delay


func has_save() -> bool:
	return not read_save_data().is_empty()


func save_game() -> bool:
	_pending_timer = -1.0
	var state := GameState.to_dict()
	if player_snapshot_provider.is_valid():
		var snapshot: Variant = player_snapshot_provider.call()
		if snapshot is Dictionary:
			state["player"] = snapshot
	var payload := {
		"game": GAME_ID,
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"state": state,
	}
	var file := FileAccess.open(_temp_path(), FileAccess.WRITE)
	if file == null:
		var reason := "Could not open save file (%s)" % error_string(FileAccess.get_open_error())
		push_warning(reason)
		save_failed.emit(reason)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		save_failed.emit("No access to user directory")
		return false
	if dir.file_exists(save_path.get_file()):
		dir.copy(save_path, _backup_path())
		dir.remove(save_path.get_file())
	var err := dir.rename(_temp_path(), save_path)
	if err != OK:
		save_failed.emit("Could not finalize save (%s)" % error_string(err))
		return false
	saved.emit()
	return true


## Returns the validated, migrated save payload or an empty dictionary.
func read_save_data() -> Dictionary:
	var data := _read_file(save_path)
	if data.is_empty():
		data = _read_file(_backup_path())
	return data


func load_game() -> bool:
	var data := read_save_data()
	if data.is_empty():
		return false
	GameState.from_dict(data["state"])
	return true


func delete_save() -> void:
	_pending_timer = -1.0
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for path in [save_path, _backup_path(), _temp_path()]:
		if dir.file_exists(path.get_file()):
			dir.remove(path.get_file())


## Small summary for the main menu "Continue" button.
func read_summary() -> Dictionary:
	var data := read_save_data()
	if data.is_empty():
		return {}
	var state: Dictionary = data["state"]
	return {
		"energy": (state.get("fragments", []) as Array).size(),
		"area": StringName(str(state.get("area", "meadow"))),
		"play_time": float(state.get("play_time", 0.0)),
		"saved_at": float(data.get("saved_at", 0.0)),
	}


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Save file %s is not valid JSON: %s" % [path, json.get_error_message()])
		return {}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	if data.get("game", "") != GAME_ID or not (data.get("state") is Dictionary):
		push_warning("Save file %s is not a Little Bot save." % path)
		return {}
	return _migrate(data)


## Upgrades older save layouts in place. Unknown future versions are rejected.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("Save file is from a newer version (%d)." % version)
		return {}
	var state: Dictionary = data["state"]
	if version < 2:
		# v1 stored the checkpoint under "spawn" and had no puzzle table.
		if state.has("spawn") and not state.has("checkpoint"):
			state["checkpoint"] = state["spawn"]
		if not state.has("puzzles"):
			state["puzzles"] = {}
	data["version"] = SAVE_VERSION
	return data
