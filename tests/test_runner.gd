extends Node
## Automated logic tests for progression, quests, saving and level data.
## Run headless: godot --headless --path . res://tests/test_runner.tscn
## Uses its own save slot so a player's real save is never touched.

const TEST_SLOT := "user://test_savegame.json"

var _failures: PackedStringArray = []
var _count := 0


func _ready() -> void:
	SaveSystem.use_slot(TEST_SLOT)
	SaveSystem.delete_save()
	test_fragments()
	test_sets_and_flags()
	test_quests_order()
	test_quests_out_of_order()
	test_save_roundtrip()
	test_corrupt_and_backup()
	test_migration_and_future_versions()
	test_new_game_keeps_settings()
	test_level_data()
	test_junction_logic()
	test_facility_progression()
	test_facility_save_location()
	test_facility_puzzle_logic()
	SaveSystem.delete_save()
	print("TESTS: %d checks, %d failures" % [_count, _failures.size()])
	for f in _failures:
		print("TEST FAIL: ", f)
	get_tree().quit(1 if _failures.size() > 0 else 0)


func check(cond: bool, label: String) -> void:
	_count += 1
	if not cond:
		_failures.append(label)
		print("  FAIL ", label)


func test_fragments() -> void:
	GameState.reset()
	check(GameState.energy() == 0, "fresh state has no energy")
	check(GameState.collect_fragment(&"meadow_1"), "first collect succeeds")
	check(not GameState.collect_fragment(&"meadow_1"), "duplicate collect is refused")
	GameState.collect_fragment(&"forest_2")
	check(GameState.energy() == 2, "energy counts unique fragments")
	check(GameState.area_fragment_count(&"meadow") == 1, "per-area fragment count")
	check(GameData.area_of_fragment(&"garden_7") == &"garden", "area parsed from fragment id")
	check(GameData.total_fragments() == 42, "42 fragments in total (30 garden + 12 facility)")
	var garden := 0
	for area: StringName in GameData.AREA_IDS:
		garden += GameData.FRAGMENTS_PER_AREA[area]
	check(garden == 30, "the four garden areas keep their 30 fragments")
	check(GameData.area_of_fragment(&"reactor_3") == &"reactor", "facility fragment ids parse")


func test_sets_and_flags() -> void:
	GameState.reset()
	check(GameState.add_to_set(&"shrine_nodes", &"a") == 1, "set add")
	check(GameState.add_to_set(&"shrine_nodes", &"a") == 1, "set ignores duplicates")
	check(GameState.add_to_set(&"shrine_nodes", &"b") == 2, "set grows")
	check(GameState.set_has(&"shrine_nodes", &"b"), "set membership")
	GameState.set_flag(&"x", true)
	check(GameState.has_flag(&"x"), "flag set")
	check(not GameState.has_flag(&"y"), "unset flag false")


func test_quests_order() -> void:
	GameState.reset()
	check(Quests.current_id == &"wake", "first objective is waking up")
	GameState.set_flag(&"robot_awake", true)
	check(Quests.current_id == &"gather_meadow", "then gather energy")
	for i in GameData.GATE_ENERGY:
		GameState.collect_fragment(StringName("meadow_%d" % (i + 1)))
	check(Quests.current_id == &"power_gate", "then power the gate")
	GameState.set_flag(&"meadow_gate_open", true)
	check(Quests.current_id == &"enter_forest", "then enter the forest")
	GameState.set_flag(&"visited_forest", true)
	check(Quests.current_id == &"find_way", "then find a way")
	GameState.set_flag(&"saw_bridge", true)
	check(Quests.current_id == &"forest_switches", "then the switches")
	check(Quests.current_text().contains("0/3"), "switch progress text (%s)" % Quests.current_text())
	GameState.add_to_set(&"forest_switches", &"s1")
	check(Quests.current_text().contains("1/3"), "switch progress updates")


