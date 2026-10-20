extends Node
## Central progression state for the current playthrough.
## Everything here is plain data so it can be saved, loaded and tested without the world.

signal fragment_collected(fragment_id: StringName, total: int)
signal flag_changed(flag: StringName, value: Variant)
signal discovery_found(discovery_id: StringName)
signal object_revealed(object_id: StringName)
signal area_entered(area_id: StringName)
signal checkpoint_reached(checkpoint_id: StringName)
signal state_reset
signal state_loaded

var collected_fragments: Dictionary = {}
var flags: Dictionary = {}
var discoveries: Dictionary = {}
var revealed: Dictionary = {}
var puzzle_states: Dictionary = {}
var checkpoint_id: StringName = &"station"
var current_area: StringName = &"meadow"
var play_time: float = 0.0
## True while gameplay is running (not in menus). Play time only advances then.
var in_gameplay := false


func _process(delta: float) -> void:
	if in_gameplay and not get_tree().paused:
		play_time += delta


func reset() -> void:
	collected_fragments.clear()
	flags.clear()
	discoveries.clear()
	revealed.clear()
	puzzle_states.clear()
	checkpoint_id = &"station"
	current_area = &"meadow"
	play_time = 0.0
	state_reset.emit()


# --- Energy fragments -------------------------------------------------------

func energy() -> int:
	return collected_fragments.size()


func has_fragment(fragment_id: StringName) -> bool:
	return collected_fragments.has(fragment_id)


## Returns false when the fragment was already collected (prevents duplicate rewards).
func collect_fragment(fragment_id: StringName) -> bool:
	if fragment_id == &"" or collected_fragments.has(fragment_id):
		return false
	collected_fragments[fragment_id] = true
	fragment_collected.emit(fragment_id, energy())
	return true


func area_fragment_count(area_id: StringName) -> int:
	var count := 0
	for fragment_id: StringName in collected_fragments:
		if GameData.area_of_fragment(fragment_id) == area_id:
			count += 1
	return count


# --- Flags and counters -----------------------------------------------------

func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func has_flag(flag: StringName) -> bool:
	return bool(flags.get(flag, false))


func set_flag(flag: StringName, value: Variant = true) -> void:
	if flags.get(flag) == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)


## Adds a member to a named set flag (e.g. which shrine nodes are on) and returns the new count.
func add_to_set(flag: StringName, member: StringName) -> int:
	var members: Array = flags.get(flag, [])
	if not members.has(String(member)):
		members = members.duplicate()
		members.append(String(member))
		flags[flag] = members
		flag_changed.emit(flag, members)
	return members.size()


func set_count(flag: StringName) -> int:
	var members: Variant = flags.get(flag, [])
	return (members as Array).size() if members is Array else 0


func set_has(flag: StringName, member: StringName) -> bool:
	var members: Variant = flags.get(flag, [])
	return members is Array and (members as Array).has(String(member))


# --- Discoveries, reveals, puzzles --------------------------------------------

func add_discovery(discovery_id: StringName) -> bool:
	if discoveries.has(discovery_id):
		return false
	discoveries[discovery_id] = true
	discovery_found.emit(discovery_id)
	return true


func has_discovery(discovery_id: StringName) -> bool:
	return discoveries.has(discovery_id)


func mark_revealed(object_id: StringName) -> void:
	if revealed.has(object_id):
		return
	revealed[object_id] = true
	object_revealed.emit(object_id)


func is_revealed(object_id: StringName) -> bool:
	return revealed.has(object_id)


func set_puzzle_state(puzzle_id: StringName, value: Variant) -> void:
	puzzle_states[puzzle_id] = value


func get_puzzle_state(puzzle_id: StringName, default: Variant = null) -> Variant:
	return puzzle_states.get(puzzle_id, default)


# --- Location ---------------------------------------------------------------

func set_checkpoint(new_checkpoint: StringName) -> bool:
	if new_checkpoint == checkpoint_id:
		return false
	checkpoint_id = new_checkpoint
	checkpoint_reached.emit(new_checkpoint)
	return true


func enter_area(area_id: StringName) -> void:
	if area_id == current_area:
		return
	current_area = area_id
	set_flag(StringName("visited_%s" % area_id), true)
	area_entered.emit(area_id)


# --- Serialization ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"fragments": _keys_as_strings(collected_fragments),
		"flags": _flags_to_json(),
		"discoveries": _keys_as_strings(discoveries),
		"revealed": _keys_as_strings(revealed),
		"puzzles": puzzle_states.duplicate(true),
		"checkpoint": String(checkpoint_id),
		"area": String(current_area),
		"play_time": play_time,
	}


func from_dict(data: Dictionary) -> void:
	collected_fragments.clear()
	flags.clear()
	discoveries.clear()
	revealed.clear()
	puzzle_states.clear()
	for id: Variant in data.get("fragments", []):
		collected_fragments[StringName(str(id))] = true
	var raw_flags: Variant = data.get("flags", {})
	if raw_flags is Dictionary:
		for key: Variant in raw_flags:
			flags[StringName(str(key))] = raw_flags[key]
	for id: Variant in data.get("discoveries", []):
		discoveries[StringName(str(id))] = true
	for id: Variant in data.get("revealed", []):
		revealed[StringName(str(id))] = true
	var raw_puzzles: Variant = data.get("puzzles", {})
	if raw_puzzles is Dictionary:
		for key: Variant in raw_puzzles:
			puzzle_states[StringName(str(key))] = raw_puzzles[key]
	checkpoint_id = StringName(str(data.get("checkpoint", "station")))
	current_area = StringName(str(data.get("area", "meadow")))
	play_time = float(data.get("play_time", 0.0))
	state_loaded.emit()


func _keys_as_strings(source: Dictionary) -> Array:
	var out: Array = []
	for key: Variant in source:
		out.append(String(key))
	out.sort()
	return out


func _flags_to_json() -> Dictionary:
	var out := {}
	for key: Variant in flags:
		out[String(key)] = flags[key]
	return out
