extends Node
## Automated playthrough of the three sci-fi areas (5 research facility, 6 alien reactor,
## 7 quantum lab). Starts from a finished garden, rides the lift down and solves every puzzle
## through the real Interactor (focus + interact input), including wrong attempts, resets,
## hazards, real low-gravity hops, dimension collision, time freeze, save/continue in the
## facility, the travel screen, and the trip home. Screenshots: docs/captures/facility_*.png
## Usage (windowed): godot --path . res://tools/facility_playtest_runner.tscn [-- noshots]

const SHOTS := "res://docs/captures/"
const TEST_SLOT := "user://facility_test_save.json"

var facility: FacilityWorld
var player: Player
var failures: PackedStringArray = []
var shot_index := 0
var take_shots := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	get_window().size = Vector2i(1600, 900)
	take_shots = not OS.get_cmdline_user_args().has("noshots")
	SaveSystem.use_slot(TEST_SLOT)
	SaveSystem.delete_save()
	GameState.reset()
	for flag in [&"robot_awake", &"meadow_gate_open", &"bridge_raised", &"shrine_restored", &"garden_restored",
			&"visited_forest", &"visited_shrine", &"visited_garden", &"saw_bridge", &"shrine_plaza_reached"]:
		GameState.set_flag(flag, true)
	for s in ["s1", "s2", "s3"]:
		GameState.add_to_set(&"forest_switches", StringName(s))
	for s in ["a", "b", "c", "d"]:
		GameState.add_to_set(&"shrine_nodes", StringName(s))
	for s in ["a", "b", "c"]:
		GameState.add_to_set(&"resonators", StringName(s))
	for area: StringName in GameData.AREA_IDS:
		for i in GameData.FRAGMENTS_PER_AREA[area]:
			GameState.collect_fragment(StringName("%s_%d" % [area, i + 1]))
	# Keep this runner alive across scene changes: a placeholder becomes the current scene.
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	check(Quests.current_id == &"enter_lab", "objective after the garden is the lift (%s)" % Quests.current_id)
	SceneRouter.travel_to(&"lab")
	await _wait_until(func() -> bool: return get_tree().current_scene is FacilityWorld, 30.0)
	await _attach()
	check(GameState.current_area == &"lab", "arrived in the research facility")
	check(Quests.current_id == &"lab_power", "objective: restore the facility's power (%s)" % Quests.current_id)
	await _shot("lab_arrival")

	await lab_test()
	await reactor_test()
	await quantum_test()
	await continue_test()
	await travel_test()

	print("FACILITY RESULT: %d failures" % failures.size())
	for f in failures:
		print("FACILITY FAIL: ", f)
	print("FACILITY energy=%d discoveries=%d objective=%s" % [GameState.energy(), GameState.discoveries.size(), Quests.current_id])
	SaveSystem.delete_save()
	get_tree().quit(1 if failures.size() > 0 else 0)


func _attach() -> void:
	facility = get_tree().current_scene as FacilityWorld
	facility.pause_on_focus_loss = false
	player = facility.player
	await _seconds(1.5)


# --- Area 5 -------------------------------------------------------------------------------