func test_quests_out_of_order() -> void:
	GameState.reset()
	# Doing later things first must still land on the right objective.
	GameState.set_flag(&"robot_awake", true)
	GameState.set_flag(&"meadow_gate_open", true)
	GameState.set_flag(&"visited_forest", true)
	GameState.set_flag(&"bridge_raised", true)
	for i in 3:
		GameState.add_to_set(&"forest_switches", StringName("s%d" % i))
	for i in 3:
		GameState.collect_fragment(StringName("meadow_%d" % (i + 1)))
	check(Quests.current_id == &"find_shrine", "skips completed objectives (%s)" % Quests.current_id)
	GameState.set_flag(&"garden_restored", true)
	GameState.set_flag(&"shrine_plaza_reached", true)
	for i in 4:
		GameState.add_to_set(&"shrine_nodes", StringName("n%d" % i))
	GameState.set_flag(&"shrine_restored", true)
	GameState.set_flag(&"visited_garden", true)
	for i in 3:
		GameState.add_to_set(&"resonators", StringName("r%d" % i))
	check(Quests.current_id == &"enter_lab", "after the garden, the lift to the facility (%s)" % Quests.current_id)
	GameState.set_flag(&"visited_lab", true)
	GameState.set_flag(&"visited_reactor", true)
	GameState.set_flag(&"visited_quantum", true)
	for s in ["couplers", "laser", "terminals"]:
		GameState.add_to_set(&"lab_power", StringName(s))
	for s in ["arms", "cores", "nodes"]:
		GameState.add_to_set(&"reactor_stability", StringName(s))
	for s in ["gravity", "phase", "time"]:
		GameState.add_to_set(&"quantum_systems", StringName(s))
	check(Quests.current_id == &"quantum_exit", "facility done except the exit (%s)" % Quests.current_id)
	GameState.set_flag(&"quantum_complete", true)
	check(Quests.current_id == &"explore", "ends in free exploration")


func test_save_roundtrip() -> void:
	GameState.reset()
	GameState.collect_fragment(&"meadow_1")
	GameState.collect_fragment(&"shrine_3")
	GameState.set_flag(&"robot_awake", true)
	GameState.add_to_set(&"shrine_nodes", &"node_energy")
	GameState.add_discovery(&"dock_plaque")
	GameState.mark_revealed(&"meadow_5")
	GameState.set_puzzle_state(&"mirror_a", 3)
	GameState.set_checkpoint(&"shrine_plaza")
	GameState.play_time = 123.5
	var before := GameState.to_dict()
	check(SaveSystem.save_game(), "save succeeds")
	check(SaveSystem.has_save(), "save exists")
	GameState.reset()
	check(GameState.energy() == 0, "reset clears state")
	check(SaveSystem.load_game(), "load succeeds")
	var after := GameState.to_dict()
	check(after["fragments"] == before["fragments"], "fragments restored")
	check(GameState.set_has(&"shrine_nodes", &"node_energy"), "sets restored")
	check(GameState.has_discovery(&"dock_plaque"), "discoveries restored")
	check(GameState.is_revealed(&"meadow_5"), "reveals restored")
	check(int(GameState.get_puzzle_state(&"mirror_a", -1)) == 3, "puzzle state restored")
	check(GameState.checkpoint_id == &"shrine_plaza", "checkpoint restored")
	check(is_equal_approx(GameState.play_time, 123.5), "play time restored")
	check(not GameState.collect_fragment(&"meadow_1"), "no duplicate reward after load")
	var summary := SaveSystem.read_summary()
	check(int(summary.get("energy", -1)) == 2, "menu summary reads energy")


