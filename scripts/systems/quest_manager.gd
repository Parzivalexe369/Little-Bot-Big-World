extends Node
## Data-driven objective tracker. Objectives live in res://resources/quests.json.
## The current objective is always derived from GameState, so loading a save or completing
## things out of order can never leave the tracker out of sync.

signal objective_changed(objective_id: StringName, text: String)
signal objective_completed(objective_id: StringName)
signal objective_progress(objective_id: StringName, text: String)

const QUEST_FILE := "res://resources/quests.json"

var objectives: Array[Dictionary] = []
var current_id: StringName = &""
var _current_text := ""
var _suppress_completion := true


func _ready() -> void:
	_load_definitions()
	GameState.flag_changed.connect(func(_f: StringName, _v: Variant) -> void: refresh())
	GameState.fragment_collected.connect(func(_id: StringName, _t: int) -> void: refresh())
	GameState.discovery_found.connect(func(_id: StringName) -> void: refresh())
	GameState.state_loaded.connect(_on_state_replaced)
	GameState.state_reset.connect(_on_state_replaced)
	_on_state_replaced()


func current_text() -> String:
	return _current_text


func current_objective() -> Dictionary:
	for objective in objectives:
		if objective["id"] == String(current_id):
			return objective
	return {}


## Re-evaluates the objective list. Emits completion for each objective finished since last time.
func refresh() -> void:
	var previous := current_id
	var next_index := _first_incomplete_index()
	var next_id: StringName = StringName(objectives[next_index]["id"]) if next_index >= 0 else &""
	if next_id != previous:
		if not _suppress_completion and previous != &"":
			var prev_index := _index_of(previous)
			for i in range(maxi(prev_index, 0), next_index if next_index >= 0 else objectives.size()):
				objective_completed.emit(StringName(objectives[i]["id"]))
		current_id = next_id
		_current_text = _format_text(objectives[next_index]) if next_index >= 0 else ""
		GameState.flags[&"objective"] = String(current_id)
		objective_changed.emit(current_id, _current_text)
	else:
		var text := _format_text(objectives[next_index]) if next_index >= 0 else ""
		if text != _current_text:
			_current_text = text
			objective_progress.emit(current_id, text)


## Progress of the current objective as (count, target), or (-1, -1) if it has no counter.
## Read-only helper for the HUD's progress bar.
func current_progress() -> Vector2i:
	var objective := current_objective()
	if objective.is_empty():
		return Vector2i(-1, -1)
	if objective.has("progress"):
		var progress: Dictionary = objective["progress"]
		return Vector2i(GameState.set_count(StringName(progress["set"])), _resolve_number(progress["target"]))
	var done: Dictionary = objective.get("done", {})
	if done.has("energy"):
		return Vector2i(GameState.energy(), _resolve_number(done["energy"]))
	return Vector2i(-1, -1)


func is_condition_met(condition: Dictionary) -> bool:
	if condition.has("never"):
		return false
	if condition.has("any"):
		for sub: Dictionary in condition["any"]:
			if is_condition_met(sub):
				return true
		return false
	if condition.has("flag"):
		return GameState.has_flag(StringName(condition["flag"]))
	if condition.has("energy"):
		return GameState.energy() >= _resolve_number(condition["energy"])
	if condition.has("set"):
		return GameState.set_count(StringName(condition["set"])) >= _resolve_number(condition.get("count", 1))
	return false


func _on_state_replaced() -> void:
	_suppress_completion = true
	current_id = &""
	refresh()
	_suppress_completion = false


func _first_incomplete_index() -> int:
	for i in objectives.size():
		if not is_condition_met(objectives[i]["done"]):
			return i
	return -1


func _index_of(objective_id: StringName) -> int:
	for i in objectives.size():
		if objectives[i]["id"] == String(objective_id):
			return i
	return -1


func _format_text(objective: Dictionary) -> String:
	var text: String = objective.get("text", "")
	var values := {
		"energy": GameState.energy(),
		"gate_energy": GameData.GATE_ENERGY,
		"heart_energy": GameData.HEART_ENERGY,
		"total_fragments": GameData.total_fragments(),
		"discoveries": GameState.discoveries.size(),
		"total_discoveries": GameData.DISCOVERIES.size(),
	}
	if objective.has("progress"):
		var progress: Dictionary = objective["progress"]
		values["count"] = GameState.set_count(StringName(progress["set"]))
		values["target"] = _resolve_number(progress["target"])
	return text.format(values)


func _resolve_number(value: Variant) -> int:
	if value is String:
		match value:
			"gate_energy": return GameData.GATE_ENERGY
			"heart_energy": return GameData.HEART_ENERGY
			"shrine_node_energy": return GameData.SHRINE_NODE_ENERGY
			"shrine_node_count": return GameData.SHRINE_NODE_COUNT
			"forest_switch_count": return GameData.FOREST_SWITCH_COUNT
			"resonator_count": return GameData.RESONATOR_COUNT
			"lab_power_count": return GameData.LAB_POWER_COUNT
			"reactor_stability_count": return GameData.REACTOR_STABILITY_COUNT
			"quantum_system_count": return GameData.QUANTUM_SYSTEM_COUNT
			_: return int(value)
	return int(value)


func _load_definitions() -> void:
	objectives.clear()
	var text := FileAccess.get_file_as_string(QUEST_FILE)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not (parsed.get("objectives") is Array):
		push_error("Quest definitions missing or invalid: %s" % QUEST_FILE)
		objectives.append({"id": "explore", "text": "Explore.", "done": {"never": true}})
		return
	for entry: Variant in parsed["objectives"]:
		if entry is Dictionary and entry.has("id") and entry.has("done"):
			objectives.append(entry)
