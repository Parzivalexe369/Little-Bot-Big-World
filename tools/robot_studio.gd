extends SceneTree
## Dev tool: renders close-ups of the player robot (RobotVisual, so all runtime materials and
## procedural layers apply) under neutral studio light, for checking materials and the face.
## Usage (windowed): godot --path . --script res://tools/robot_studio.gd -- out.png [hide=Mesh,Mesh]
##        [action=Name@seconds] [express=happy|squint|wide|focus|hurt] [squash=-0.2..0.18]

const SIZE := Vector2i(1200, 600)


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://docs/reference/robot_studio.png"
	var hide: PackedStringArray = []
	var action := ""
	var action_t := 0.0
	var expression := ""
	var squash := 0.0
	var has_squash := false
	for a in args:
		if a.begins_with("express="):
			expression = a.substr(8)
		elif a.begins_with("squash="):
			squash = float(a.substr(7))
			has_squash = true
		if a.begins_with("hide="):
			hide = a.substr(5).split(",")
		elif a.begins_with("action="):
			var parts := a.substr(7).split("@")
			action = parts[0]
			action_t = float(parts[1]) if parts.size() > 1 else 0.3
	root.size = SIZE
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.56, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_hdr_threshold = 1.15
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.ssao_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.46, 0.4, 0.32)
	fm.roughness = 0.95
	floor_mesh.material_override = fm
	world.add_child(floor_mesh)
	var views := [[Vector3(0, 0.42, -1.25), 34.0], [Vector3(-0.85, 0.5, -0.95), 34.0], [Vector3(1.15, 0.6, 0.35), 34.0]]
	var sheet := Image.create(SIZE.x * views.size() / 2, SIZE.y, false, Image.FORMAT_RGBA8)
	var robot := RobotVisual.new()
	world.add_child(robot)
	await process_frame
	robot.wake_instantly()
	# Frame the model's actual bounds (hovering a little above the floor).
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in robot.model.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	robot.position = Vector3(0, 0.12 - box.position.y, 0)
	var focus := box.get_center() + Vector3(0, robot.position.y, 0)
	var radius := box.size.length() * 0.5
	for mesh_name in hide:
		var n := robot.model.find_child(mesh_name, true, false) as Node3D
		if n:
			n.visible = false
	if action != "":
		robot.play_action(StringName(action))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	var settle := 40 if action == "" else int(action_t * 60.0)
	if expression != "":
		robot.express(StringName(expression), 999.0)
	for i in settle:
		await process_frame
	if has_squash:
		# Freeze a squash pose for inspection (stops the robot's own update).
		var sy := 1.0 + squash
		robot.model.scale = Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy))
		robot.process_mode = Node.PROCESS_MODE_DISABLED
	for vi in views.size():
		var v: Array = views[vi]
		cam.fov = v[1]
		var dir := (v[0] as Vector3).normalized()
		cam.look_at_from_position(focus + dir * radius * 3.4, focus)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(SIZE.x / 2, SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(vi * SIZE.x / 2, 0))
	sheet.save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	print("saved ", out)
	quit()