func test_corrupt_and_backup() -> void:
	GameState.reset()
	GameState.collect_fragment(&"meadow_2")
	SaveSystem.save_game()
	GameState.collect_fragment(&"meadow_3")
	SaveSystem.save_game()  # previous save becomes the backup
	var f := FileAccess.open(TEST_SLOT, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	GameState.reset()
	check(SaveSystem.load_game(), "falls back to backup when the main save is corrupt")
	check(GameState.has_fragment(&"meadow_2"), "backup content loaded")
	SaveSystem.delete_save()
	check(not SaveSystem.has_save(), "delete removes saves")
	check(not SaveSystem.load_game(), "loading with no save fails gracefully")


func test_migration_and_future_versions() -> void:
	var v1 := {"game": SaveSystem.GAME_ID, "version": 1, "saved_at": 0,
		"state": {"fragments": ["meadow_1"], "flags": {"robot_awake": true}, "spawn": "meadow_gate"}}
	var f := FileAccess.open(TEST_SLOT, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	GameState.reset()
	check(SaveSystem.load_game(), "v1 save loads")
	check(GameState.checkpoint_id == &"meadow_gate", "v1 spawn migrated to checkpoint")
	var future := {"game": SaveSystem.GAME_ID, "version": 99, "state": {}}
	f = FileAccess.open(TEST_SLOT, FileAccess.WRITE)
	f.store_string(JSON.stringify(future))
	f.close()
	DirAccess.remove_absolute(TEST_SLOT.get_basename() + ".bak")
	check(SaveSystem.read_save_data().is_empty(), "future-version save rejected")
	var other := {"game": "something_else", "version": 1, "state": {}}
	f = FileAccess.open(TEST_SLOT, FileAccess.WRITE)
	f.store_string(JSON.stringify(other))
	f.close()
	check(SaveSystem.read_save_data().is_empty(), "foreign save rejected")
	SaveSystem.delete_save()


func test_new_game_keeps_settings() -> void:
	Settings.save_settings()
	var had_settings := FileAccess.file_exists(Settings.PATH)
	SaveSystem.delete_save()
	check(had_settings and FileAccess.file_exists(Settings.PATH), "deleting the save keeps settings")


func test_level_data() -> void:
	var ids := {}
	var per_area := {}
	var discoveries := {}
	for path in ["res://scenes/levels/meadow.tscn", "res://scenes/levels/mushroom_forest.tscn",
			"res://scenes/levels/forgotten_shrine.tscn", "res://scenes/levels/crystal_garden.tscn",
			"res://scenes/facility/research_lab.tscn", "res://scenes/facility/alien_reactor.tscn",
			"res://scenes/facility/quantum_lab.tscn"]:
		var state := (load(path) as PackedScene).get_state()
		for i in state.get_node_count():
			for p in state.get_node_property_count(i):
				var prop := state.get_node_property_name(i, p)
				var value: Variant = state.get_node_property_value(i, p)
				if prop == &"fragment_id":
					check(not ids.has(value), "fragment id %s unique" % value)
					ids[value] = true
					var area := GameData.area_of_fragment(value)
					per_area[area] = int(per_area.get(area, 0)) + 1
				elif prop == &"discovery_id":
					discoveries[value] = true
	for area: StringName in GameData.FRAGMENTS_PER_AREA:
		check(int(per_area.get(area, 0)) == GameData.FRAGMENTS_PER_AREA[area], "%s has %d fragments placed (%d)" % [area, GameData.FRAGMENTS_PER_AREA[area], per_area.get(area, 0)])
	for entry: Dictionary in GameData.DISCOVERIES:
		check(discoveries.has(entry["id"]), "discovery %s is placed in a level" % entry["id"])
	# Energy budget: every gate is reachable with fragments available before it.
	var before_shrine: int = GameData.FRAGMENTS_PER_AREA[&"meadow"] + GameData.FRAGMENTS_PER_AREA[&"forest"] + GameData.FRAGMENTS_PER_AREA[&"shrine"]
	check(GameData.FRAGMENTS_PER_AREA[&"meadow"] >= GameData.GATE_ENERGY, "meadow has enough energy for the gate")
	check(before_shrine >= GameData.SHRINE_NODE_ENERGY, "enough energy for the shrine node")
	check(GameData.total_fragments() >= GameData.HEART_ENERGY, "enough energy for the heart")


func test_junction_logic() -> void:
	check(JunctionPuzzle.connections("straight", 0) == ["N", "S"], "straight tile N-S")
	check(JunctionPuzzle.connections("straight", 1) == ["E", "W"], "straight tile E-W")
	check(JunctionPuzzle.connections("elbow", 0) == ["S", "E"], "elbow rot 0")
	check(JunctionPuzzle.connections("elbow", 3) == ["W", "S"], "elbow rot 3")


func test_facility_progression() -> void:
	GameState.reset()
	check(GameData.ALL_AREA_IDS.size() == 7, "seven areas in journey order")
	check(GameData.area_unlocked(&"meadow"), "meadow always unlocked for travel")
	check(not GameData.area_unlocked(&"lab"), "lab locked before visiting")
	GameState.enter_area(&"lab")
	check(GameData.area_unlocked(&"lab"), "visiting unlocks travel")
	for area: StringName in GameData.ALL_AREA_IDS:
		check(GameData.AREA_ENTRY_CHECKPOINT.has(area), "%s has an entry checkpoint" % area)
		check(GameData.area_name(area) != "", "%s has a name" % area)
	check(GameData.is_facility_area(&"reactor") and not GameData.is_facility_area(&"garden"), "facility area check")
	# Every checkpoint id used by the facility scenes is named (journal / travel).
	for path in ["res://scenes/facility/research_lab.tscn", "res://scenes/facility/alien_reactor.tscn", "res://scenes/facility/quantum_lab.tscn"]:
		var state := (load(path) as PackedScene).get_state()
		for i in state.get_node_count():
			for prop in state.get_node_property_count(i):
				if state.get_node_property_name(i, prop) == &"checkpoint_id":
					var id: StringName = state.get_node_property_value(i, prop)
					check(GameData.CHECKPOINT_NAMES.has(id), "checkpoint %s is named" % id)


func test_facility_save_location() -> void:
	GameState.reset()
	GameState.location = &"facility"
	GameState.current_area = &"reactor"
	GameState.checkpoint_id = &"reactor_cores"
	GameState.set_puzzle_state(&"reactor_levels", [3, 5, 0])
	SaveSystem.save_game()
	GameState.reset()
	check(GameState.location == &"world", "reset returns to the garden world")
	SaveSystem.load_game()
	check(GameState.location == &"facility", "location survives save/load")
	check(GameState.checkpoint_id == &"reactor_cores", "facility checkpoint survives save/load")
	var levels: Array = (GameState.get_puzzle_state(&"reactor_levels") as Array).map(func(v: Variant) -> int: return int(v))
	check(levels == [3, 5, 0], "reactor core levels survive save/load")
	# Saves from before the sci-fi areas have no location field: they load in the garden.
	var old := {"game": SaveSystem.GAME_ID, "version": 2, "saved_at": 0,
		"state": {"fragments": ["meadow_1"], "flags": {"robot_awake": true}, "checkpoint": "heart", "area": "garden"}}
	var f := FileAccess.open(TEST_SLOT, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	DirAccess.remove_absolute(TEST_SLOT.get_basename() + ".bak")
	check(SaveSystem.load_game(), "pre-facility save loads")
	check(GameState.location == &"world", "pre-facility save starts in the garden world")
	SaveSystem.delete_save()


## Pure logic checks of the facility puzzles (the scene-level behaviour is covered by
## tools/facility_playtest_runner.tscn).
func test_facility_puzzle_logic() -> void:
	var lab := load("res://scripts/facility/areas/lab_area.gd")
	var start: Array = lab.COUPLER_START
	var links: Array = lab.COUPLER_LINKS
	# Brute force: the couplers must have exactly one minimal solution, and it is K2, K3, K4.
	var best: Array = []
	var solutions := 0
	for mask in 32:
		var state := start.duplicate()
		var presses := []
		for k in 5:
			if mask & (1 << k):
				presses.append(k)
				for c: int in links[k]:
					state[c] = not state[c]
		if not state.has(false):
			solutions += 1
			if best.is_empty() or presses.size() < best.size():
				best = presses
	check(solutions == 1 and best == [1, 2, 3], "coupler puzzle has one solution: K2 K3 K4 (%s)" % [best])
	check(start.has(false), "couplers do not start solved")
	var order: Array = lab.TERMINAL_ORDER
	check(order == ["COOLANT", "CONTAINMENT", "FIELD", "CORE"], "terminal restart is the reverse of the logged shutdown")
	# Reactor cores: reachable (4, 4, 0) from (8, 0, 0) with the three one-way valves.
	var reactor := load("res://scripts/facility/areas/reactor_area.gd")
	var caps: Array = reactor.CAPS
	var moves := [[0, 1], [1, 2], [2, 0]]
	var seen := {str(reactor.START_LEVELS): 0}
	var frontier: Array = [reactor.START_LEVELS.duplicate()]
	var found := -1
	while not frontier.is_empty() and found < 0:
		var cur: Array = frontier.pop_front()
		for m: Array in moves:
			var amount: int = mini(cur[m[0]], caps[m[1]] - cur[m[1]])
			if amount <= 0:
				continue
			var nxt := cur.duplicate()
			nxt[m[0]] -= amount
			nxt[m[1]] += amount
			if not seen.has(str(nxt)):
				seen[str(nxt)] = int(seen[str(cur)]) + 1
				frontier.append(nxt)
				if nxt[0] == 4 and nxt[1] == 4:
					found = seen[str(nxt)]
	check(found == 7, "core balance solvable in 7 transfers (%d)" % found)
	var rhythm: Array = reactor.RHYTHM
	var dots: Array = reactor.PAD_DOTS
	check(rhythm.duplicate() != [1, 2, 3, 4] and dots.duplicate() != rhythm, "node order is not simply 1-2-3-4 or pad order")
	var sorted_r := rhythm.duplicate()
	sorted_r.sort()
	var sorted_d := dots.duplicate()
	sorted_d.sort()
	check(sorted_r == sorted_d, "every heartbeat group matches exactly one node")