func lab_test() -> void:
	var lab := facility.areas[0]
	var door_a: ScifiParts.Door = lab.get("_door_a")
	check(not door_a.is_open, "lab: arrival door starts sealed")
	var door_it := door_a.find_children("*", "Interactable", true, false)[0] as Interactable
	check(door_it.locked, "lab: sealed door shows a locked prompt (%s)" % door_it.get_prompt())
	# Couplers: a wrong press flips its conduits, pressing again flips them back.
	var before: Array = (lab.get("_conduits") as Array).duplicate()
	await use_interactable(_find_prompt(lab, "Turn coupler K1"))
	var after: Array = (lab.get("_conduits") as Array).duplicate()
	check(before != after and after[0] != before[0] and after[1] != before[1] and after[2] == before[2], "lab: K1 flips conduits C1 and C2 only")
	await use_interactable(_find_prompt(lab, "Turn coupler K1"))
	check((lab.get("_conduits") as Array) == before, "lab: pressing K1 again undoes it")
	await use_interactable(_find_prompt(lab, "Turn coupler K5"))
	await use_interactable(_find_prompt(lab, "Reset the couplers"))
	check((lab.get("_conduits") as Array) == lab.COUPLER_START, "lab: reset lever restores the start state")
	for k in ["K2", "K3", "K4"]:
		await use_interactable(_find_prompt(lab, "Turn coupler " + k))
	check(GameState.set_has(&"lab_power", &"couplers"), "lab: couplers energize the main bus")
	await _seconds(2.0)
	await _wait_cinematic()
	check(door_a.is_open, "lab: arrival door opens with power")
	await _shot("lab_couplers")
	# Optics: the beam is blocked until the carts are placed.
	check(not GameState.set_has(&"lab_power", &"laser"), "lab: laser not routed at start")
	var door_b: ScifiParts.Door = lab.get("_door_b")
	check(not door_b.is_open, "lab: control door sealed before the laser")
	for cart_name: String in ["cart_a", "cart_c", "cart_b"]:
		var cart := lab.find_child(cart_name, true, false) as Node3D
		var pushes := 3 if cart_name != "cart_b" else 2
		for i in pushes:
			await use_interactable(cart.find_children("*", "Interactable", true, false)[0] as Interactable)
			await _seconds(1.0)
	await _seconds(0.5)
	check(GameState.set_has(&"lab_power", &"laser"), "lab: mirror carts route the laser to the receiver")
	await _wait_cinematic()
	check(door_b.is_open, "lab: control door opens")
	await _shot("lab_laser")
	# Hidden lab: the loose vent is found with the scanner.
	var vent_it: Interactable = lab.get("_vent_interactable")
	check(not vent_it.enabled, "lab: vent not usable before scanning")
	await place(lab.to_global(Vector3(11.0, 0.2, -2.0)))
	player.try_scan()
	await _seconds(1.8)
	check(vent_it.enabled, "lab: scanning reveals the loose vent")
	await use_interactable(vent_it)
	check(GameState.is_revealed(&"lab_vent"), "lab: vent pried open")
	await place(lab.to_global(Vector3(16.0, 2.5, -2.0)))
	await _seconds(0.8)
	check(player.is_on_floor() and player.global_position.y > 2.0, "lab: the duct into the hidden lab is walkable")
	await use_node(lab.find_child("ExperimentLog", true, false))
	check(GameState.has_discovery(&"experiment_log"), "lab: experiment log discovery")
	await _shot("lab_hidden")
	# Real hops up the crates into the vent duct: single crate, then the stack, then the duct.
	await place(lab.to_global(Vector3(11.8, 0.2, -1.08)), -90.0)
	await real_hop(Vector3.RIGHT, 0.6)
	check(player.global_position.y > 0.85, "lab: robot hops onto the first crate (y=%.2f)" % player.global_position.y)
	await real_hop(Vector3.FORWARD, 0.6, 0.45)
	check(player.global_position.y > 1.75, "lab: robot hops onto the crate stack (y=%.2f)" % player.global_position.y)
	await real_hop(Vector3.RIGHT, 0.2)
	check(player.global_position.x > lab.global_position.x + 14.1 and player.global_position.y > 2.1, "lab: robot hops into the vent duct (%s)" % player.global_position)
	# Control room: wrong order trips everything; reverse of the shutdown log works.
	await use_interactable(_find_prompt(lab, "Bring CORE online"))
	check(not GameState.set_has(&"lab_power", &"terminals") and (lab.get("_sequence") as Array).is_empty(), "lab: wrong terminal order trips and resets")
	for t in ["COOLANT", "CONTAINMENT", "FIELD", "CORE"]:
		await use_interactable(_find_prompt(lab, "Bring %s online" % t))
	check(GameState.set_has(&"lab_power", &"terminals"), "lab: terminals restarted in the reverse order")
	check(GameState.set_count(&"lab_power") == 3, "lab: all three power steps done")
	check(Quests.current_id == &"enter_reactor", "objective moves on to the reactor (%s)" % Quests.current_id)
	await _wait_cinematic()
	await _shot("lab_control")
	await use_node(lab.find_child("Blueprint", true, false))
	check(GameState.has_discovery(&"helper_blueprint"), "lab: blueprint discovery")
	for i in 4:
		await collect(StringName("lab_%d" % (i + 1)))
	await use_interactable(_find_prompt(lab, "Ride the freight lift down"))
	await _wait_until(func() -> bool: return GameState.current_area == &"reactor", 10.0)
	await _seconds(1.5)
	check(GameState.current_area == &"reactor", "freight lift reaches the reactor")
	check(GameState.checkpoint_id == &"reactor_entry", "reactor entry checkpoint set")


