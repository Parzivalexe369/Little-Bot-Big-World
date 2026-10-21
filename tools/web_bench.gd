extends Node
## Dev tool: browser benchmark. build_web.py --test exports it as build/web_test/bench (its
## main scene); open index.html?scene=world or ?scene=facility. It visits fixed spots, waits
## for shaders to settle, and prints one "BENCH" line per spot to the browser console:
## average and worst frame time, draw calls and the 3D render scale.
## Optional: &exp=shadow,glow,... also measures each spot with that feature switched off
## (see _apply), &scale=0.5 sets the 3D render scale.
## Natively: godot --path . res://tools/web_bench.tscn -- facility

const SPOTS := {
	"world": [["meadow", Vector3(3, 0, 30)], ["forest", Vector3(-12, 0, -120)], ["shrine", Vector3(27, 0, -250)], ["garden", Vector3(-6, 0, -380)]],
	"facility": [["lab_entry", &"lab_entry"], ["lab_optics", &"lab_optics"], ["lab_control", &"lab_control"], ["rx_entry", &"reactor_entry"], ["rx_cores", &"reactor_cores"], ["q_entry", &"quantum_entry"], ["q_final", &"quantum_final"]],
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var which := "world"
	var exps: PackedStringArray = []
	if OS.has_feature("web"):
		which = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('scene') || 'world'"))
		var e := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('exp') || ''"))
		if e != "":
			exps = e.split(",")
		var sc := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('scale') || ''"))
		if sc != "":
			Settings.render_scale = float(sc)
			Settings.apply_display()
	elif OS.get_cmdline_user_args().has("facility"):
		which = "facility"
	if which == "new_game" or which == "travel_lab":
		# A real start (or a trip to the facility): the loading screen and shader warm-up run
		# as for a player; with a cold browser, the console shows any slow warm-up frames.
		if which == "new_game":
			SceneRouter.start_new_game()
		else:
			SceneRouter.travel_to(&"lab")
		return
	if which == "empty":
		# Baseline: an empty 3D scene shows the browser's own cost per frame.
		var cam := Camera3D.new()
		add_child(cam)
		for i in 60:
			await get_tree().process_frame
		await _measure("empty")
		print("BENCH done")
		return
	var world: Node = (load("res://scenes/%s/%s.tscn" % [which, which]) as PackedScene).instantiate()
	world.set("pause_on_focus_loss", false)
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for i in 30:
		await get_tree().process_frame
	var player := world.get_node("Player") as Player
	var rig := world.get_node("CameraRig") as CameraRig
	player.visual.wake_instantly()
	print("BENCH start scene=%s adapter=%s canvas=%s scale=%.2f" % [which, RenderingServer.get_video_adapter_name(), get_viewport().get_visible_rect().size, get_viewport().scaling_3d_scale])
	for spot: Array in SPOTS[which]:
		var pos: Vector3
		var yaw := 0.0
		if spot[1] is StringName:
			for cp in world.find_children("*", "Checkpoint", true, false):
				if (cp as Checkpoint).checkpoint_id == spot[1]:
					pos = (cp as Node3D).global_position
					yaw = (cp as Node3D).global_rotation.y
		else:
			pos = WorldTerrain.point_on_ground(spot[1].x, spot[1].z, 0.3)
		player.respawn_at(pos, yaw)
		rig.yaw = yaw
		rig.pitch = deg_to_rad(-14.0)
		rig.snap_to_target()
		# Let new shaders compile and streaming settle before measuring.
		var calm := 0
		var last := Time.get_ticks_usec()
		for i in 600:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			calm = calm + 1 if now - last < 100000 else 0
			last = now
			if calm >= 90:
				break
		await _measure(String(spot[0]))
		for exp in exps:
			var undo := _apply(world, exp)
			for i in 20:
				await get_tree().process_frame
			await _measure("  -" + exp)
			undo.call()
	print("BENCH done")


var _frame_start := 0
var _busy := 0
var _busy_frames := 0


func _on_frame_start() -> void:
	if _frame_start == 0:
		_frame_start = Time.get_ticks_usec()


func _on_frame_drawn() -> void:
	if _frame_start != 0:
		_busy += Time.get_ticks_usec() - _frame_start
		_busy_frames += 1
	_frame_start = 0


## Average and worst frame time, plus "busy": the time from the start of a frame's physics
## and scripts to the end of its rendering commands, which a browser frame cap or vsync
## wait does not hide (GPU work after that is not included).
func _measure(label: String) -> void:
	if not get_tree().physics_frame.is_connected(_on_frame_start):
		get_tree().physics_frame.connect(_on_frame_start)
		get_tree().process_frame.connect(_on_frame_start)
		RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_busy = 0
	_busy_frames = 0
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var worst := 0.0
	var last := t0
	var draws := 0
	while Time.get_ticks_usec() - t0 < 3000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("BENCH %-11s frame=%6.2fms busy=%6.2fms worst=%6.1fms draws=%4d" % [label, ms, _busy / 1000.0 / maxi(_busy_frames, 1), worst, draws / frames])


## Switches one feature off; returns a Callable that switches it back on.
func _apply(world: Node, exp: String) -> Callable:
	var changed: Array = []
	match exp:
		"shadow":
			for n in world.find_children("*", "Light3D", true, false):
				if (n as Light3D).shadow_enabled:
					changed.append(n)
					(n as Light3D).shadow_enabled = false
			return func() -> void:
				for n in changed:
					(n as Light3D).shadow_enabled = true
		"glow", "fog":
			var we := world.find_children("*", "WorldEnvironment", true, false)
			if we.is_empty():
				return func() -> void: pass
			var env := (we[0] as WorldEnvironment).environment
			var was: bool = env.glow_enabled if exp == "glow" else env.fog_enabled
			env.set("glow_enabled" if exp == "glow" else "fog_enabled", false)
			return func() -> void:
				env.set("glow_enabled" if exp == "glow" else "fog_enabled", was)
		"tiny":
			var old := get_viewport().scaling_3d_scale
			get_viewport().scaling_3d_scale = 0.25
			return func() -> void:
				get_viewport().scaling_3d_scale = old
		"hud":
			for n in world.find_children("*", "CanvasLayer", true, false):
				if (n as CanvasLayer).visible:
					changed.append(n)
					(n as CanvasLayer).visible = false
			return func() -> void:
				for n in changed:
					(n as CanvasLayer).visible = true
		"audio":
			AudioServer.set_bus_mute(0, true)
			return func() -> void:
				AudioServer.set_bus_mute(0, false)
		"process":
			# Script work: pause every node's _process/_physics_process except the camera.
			for n in world.find_children("*", "", true, false):
				if n.is_processing() or n.is_physics_processing():
					changed.append([n, n.is_processing(), n.is_physics_processing()])
					n.set_process(false)
					n.set_physics_process(false)
			return func() -> void:
				for c in changed:
					(c[0] as Node).set_process(c[1])
					(c[0] as Node).set_physics_process(c[2])
		_:
			# Hide every node whose script class or node class matches.
			for n in world.find_children("*", "", true, false):
				var sc: Script = n.get_script()
				var cls := String(sc.get_global_name()) if sc else ""
				if (cls == exp or n.get_class() == exp) and n is Node3D and (n as Node3D).visible:
					changed.append(n)
					(n as Node3D).visible = false
			return func() -> void:
				for n in changed:
					(n as Node3D).visible = true
