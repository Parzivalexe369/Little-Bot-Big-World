class_name ShaderWarmup
extends RefCounted
## Browsers compile each shader the first time something is drawn with it, and the game
## freezes for a moment each time: a new area's materials coming into view, the first scan,
## the first pickup. Behind the loading screen (SceneRouter, browsers only) this draws the
## whole level once from above, with draw distances and area culling lifted, plus the common
## effects, so those freezes happen while loading instead of while playing. The browser keeps
## the compiled shaders, so later visits skip the work.

const FRAMES := 4


static func run(scene: Node3D) -> void:
	var tree := scene.get_tree()
	var viewport := scene.get_viewport()
	var previous := viewport.get_camera_3d()
	var lifted: Array = []
	var box := AABB()
	var have_box := false
	for node in scene.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if g.visibility_range_end > 0.0:
			lifted.append([g, g.visibility_range_end])
			g.visibility_range_end = 0.0
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			var b := g.global_transform * g.get_aabb()
			if b.size.length() < 400.0:
				box = b if not have_box else box.merge(b)
				have_box = true
	var shown: Array = []
	for node in scene.find_children("*", "FacilityArea", true, false):
		if not (node as Node3D).visible:
			(node as Node3D).visible = true
			shown.append(node)
	if not have_box:
		box = AABB(Vector3(-50, -10, -50), Vector3(100, 20, 100))
	# Top-down view of everything.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.z) * 1.05
	cam.near = 1.0
	cam.far = box.size.y + 500.0
	scene.add_child(cam)
	var top := box.get_center() + Vector3.UP * (box.size.y * 0.5 + 200.0)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), top)
	cam.make_current()
	# The usual gameplay effects, in view and running despite the paused game.
	var fx := Node3D.new()
	fx.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(fx)
	fx.global_position = box.get_center() + Vector3.UP * (box.size.y * 0.5 + 2.0)
	var color := Color(0.5, 0.95, 1.0)
	for p: GPUParticles3D in [FxFactory.sparkles(color), FxFactory.burst(color), FxFactory.dust_burst(color),
			FxFactory.dust_trail(color), FxFactory.energy_trail(color)]:
		p.emitting = true
		fx.add_child(p)
	FxFactory.ring_pulse(fx, fx.global_position, color)
	var dummy := MeshInstance3D.new()
	dummy.mesh = SphereMesh.new()
	fx.add_child(dummy)
	ScanHighlight.flash(dummy)
	var shell := MeshInstance3D.new()
	shell.mesh = SphereMesh.new()
	var shell_material := ShaderMaterial.new()
	shell_material.shader = ScanPulse.SHELL_SHADER
	shell.material_override = shell_material
	fx.add_child(shell)
	# The level's own effects (embers, sparks...) run for these frames too, so they draw.
	var particles: Array = []
	for node in scene.find_children("*", "GPUParticles3D", true, false):
		var p := node as GPUParticles3D
		particles.append([p, p.process_mode, p.emitting])
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.emitting = true
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	# Back to the game as it was.
	for entry: Array in particles:
		if is_instance_valid(entry[0]):
			var p := entry[0] as GPUParticles3D
			p.process_mode = entry[1]
			if not entry[2]:
				# Was idle (e.g. one-shot sparks): clear what the warm-up emitted.
				p.restart()
			p.emitting = entry[2]
	fx.queue_free()
	cam.queue_free()
	for entry: Array in lifted:
		if is_instance_valid(entry[0]):
			(entry[0] as GeometryInstance3D).visibility_range_end = entry[1]
	for node: Node3D in shown:
		if is_instance_valid(node):
			node.visible = false
	if is_instance_valid(previous):
		previous.make_current()
	await tree.process_frame