# --- Area 6 -------------------------------------------------------------------------------

func reactor_test() -> void:
	var rx := facility.areas[1]
	await _shot("reactor_entry")
	# Plasma vent: standing in it while it fires knocks the robot back.
	var vents: Array = rx.get("_vents")
	var vent: ScifiParts.Hazard = vents[0]
	await _wait_until(func() -> bool: return not vent.is_active() and fmod(vent.get("_t"), vent.period) < 0.2, 6.0)
	await place(vent.global_position + Vector3(0.6, -1.2, 0.2))
	await _wait_until(func() -> bool: return player.has_meta("stunned"), 4.0)
	check(player.has_meta("stunned"), "reactor: plasma vent knocks the robot back")
	await _seconds(1.0)
	await collect(&"reactor_1")
	await collect(&"reactor_4")
	# Arms: a lock outside the window misses; inside the window it holds.
	var arms: Array = rx.get("_arms")
	var arm0: Dictionary = arms[0]
	var it0: Interactable = arm0["interactable"]
	await approach(it0)
	await _wait_until(func() -> bool: return absf(rx.arm_offset(arm0)) > 40.0, 8.0)
	await _press("interact")
	check(not arm0["locked"], "reactor: locking an arm outside its window misses")
	for arm: Dictionary in arms:
		var it: Interactable = arm["interactable"]
		await approach(it)
		await _wait_until(func() -> bool: return rx.arm_in_window(arm), 10.0)
		await _press("interact")
		await _frames(5)
		check(arm["locked"], "reactor: %s locked in its window" % it.prompt)
	check(GameState.set_has(&"reactor_stability", &"arms"), "reactor: arms synchronized")
	await _wait_cinematic()
	await _seconds(0.8)
	# Walk out onto the locked bridge: it carries the robot.
	await place(rx.to_global(Vector3(0, 4.3, -9.0)))
	await _seconds(0.6)
	check(player.is_on_floor() and player.global_position.y > rx.global_position.y + 3.6, "reactor: robot stands on the locked arm bridge")
	await _shot("reactor_arms")
	# Cores: purge, then the 7-transfer solution through the real valves.
	await use_interactable(_find_prompt(rx, "Transfer A → B"))
	check(rx.core_levels() == [3, 5, 0], "reactor: A→B pours until B is full (%s)" % [rx.core_levels()])
	await use_interactable(_find_prompt(rx, "Purge the cores"))
	check(rx.core_levels() == [8, 0, 0], "reactor: purge restores 8/0/0")
	await use_interactable(_find_prompt(rx, "Transfer B → C"))
	check(rx.core_levels() == [8, 0, 0], "reactor: pouring from an empty core changes nothing")
	for t in ["A → B", "B → C", "C → A", "B → C", "A → B", "B → C", "C → A"]:
		await use_interactable(_find_prompt(rx, "Transfer " + t))
		await _seconds(0.3)
	check(rx.core_levels() == [4, 4, 0], "reactor: cores balanced at 4/4/0 (%s)" % [rx.core_levels()])
	check(GameState.set_has(&"reactor_stability", &"cores"), "reactor: core step done")
	await _wait_cinematic()
	await _shot("reactor_cores")
	await use_node(rx.find_child("ReactorHeart", true, false))
	check(GameState.has_discovery(&"reactor_heart"), "reactor: heart discovery")
	await collect(&"reactor_2")
	# Moving lift carries the robot up to the pads.
	var lift: ScifiParts.MovingPlatform = rx.get("_lift")
	await _wait_until(func() -> bool: return lift.position.y < 4.05 and lift.get("_wait") > 1.0, 15.0)
	await place(lift.global_position + Vector3(0, 0.4, 0))
	await _wait_until(func() -> bool: return lift.position.y > 7.9, 12.0)
	await _seconds(0.3)
	check(player.global_position.y > rx.global_position.y + 7.6, "reactor: moving lift carries the robot up (y=%.1f)" % player.global_position.y)
	# Energy bridge: solid while on, gone while off.
	var bridges: Array = rx.get("_bridges")
	var bridge: ScifiParts.EnergyBridge = bridges[0]
	await _wait_until(func() -> bool: return not bridge.solid, 10.0)
	await place(bridge.global_position + Vector3(0, 0.6, 0))
	await _seconds(0.7)
	check(player.global_position.y < bridge.global_position.y - 0.5, "reactor: robot falls through a bridge that is off")
	# Nodes: wrong order overloads, heart rhythm order works.
	var nodes: Array = rx.get("_nodes")
	var by_dots := {}
	for n: Dictionary in nodes:
		by_dots[int(n["dots"])] = n
	await use_interactable(_node_it(by_dots[1]))
	check(not (by_dots[1] as Dictionary)["on"], "reactor: waking the wrong node first overloads")
	for d in rx.RHYTHM:
		await use_interactable(_node_it(by_dots[d]))
	check(GameState.set_has(&"reactor_stability", &"nodes"), "reactor: nodes woken in the heart's rhythm")
	check(Quests.current_id == &"enter_quantum", "objective moves on to the portal (%s)" % Quests.current_id)
	await _wait_cinematic()
	await use_node(rx.find_child("BuilderGlyphs", true, false))
	check(GameState.has_discovery(&"builder_glyphs"), "reactor: glyphs discovery")
	await collect(&"reactor_3")
	# The pit returns the robot to its checkpoint.
	GameState.set_checkpoint(&"reactor_cores")
	await place(rx.to_global(Vector3(25, -3, 0)))
	await _wait_until(func() -> bool: return player.global_position.y > rx.global_position.y + 3.0, 6.0)
	await _seconds(1.2)
	check(player.global_position.distance_to(Checkpoint.find(get_tree(), &"reactor_cores").global_position) < 3.0, "reactor: falling into the pit returns to the checkpoint")
	await _shot("reactor_stable")
	var portal_it: Interactable = rx.get("_portal_it")
	check(portal_it.enabled, "reactor: portal opens when stable")
	await use_interactable(portal_it)
	await _wait_until(func() -> bool: return GameState.current_area == &"quantum", 10.0)
	await _seconds(1.5)
	check(GameState.current_area == &"quantum", "portal reaches the quantum lab")


