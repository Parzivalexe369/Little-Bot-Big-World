extends Node
## Automated end-to-end playtest. Boots the real main menu, starts a new game and plays
## to the ending using the actual interaction code (Interactor focus + interact input),
## asserting progression along the way. Screenshots go to docs/captures/playtest_*.png.
## Usage (windowed): godot --path . res://tools/playtest_runner.tscn [-- quick]

const SHOTS := "res://docs/captures/"

var world: World
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
	SaveSystem.delete_save()
	# Keep this runner alive across scene changes: the menu becomes the current scene.
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames(90)
	await _shot("menu")
	SceneRouter.start_new_game()
	await _wait_until(func() -> bool: return get_tree().current_scene is World, 30.0)
	world = get_tree().current_scene as World
	world.pause_on_focus_loss = false
	player = world.player
	await _frames(60)
	check(world.phase == World.Phase.INTRO, "starts in intro")
	check(player.visual.is_sleeping(), "robot starts asleep")
	await _shot("intro_asleep")
	await _press("interact")
	await _wait_until(func() -> bool: return world.phase == World.Phase.PLAYING, 15.0)
	check(GameState.has_flag(&"robot_awake"), "robot woke up")
	await _shot("awake")

	# Walk forward with real input for a moment.
	Input.action_press("move_forward")
	await _seconds(1.5)
	Input.action_release("move_forward")
	check(player.global_position.z < 57.0, "walking moves the robot (z=%.1f)" % player.global_position.z)
	await _shot("walking")

	# Read the dock plaque (discovery).
	await use_node(_find_named("DockPlaque"))
	check(GameState.has_discovery(&"dock_plaque"), "dock plaque discovery")

	# Scan reveals the hidden meadow fragment.
	var hidden := _find_fragment(&"meadow_5")
	await teleport_near(hidden.global_position, 4.0)
	check(player.try_scan(), "scan fires")
	await _seconds(1.6)
	check(GameState.is_revealed(&"meadow_5"), "scan revealed hidden fragment")
	await _shot("scan_reveal")

	# Collect meadow fragments.
	for id in [&"meadow_1", &"meadow_2", &"meadow_3", &"meadow_5", &"meadow_6", &"meadow_7"]:
		await collect(id)
	check(GameState.energy() >= 3, "collected enough meadow energy (%d)" % GameState.energy())
	# The secret inside the giant watering can.
	await use_node(_find_named("WateringCanStory"))
	check(GameState.has_discovery(&"watering_can"), "watering can discovery")
	# Fragment on the boulder: hop onto the first stepping stone with real input, then the top.
	await real_hop_test()
	await hop_test()

	# Power the gate.
	var gate := _find_type(RootGate) as RootGate
	await use_interactable(gate.interactable)
	await _wait_until(func() -> bool: return GameState.has_flag(&"meadow_gate_open"), 8.0)
	await _seconds(2.5)
	await _shot("gate_open")
	await _wait_until(func() -> bool: return world.restore_levels.x > 0.99, 12.0)
	check(world.restore_levels.x > 0.99, "meadow restored")
	await teleport_near(Vector3(-2.0, 0, -50.0), 0.0, -2.0)
	await _shot("meadow_restored")

	# Walk through the gate into the forest.
	await teleport_near(Vector3(-8, 0, -68), 0.0)
	await _seconds(1.2)
	check(GameState.has_flag(&"visited_forest"), "entered forest")
	await _shot("forest_entry")

	# Forest fragments and the hidden switches.
	for id in [&"forest_1", &"forest_3", &"forest_4", &"forest_6", &"forest_7", &"forest_8"]:
		await collect(id)
	var caretaker := _find_named("SleepingCaretaker")
	await use_node(caretaker)
	check(GameState.has_discovery(&"sleeping_caretaker"), "caretaker discovery")
	await teleport_near(Vector3(-2, 0, -188), 0.0)
	await _seconds(0.5)
	check(GameState.has_flag(&"saw_bridge"), "saw bridge trigger")
	for sw in _find_all(ValveSwitch):
		var v := sw as ValveSwitch
		await teleport_near(v.global_position, 4.0)
		player.try_scan()
		await _seconds(1.5)
		await use_interactable(v.interactable)
		await _seconds(1.6)
	check(GameState.set_count(&"forest_switches") == 3, "all three switches on (%d)" % GameState.set_count(&"forest_switches"))
	await _shot("switch_on")
	var bridge := _find_type(OldBridge) as OldBridge
	await use_interactable(bridge.interactable)
	await _wait_until(func() -> bool: return GameState.has_flag(&"bridge_raised"), 6.0)
	await _seconds(6.0)
	await _shot("bridge_raised")
	check(GameState.has_flag(&"bridge_raised"), "bridge raised")
	# Cross the bridge with real movement.
	await teleport_near(Vector3(1.2, 0, -195.5), 0.0, 0.0)
	player.face_toward(Vector3(3.6, 0, -213))
	world.camera_rig.yaw = player.facing_yaw()
	Input.action_press("move_forward")
	await _seconds(4.0)
	Input.action_release("move_forward")
	check(player.global_position.z < -208.0, "crossed the bridge on foot (z=%.1f)" % player.global_position.z)
	await _shot("crossed_bridge")

	# Shrine.
	await teleport_near(Vector3(27, 0, -255), 0.0)
	await _seconds(0.6)
	check(GameState.has_flag(&"shrine_plaza_reached"), "reached shrine plaza")
	for id in [&"shrine_1", &"shrine_2", &"shrine_5", &"shrine_6"]:
		await collect(id)
	# Hidden fragment needs the scanner.
	var hidden_s := _find_fragment(&"shrine_7")
	await teleport_near(hidden_s.global_position, 4.0)
	player.try_scan()
	await _seconds(1.2)
	await collect(&"shrine_7")
	await _shot("shrine_plaza")
	check(GameState.energy() >= GameData.SHRINE_NODE_ENERGY, "enough energy for the node (%d)" % GameState.energy())
	var nodes := {}
	for n in _find_all(PowerNode):
		nodes[(n as PowerNode).device_id] = n
	await use_interactable((nodes[&"node_energy"] as PowerNode).interactable)
	await _seconds(1.0)
	check((nodes[&"node_energy"] as PowerNode).is_on(), "energy node on")
	# Beam puzzle: turn mirrors to the solved angles (A step 3, B step 7).
	await solve_mirror(_find_named("MirrorA") as BeamMirror, 3)
	await solve_mirror(_find_named("MirrorB") as BeamMirror, 7)
	await _wait_until(func() -> bool: return (nodes[&"node_beam"] as PowerNode).is_on(), 6.0)
	check((nodes[&"node_beam"] as PowerNode).is_on(), "beam node on")
	await _shot("beam_puzzle")
	# Hidden chamber.
	var wall := _find_type(HiddenWall) as HiddenWall
	await teleport_near(wall.global_position + wall.global_basis.z * 3.0, 0.0)
	player.try_scan()
	await _seconds(1.0)
	await use_interactable(wall.interactable)
	await _seconds(3.2)
	check(GameState.has_flag(&"hidden_wall_open"), "hidden wall opened")
	await collect(&"shrine_3")
	await use_interactable((nodes[&"node_hidden"] as PowerNode).interactable)
	await _seconds(1.0)
	check((nodes[&"node_hidden"] as PowerNode).is_on(), "hidden node on")
	await _shot("hidden_chamber")
	# Conduit tiles: A x1, B x2, C x3.
	var junction := _find_type(JunctionPuzzle) as JunctionPuzzle
	for pair in [["A", 1], ["B", 2], ["C", 1]]:
		var tile: Dictionary = junction._tiles[pair[0]]
		for k in int(pair[1]):
			await use_interactable(tile["interactable"] as Interactable)
			await _seconds(0.5)
	await _seconds(0.6)
	check((nodes[&"node_conduit"] as PowerNode).is_on(), "conduit node on")
	await _shot("conduit_puzzle")
	check(GameState.set_count(&"shrine_nodes") == 4, "all four shrine nodes (%d)" % GameState.set_count(&"shrine_nodes"))
	var core := _find_type(ShrineCore) as ShrineCore
	await use_interactable(core.interactable)
	await _seconds(5.0)
	await _shot("core_awakening")
	await _wait_until(func() -> bool: return world.phase == World.Phase.PLAYING and not world.director.busy, 40.0)
	check(GameState.has_flag(&"shrine_restored"), "shrine restored")
	await use_node(_find_named("Mural"))
	await use_node(_find_named("Courier"))
	await collect(&"shrine_4")

	# Garden.
	await teleport_near(Vector3(19, 0, -316), 0.0, 180.0)
	await _seconds(1.0)
	check(GameState.has_flag(&"visited_garden"), "entered garden")
	await _shot("garden_entry")
	for id in [&"garden_1", &"garden_2", &"garden_3", &"garden_5", &"garden_8"]:
		await collect(id)
	await solve_mirror(_find_named("PrismA") as BeamMirror, 7)
	await solve_mirror(_find_named("PrismB") as BeamMirror, 5)
	await _seconds(2.0)
	check(GameState.set_has(&"resonators", &"resonator_beam"), "beam resonator on")
	await _shot("prism_puzzle")
	var hidden_res := _find_named("ResonatorHidden") as Resonator
	await teleport_near(hidden_res.global_position, 5.0)
	player.try_scan()
	await _seconds(3.0)
	await use_interactable(hidden_res.interactable)
	await _seconds(1.0)
	check(GameState.set_has(&"resonators", &"resonator_hidden"), "hidden resonator on")
	check(GameState.has_discovery(&"crystal_echo"), "humming cave discovery")
	var melody := _find_type(MelodyPuzzle) as MelodyPuzzle
	await use_interactable(melody.interactable)
	await _seconds(5.0)
	for i in MelodyPuzzle.SEQUENCE:
		var root := melody.get_node("Crystal%d" % i) as Node3D
		var it := root.find_children("*", "Interactable", false, false)[0] as Interactable
		await use_interactable(it)
		await _seconds(0.7)
	await _seconds(2.0)
	check(GameState.set_has(&"resonators", &"resonator_melody"), "melody resonator on")
	await _shot("melody_puzzle")
	print("PLAYTEST energy before heart: ", GameState.energy())
	check(GameState.energy() >= GameData.HEART_ENERGY, "enough energy for the heart (%d)" % GameState.energy())

	# Save/load round trip before the finale.
	var before := GameState.to_dict()
	check(SaveSystem.save_game(), "save game")
	GameState.reset()
	check(SaveSystem.load_game(), "load game")
	check(GameState.energy() == (before["fragments"] as Array).size(), "energy survives save/load")
	check(GameState.set_count(&"shrine_nodes") == 4, "shrine nodes survive save/load")

	var heart := _find_type(CrystalHeart) as CrystalHeart
	await use_interactable(heart.interactable)
	await _seconds(4.0)
	await _shot("finale_heart")
	await _seconds(8.0)
	await _shot("finale_aerial")
	await _wait_until(func() -> bool: return world.completion.visible, 40.0)
	check(world.completion.visible, "completion screen shown")
	check(GameState.has_flag(&"garden_restored"), "garden restored")
	check(world.world_awake > 0.99, "world awake")
	var garden_discoveries := GameData.DISCOVERIES.filter(func(d: Dictionary) -> bool: return GameData.AREA_IDS.has(d["area"])).size()
	check(GameState.discoveries.size() == garden_discoveries, "all garden discoveries found (%d/%d)" % [GameState.discoveries.size(), garden_discoveries])
	await _seconds(1.6)
	await _shot("completion")
	world.completion._on_keep()
	await _wait_until(func() -> bool: return world.phase == World.Phase.PLAYING, 10.0)
	check(world.phase == World.Phase.PLAYING, "keep exploring returns to play")
	check(Quests.current_id == &"enter_lab", "objective points to the new lift (%s)" % Quests.current_id)
	await teleport_near(Vector3(0, 0, 30), 0.0, 0.0)
	await _seconds(2.0)
	await _shot("meadow_awake")

	# After the finale a lift rises beside the Crystal Heart; riding it opens the facility.
	var lift := _find_named("ResearchLift") as Node3D
	check(lift != null, "research lift exists in the garden")
	if lift:
		await _wait_until(func() -> bool: return lift.visible, 30.0)
		check(lift.visible, "research lift rose after the finale")
		await _seconds(4.5)
		await use_node(lift)
		await _wait_until(func() -> bool: return get_tree().current_scene is FacilityWorld, 30.0)
		check(get_tree().current_scene is FacilityWorld, "riding the lift loads the facility")
		await _frames(30)
		check(GameState.location == &"facility" and GameState.current_area == &"lab", "arrived in the research facility (%s)" % GameState.current_area)

	print("PLAYTEST RESULT: %d failures" % failures.size())
	for f in failures:
		print("PLAYTEST FAIL: ", f)
	print("PLAYTEST energy=%d discoveries=%d objective=%s" % [GameState.energy(), GameState.discoveries.size(), Quests.current_id])
	get_tree().quit(1 if failures.size() > 0 else 0)


