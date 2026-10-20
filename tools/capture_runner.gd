extends Node
## Dev tool: loads the game world and saves screenshots from scripted viewpoints.
## Usage (windowed): godot --path . res://tools/capture_runner.tscn -- <shots.json> [scene]
## Each shot: {"name": str, "player": [x, z], "yaw": deg, "cam_yaw": deg, "cam_pitch": deg,
##             "distance": m, "wait": frames, "free_cam": [x, y, z], "look": [x, y, z],
##             "flags": {...}, "fragments": n, "press": "action", "hold": frames, "call": "method"}

const OUT_DIR := "res://docs/captures/"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var shots: Array = []
	if not args.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
		if parsed is Array:
			shots = parsed
	if shots.is_empty():
		shots = [{"name": "default", "player": [0, 50], "yaw": 0, "wait": 30}]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(1600, 900)
	var world_path := "res://scenes/world/world.tscn" if args.size() < 2 else args[1]
	var world: Node = (load(world_path) as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for i in 20:
		await get_tree().process_frame
	for shot: Dictionary in shots:
		await _take(world, shot)
	print("capture done")
	get_tree().quit()


func _take(world: Node, shot: Dictionary) -> void:
	var player := world.get_node_or_null("Player") as Player
	var rig := world.get_node_or_null("CameraRig") as CameraRig
	if shot.has("flags"):
		for key: String in shot["flags"]:
			GameState.set_flag(StringName(key), shot["flags"][key])
	if shot.has("fragments"):
		for n in int(shot["fragments"]):
			GameState.collect_fragment(StringName("debug_%d" % n))
	if shot.has("restore") and world is World:
		var r: Array = shot["restore"]
		(world as World).restore_levels = Vector4(r[0], r[1], r[2], r[3])
		(world as World).world_awake = float(shot.get("awake", 0.0))
	if world is World:
		(world as World).pause_on_focus_loss = false
		(world as World).hud.visible = bool(shot.get("hud", false))
	elif world is FacilityWorld:
		(world as FacilityWorld).pause_on_focus_loss = false
		(world as FacilityWorld).hud.visible = bool(shot.get("hud", false))
	if shot.has("window"):
		var ws: Array = shot["window"]
		get_window().size = Vector2i(int(ws[0]), int(ws[1]))
	if player and bool(shot.get("input", false)):
		player.input_enabled = true
		player.visual.wake_instantly()
		if world is World:
			(world as World).hud.forced_prompt = ""
			(world as World).hud.set_hud_visible(true, 0.0)
	if shot.has("call") and world.has_method(shot["call"]):
		await world.call(shot["call"])
	if player and shot.has("at"):
		var at: Array = shot["at"]
		player.respawn_at(Vector3(at[0], at[1], at[2]), deg_to_rad(float(shot.get("yaw", 0.0))))
	if player and shot.has("player"):
		var p: Array = shot["player"]
		var yaw := deg_to_rad(float(shot.get("yaw", 0.0)))
		player.respawn_at(WorldTerrain.point_on_ground(p[0], p[1], 0.3), yaw)
	if rig:
		rig.yaw = deg_to_rad(float(shot.get("cam_yaw", shot.get("yaw", 0.0))))
		rig.pitch = deg_to_rad(float(shot.get("cam_pitch", -14.0)))
		rig.desired_distance = float(shot.get("distance", 3.6))
		rig.snap_to_target()
	var cam: Camera3D = null
	if shot.has("free_cam"):
		cam = Camera3D.new()
		world.add_child(cam)
		var c: Array = shot["free_cam"]
		var l: Array = shot.get("look", [0, 0, 0])
		cam.fov = float(shot.get("fov", 60.0))
		cam.far = 2000.0
		cam.look_at_from_position(Vector3(c[0], c[1], c[2]), Vector3(l[0], l[1], l[2]))
		cam.make_current()
	if shot.has("press"):
		var actions: Array = shot["press"] if shot["press"] is Array else [shot["press"]]
		if player:
			player.input_enabled = true
			player.visual.wake_instantly()
		for a: String in actions:
			Input.action_press(a)
		for i in int(shot.get("hold", 1)):
			await get_tree().process_frame
		if not bool(shot.get("keep_pressed", false)):
			for a: String in actions:
				Input.action_release(a)
	if shot.has("focus_button"):
		for node in get_tree().root.find_children("*", "Button", true, false):
			if (node as Button).text == String(shot["focus_button"]) and (node as Button).is_visible_in_tree():
				(node as Button).grab_focus()
				break
	if shot.has("toast"):
		var t: Array = shot["toast"]
		Events.notify.emit(String(t[0]), String(t[1]) if t.size() > 1 else "info")
	if shot.has("discovery"):
		Events.discovery_shown.emit(StringName(shot["discovery"]))
	if shot.has("banner"):
		Events.area_banner.emit(StringName(shot["banner"]))
	for i in int(shot.get("wait", 30)):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if shot.has("press") and bool(shot.get("keep_pressed", false)):
		var acts: Array = shot["press"] if shot["press"] is Array else [shot["press"]]
		for a: String in acts:
			Input.action_release(a)
	var path := ProjectSettings.globalize_path(OUT_DIR + String(shot.get("name", "shot")) + ".png")
	img.save_png(path)
	print("saved ", path, "  fps=", Engine.get_frames_per_second())
	if cam:
		cam.queue_free()
		if rig:
			rig.camera.make_current()