# --- Area 7 -------------------------------------------------------------------------------

func quantum_test() -> void:
	var q := facility.areas[2]
	await _shot("quantum_entry")
	await use_node(q.find_child("FoldedRoom", true, false))
	check(GameState.has_discovery(&"folded_room"), "quantum: folded room discovery")
	# Gravity: a real hop cannot reach the first floating platform... until the field is on.
	var zone: Dictionary = q.gravity_zone(0)
	await place(q.to_global(Vector3(-4, 0.2, 17.2)), 0.0)
	await real_hop(Vector3.FORWARD, 0.6)
	await _seconds(1.0)
	check(player.global_position.y < q.global_position.y + 1.5, "quantum: normal hop can't reach the floating platform (y=%.2f)" % (player.global_position.y - q.global_position.y))
	await use_interactable(_find_prompt(q, "Engage the low-gravity field"))
	check(zone["on"] and is_equal_approx(player.gravity_scale, q.LOW_GRAVITY), "quantum: field lowers the robot's gravity")
	await place(q.to_global(Vector3(-4, 0.2, 17.2)), 0.0)
	await real_hop(Vector3.FORWARD, 0.9, 1.35)
	await _seconds(2.5)
	check(player.global_position.y > q.global_position.y + 2.2 and player.is_on_floor(), "quantum: low-gravity hop lands on the floating platform (y=%.2f)" % (player.global_position.y - q.global_position.y))
	await _shot("quantum_gravity")
	await collect(&"quantum_1")
	await collect(&"quantum_4")
	await place(q.to_global(Vector3(0, 10.4, -3.0)))
	await _seconds(0.5)
	check(GameState.set_has(&"quantum_systems", &"gravity"), "quantum: reaching the ledge masters gravity")
	await place(q.to_global(Vector3(0, 8.0, 7.0)))
	await _seconds(0.3)
	check(not zone["on"] or is_equal_approx(player.gravity_scale, q.LOW_GRAVITY), "quantum: gravity stays low inside the active field")
	await place(q.to_global(Vector3(0, 0.2, 25.0)))
	await _seconds(0.3)
	check(is_equal_approx(player.gravity_scale, 1.0), "quantum: leaving the field restores gravity")
	# Phase: B platforms are not solid in A, and are after shifting.
	GameState.set_checkpoint(&"quantum_gravity")
	await place(q.to_global(Vector3(0, 10.4, -3.0)))
	check(q.dimension == 0, "quantum: starts in dimension A")
	await place(q.to_global(Vector3(0, 10.5, -9.0)))
	await _seconds(0.6)
	check(player.is_on_floor() and player.global_position.y > q.global_position.y + 9.5, "quantum: dimension A platform is solid in A")
	await place(q.to_global(Vector3(-0.5, 10.6, -21.0)))
	await _seconds(0.6)
	check(player.global_position.y < q.global_position.y + 9.0, "quantum: dimension B platform is not solid in A")
	await _wait_until(func() -> bool: return player.input_enabled and player.global_position.distance_to(Checkpoint.find(get_tree(), &"quantum_gravity").global_position) < 3.0, 8.0)
	check(player.global_position.distance_to(Checkpoint.find(get_tree(), &"quantum_gravity").global_position) < 3.0, "quantum: falling into the void returns to the checkpoint")
	await use_interactable(_find_prompt(q, "Shift dimension"))
	check(q.dimension == 1, "quantum: console shifts to dimension B")
	await _seconds(0.2)
	await place(q.to_global(Vector3(-0.5, 10.6, -21.0)))
	await _seconds(0.6)
	check(player.is_on_floor() and player.global_position.y > q.global_position.y + 9.5, "quantum: dimension B platform is solid in B")
	await collect(&"quantum_2")
	await _shot("quantum_phase")
	await place(q.to_global(Vector3(4.0, 10.4, -41.0)))
	await _seconds(0.5)
	check(GameState.set_has(&"quantum_systems", &"phase"), "quantum: reaching the far platform masters phase")
	await use_node(q.find_child("TimeEcho", true, false))
	check(GameState.has_discovery(&"time_echo"), "quantum: time echo discovery")
	# Time: blades throw the robot back while running, not while time is frozen.
	GameState.set_checkpoint(&"quantum_phase")
	var blades: Array = q.get("_blades")
	var blade: Dictionary = blades[0]
	var blade_pos := q.to_global(blade["pos"] as Vector3)
	await place(blade_pos + Vector3(1.4, 0.4, 0.6))
	await _seconds(1.5)
	check(player.global_position.distance_to(Checkpoint.find(get_tree(), &"quantum_phase").global_position) < 3.0, "quantum: spinning blade sends the robot back")
	await _seconds(0.8)
	var rotor: Node3D = blade["rotor"]
	await use_interactable(_find_prompt(q, "Freeze time"))
	check(q.frozen, "quantum: console freezes time")
	var angle := rotor.rotation.y
	await place(blade_pos + Vector3(1.4, 0.4, 0.6))
	await _seconds(0.8)
	check(is_equal_approx(rotor.rotation.y, angle), "quantum: blades stand still while frozen")
	check(player.global_position.distance_to(blade_pos) < 3.0, "quantum: frozen blades don't hurt the robot")
	await collect(&"quantum_3")
	await place(q.to_global(Vector3(29.0, 10.4, -41.25)))
	await _seconds(0.5)
	check(GameState.set_has(&"quantum_systems", &"time"), "quantum: reaching the corridor end masters time")
	await _shot("quantum_time")
	await _wait_until(func() -> bool: return not q.frozen, 8.0)
	check(not q.frozen, "quantum: time resumes on its own")
	# Final: core needs all three; gravity, phase B and a freeze reach it.
	var core_it: Interactable = q.get("_core_it")
	check(not core_it.locked, "quantum: exit core unlocked with all three systems")
	var final_zone: Dictionary = q.gravity_zone(1)
	await use_interactable(_find_prompt(q, "Engage the low-gravity field", Vector3(34, 10, -38)))
	check(final_zone["on"], "quantum: final gravity field engaged")
	await place(q.to_global(Vector3(34, 13.6, -48.0)))
	await _seconds(0.4)
	if q.dimension != 1:
		await use_interactable(_find_prompt(q, "Shift dimension", Vector3(32.6, 13.2, -47.4)))
	check(q.dimension == 1, "quantum: final bridge dimension active")
	await use_interactable(_find_prompt(q, "Freeze time", Vector3(35.4, 13.2, -47.4)))
	await place(q.to_global(Vector3(34, 13.6, -52.0)))
	# Low gravity: the robot settles slowly, so wait for the landing rather than a fixed time.
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	await _seconds(0.3)
	check(player.is_on_floor() and player.global_position.y > q.global_position.y + 12.8, "quantum: dimension B bridge holds the robot")
	await use_interactable(core_it)
	check(GameState.has_flag(&"quantum_complete"), "quantum: exit core opens the way home")
	check(Quests.current_id == &"explore", "all objectives done (%s)" % Quests.current_id)
	var completion: CompletionScreen = q.get("_completion")
	await _wait_until(func() -> bool: return completion.visible, 12.0)
	check(completion.visible, "quantum: completion screen shown")
	await _shot("quantum_complete")
	completion._on_keep()
	await _seconds(0.5)
	check(GameState.energy() == GameData.total_fragments(), "all 42 fragments collected (%d)" % GameState.energy())
	check(GameState.discoveries.size() == 6, "all 6 facility discoveries found (%d)" % GameState.discoveries.size())