# --- Helpers --------------------------------------------------------------------------

func check(cond: bool, label: String) -> void:
	if cond:
		print("PLAYTEST ok   ", label)
	else:
		print("PLAYTEST FAIL ", label)
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


func _press(action: String) -> void:
	# Real input events go through the normal pipeline, so "just pressed" checks see them.
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
	img.save_png(ProjectSettings.globalize_path(SHOTS + "playtest_%02d_%s.png" % [shot_index, label]))


func teleport_near(target: Vector3, distance: float, yaw_deg: float = NAN) -> void:
	var dir := Vector3(player.global_position.x - target.x, 0, player.global_position.z - target.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	var p := target + dir * distance
	var pos := WorldTerrain.point_on_ground(p.x, p.z, 0.4)
	player.respawn_at(pos, deg_to_rad(yaw_deg) if not is_nan(yaw_deg) else NAN)
	if distance > 0.0:
		player.face_toward(target)
	world.camera_rig.yaw = player.facing_yaw()
	world.camera_rig.snap_to_target()
	await _frames(8)


func use_node(node: Node) -> void:
	if node == null:
		check(false, "node exists for use_node")
		return
	var it: Interactable = null
	for child in node.find_children("*", "Interactable", true, false):
		it = child
		break
	await use_interactable(it)


func use_interactable(it: Interactable) -> void:
	if it == null:
		check(false, "interactable exists")
		return
	var focus := it.get_focus_point()
	# Try a few approach angles until the Interactor focuses this target.
	for attempt in 8:
		var a := TAU * attempt / 8.0
		var p := focus + Vector3(cos(a), 0, sin(a)) * minf(1.4 + it.radius * 0.3, 2.2)
		var pos := WorldTerrain.point_on_ground(p.x, p.z, 0.3)
		pos.y = maxf(pos.y, focus.y - 1.5)
		player.respawn_at(pos)
		player.face_toward(focus)
		await _frames(6)
		if player.interactor.current == it:
			break
	if player.interactor.current != it:
		var names := []
		for ar in player.interactor.get_overlapping_areas():
			names.append(ar.get_parent().name)
		print("PLAYTEST debug focus: player=%s focus=%s available=%s locked=%s overlaps=%s on_floor=%s" % [player.global_position, focus, it.is_available(), it.locked, names, player.is_on_floor()])
		check(false, "could focus interactable %s (current=%s)" % [it.get_parent().name, player.interactor.current.get_parent().name if player.interactor.current else "none"])
		it.interact(player)
		return
	if it.locked:
		check(false, "interactable %s unexpectedly locked: %s" % [it.get_parent().name, it.get_prompt()])
		return
	await _press("interact")
	await _frames(10)


func collect(id: StringName) -> void:
	if GameState.has_fragment(id):
		return
	var f := _find_fragment(id)
	if f == null:
		check(false, "fragment %s exists" % id)
		return
	player.respawn_at(f.global_position - Vector3(0, 0.6, 0))
	await _frames(12)
	check(GameState.has_fragment(id), "collected %s" % id)


func hop_test() -> void:
	var f := _find_fragment(&"meadow_4")
	if f == null:
		return
	# Land on the high boulder from just above it, then check we can stand there.
	var top := f.global_position - Vector3(0, 0.9, 0)
	player.respawn_at(top + Vector3(0, 0.5, 0))
	await _seconds(0.8)
	check(GameState.has_fragment(&"meadow_4"), "collected the boulder-top fragment")
	check(player.is_on_floor(), "robot can stand on the boulder")


func real_hop_test() -> void:
	var stone := Vector2(23.2, 4.6)
	var start := Vector2(20.0, 4.6)
	player.respawn_at(WorldTerrain.point_on_ground(start.x, start.y, 0.3))
	player.face_toward(Vector3(stone.x, 0, stone.y))
	world.camera_rig.yaw = player.facing_yaw()
	await _seconds(0.5)
	var ground := WorldTerrain.height_at_world(stone.x, stone.y)
	Input.action_press("move_forward")
	await _seconds(0.25)
	var down := InputEventAction.new()
	down.action = "hop"
	down.pressed = true
	Input.parse_input_event(down)
	await _seconds(0.45)
	var up := InputEventAction.new()
	up.action = "hop"
	up.pressed = false
	Input.parse_input_event(up)
	await _seconds(0.35)
	Input.action_release("move_forward")
	await _seconds(0.8)
	check(player.global_position.y > ground + 0.6, "real hop lands on the stepping stone (y above ground: %.2f)" % (player.global_position.y - ground))


func solve_mirror(mirror: BeamMirror, target_step: int) -> void:
	if mirror == null:
		check(false, "mirror exists")
		return
	var guard := 0
	while int(GameState.get_puzzle_state(mirror.device_id, mirror.start_step)) != target_step and guard < 9:
		await use_interactable(mirror.interactable)
		await _seconds(0.5)
		guard += 1
	check(int(GameState.get_puzzle_state(mirror.device_id, -1)) == target_step, "mirror %s at step %d" % [mirror.name, target_step])


func _find_fragment(id: StringName) -> EnergyFragment:
	for n in get_tree().get_nodes_in_group(&"fragments"):
		if (n as EnergyFragment).fragment_id == id:
			return n
	return null


func _find_named(node_name: String) -> Node:
	return world.find_child(node_name, true, false)


func _find_type(type: Variant) -> Node:
	var all := _find_all(type)
	return all[0] if not all.is_empty() else null


func _find_all(type: Variant) -> Array:
	var out := []
	for n in world.find_children("*", "", true, false):
		if is_instance_of(n, type):
			out.append(n)
	return out
