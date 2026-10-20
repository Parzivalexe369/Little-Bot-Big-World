extends Node
## Dev tool: measures frame time of the world scene, optionally with subtrees removed.
## Usage (windowed): godot --path . res://tools/perf_runner.tscn -- [remove=Node,Node] [x z yaw] [profile]
## "profile" also measures with each environment effect switched off in turn;
## "quality=0|1|2" overrides the graphics preset for this run (not saved);
## "move" boosts the robot in a wide circle during the measurement.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_window().size = Vector2i(1600, 900)
	var args := OS.get_cmdline_user_args()
	var remove: PackedStringArray = []
	var after_remove: PackedStringArray = []
	var hide: PackedStringArray = []
	var coords: Array[float] = [3.0, 30.0, 20.0]
	var ci := 0
	var profile := false
	var moving := false
	var scene_path := "res://scenes/world/world.tscn"
	var at3 := Vector3.INF
	for a in args:
		if a == "profile":
			profile = true
		elif a.begins_with("scene="):
			scene_path = a.substr(6)
		elif a.begins_with("at="):
			var c := a.substr(3).split(",")
			at3 = Vector3(float(c[0]), float(c[1]), float(c[2]))
		elif a == "move":
			moving = true
		elif a.begins_with("quality="):
			Settings.quality = int(a.substr(8))
		elif a.begins_with("remove="):
			remove = a.substr(7).split(",")
		elif a.begins_with("after=") :
			after_remove = a.substr(6).split(",")
		elif a.begins_with("hide="):
			hide = a.substr(5).split(",")
		elif ci < 3:
			coords[ci] = float(a)
			ci += 1
	var world: Node = (load(scene_path) as PackedScene).instantiate()
	for path in remove:
		var n := world.get_node_or_null(path)
		if n:
			n.get_parent().remove_child(n)
			n.free()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var player := world.get_node("Player") as Player
	var rig := world.get_node("CameraRig") as CameraRig
	await get_tree().process_frame
	if at3 != Vector3.INF:
		player.respawn_at(at3, deg_to_rad(coords[2]))
		player.visual.wake_instantly()
	else:
		player.respawn_at(WorldTerrain.point_on_ground(coords[0], coords[1], 0.3), deg_to_rad(coords[2]))
	rig.yaw = deg_to_rad(coords[2])
	rig.snap_to_target()
	for i in 60:
		await get_tree().process_frame
	for path in after_remove:
		var n2 := world.get_node_or_null(path)
		if n2:
			n2.queue_free()
	for path in hide:
		var n3 := world.get_node_or_null(path) as Node3D
		if n3:
			n3.visible = false
	for i in 140:
		await get_tree().process_frame
	if moving:
		# Boost in a slow circle so streaming effects (dust, trail, probe updates) are included.
		player.input_enabled = true
		player.visual.wake_instantly()
		Input.action_press("move_forward")
		Input.action_press("move_left", 0.35)
		Input.action_press("boost")
	await _measure("removed=%s after=%s hide=%s%s" % [",".join(remove), ",".join(after_remove), ",".join(hide), " moving" if moving else ""])
	if profile:
		var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
		for prop in ["ssil_enabled", "volumetric_fog_enabled", "ssao_enabled", "glow_enabled", "ssr_enabled", "fog_enabled"]:
			var was: bool = env.get(prop)
			if not was:
				continue
			env.set(prop, false)
			await _measure("without " + prop)
			env.set(prop, true)
		var sun := world.get_node("Sun") as DirectionalLight3D
		sun.shadow_enabled = false
		await _measure("without sun shadows")
		sun.shadow_enabled = true
	get_tree().quit()


func _measure(label: String) -> void:
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	for i in 30:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - t0 < 2500000:
		await get_tree().process_frame
		frames += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	var setup := RenderingServer.get_frame_setup_time_cpu()
	print("RENDER gpu=%.2fms cpu=%.2fms setup=%.2fms" % [gpu, cpu, setup])
	print("PERF %-40s %6.2f ms (%5.1f fps) draws=%d objects=%d prims=%d process=%.1fms nodes=%d" % [label, ms, 1000.0 / ms, draws, objs, prims, proc, nodes])