# --- Save / continue, travel, and home -------------------------------------------------------

func continue_test() -> void:
	SaveSystem.save_game()
	var summary := SaveSystem.read_summary()
	check(summary.get("area") == &"quantum", "save summary names the quantum lab")
	GameState.reset()
	check(SaveSystem.load_game(), "facility save loads")
	SceneRouter.start_mode = SceneRouter.StartMode.CONTINUE
	SceneRouter.continue_game()
	await _wait_until(func() -> bool: return get_tree().current_scene is FacilityWorld and get_tree().current_scene != facility, 30.0)
	await _attach()
	check(GameState.current_area == &"quantum", "continue resumes in the quantum lab (%s)" % GameState.current_area)
	var lab := facility.areas[0]
	var rx := facility.areas[1]
	check((lab.get("_door_c") as ScifiParts.Door).is_open, "continue: lab doors restored open")
	check(rx.core_levels() == [4, 4, 0], "continue: reactor cores restored (%s)" % [rx.core_levels()])
	check(((rx.get("_portal_it") as Interactable).enabled), "continue: reactor portal restored")
	check((facility.areas[2].get("_exit_it") as Interactable).enabled, "continue: exit portal restored")


func travel_test() -> void:
	facility.pause_menu.open()
	await _frames(5)
	var travel: TravelPanel = facility.pause_menu.get("_travel")
	facility.pause_menu.call("_show_travel")
	await _frames(5)
	var buttons := travel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text.contains("."))
	check(buttons.size() == 7, "travel lists all seven areas (%d)" % buttons.size())
	check(buttons.all(func(b: Node) -> bool: return not (b as Button).disabled), "every area is unlocked for travel")
	await _shot("travel")
	facility.pause_menu.close()
	# Take the exit portal home.
	var exit_it: Interactable = facility.areas[2].get("_exit_it")
	await use_interactable(exit_it)
	await _wait_until(func() -> bool: return get_tree().current_scene is World, 30.0)
	check(get_tree().current_scene is World, "exit portal returns to the garden")
	await _seconds(2.0)
	var world := get_tree().current_scene as World
	world.pause_on_focus_loss = false
	var heart := Checkpoint.find(get_tree(), &"heart")
	check(heart != null and world.player.global_position.distance_to(heart.global_position) < 3.5, "arrived at the Crystal Heart")
	check(GameState.location == &"world" and GameState.current_area == &"garden", "back in the garden world")
	await _shot("home")


# --- Helpers ------------------------------------------------------------------------------

func check(cond: bool, label: String) -> void:
	if cond:
		print("FACILITY ok   ", label)
	else:
		print("FACILITY FAIL ", label)
		failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _wait_cinematic() -> void:
	await _frames(2)
	await _wait_until(func() -> bool: return facility.phase == FacilityWorld.Phase.PLAYING and player.input_enabled, 12.0)


func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _shot(label: String) -> void:
	if not take_shots:
		return
	await RenderingServer.frame_post_draw
	shot_index += 1
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS + "facility_%02d_%s.png" % [shot_index, label]))


func place(pos: Vector3, yaw_deg: float = NAN) -> void:
	player.respawn_at(pos, deg_to_rad(yaw_deg) if not is_nan(yaw_deg) else NAN)
	facility.camera_rig.yaw = player.facing_yaw()
	facility.camera_rig.snap_to_target()
	await _frames(6)


## Real input: move in a direction (relative to the camera, which faces the robot's yaw) and
## hold hop for a while.
func real_hop(dir: Vector3, hold: float, move_time := 1.05) -> void:
	player.face_toward(player.global_position + dir)
	facility.camera_rig.yaw = player.facing_yaw()
	await _seconds(0.3)
	Input.action_press("move_forward")
	await _seconds(0.15)
	var down := InputEventAction.new()
	down.action = "hop"
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = "hop"
	up.pressed = false
	if move_time < 0.15 + hold:
		await _seconds(maxf(move_time - 0.15, 0.0))
		Input.action_release("move_forward")
		await _seconds(0.15 + hold - move_time)
		Input.parse_input_event(up)
	else:
		await _seconds(hold)
		Input.parse_input_event(up)
		await _seconds(move_time - 0.15 - hold)
		Input.action_release("move_forward")
	await _seconds(0.8)


func _floor_below(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 4.0, 1)
	var hit := facility.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF


func approach(it: Interactable) -> void:
	var focus := it.get_focus_point()
	for attempt in 12:
		var a := TAU * attempt / 12.0
		var r := minf(1.1 + it.radius * 0.25, 1.8)
		var p := focus + Vector3(cos(a), 0, sin(a)) * r
		p.y = _floor_below(Vector3(p.x, focus.y + 0.6, p.z)) + 0.3
		if p.y < focus.y - 3.0:
			continue
		player.respawn_at(p)
		player.face_toward(focus)
		await _frames(6)
		if player.interactor.current == it:
			return


func use_interactable(it: Interactable) -> void:
	if it == null:
		check(false, "interactable exists")
		return
	await approach(it)
	if player.interactor.current != it:
		check(false, "could focus %s (current=%s)" % [it.prompt, player.interactor.current.prompt if player.interactor.current else "none"])
		it.interact(player)
		await _frames(5)
		return
	if it.locked:
		check(false, "%s unexpectedly locked: %s" % [it.prompt, it.get_prompt()])
		return
	await _press("interact")
	await _frames(8)


func use_node(node: Node) -> void:
	if node == null:
		check(false, "node exists")
		return
	await use_interactable(node.find_children("*", "Interactable", true, false)[0] as Interactable)


func collect(id: StringName) -> void:
	if GameState.has_fragment(id):
		return
	for n in get_tree().get_nodes_in_group(&"fragments"):
		var f := n as EnergyFragment
		if f and f.fragment_id == id:
			player.respawn_at(f.global_position - Vector3(0, 0.6, 0))
			await _frames(12)
			check(GameState.has_fragment(id), "collected %s" % id)
			return
	check(false, "fragment %s exists" % id)


## Finds an interactable in an area by its prompt (optionally the one nearest a local point).
func _find_prompt(area: Node3D, prompt: String, near_local := Vector3.INF) -> Interactable:
	var best: Interactable = null
	var best_d := INF
	for n in area.find_children("*", "Interactable", true, false):
		var it := n as Interactable
		if not it.prompt.begins_with(prompt) or not it.enabled:
			continue
		var d := 0.0 if near_local == Vector3.INF else it.global_position.distance_to(area.to_global(near_local))
		if d < best_d:
			best_d = d
			best = it
	if best == null:
		check(false, "found interactable '%s'" % prompt)
	return best


func _node_it(entry: Dictionary) -> Interactable:
	return entry["interactable"]
