class_name ShaderWarmup
extends RefCounted
## Browsers compile each shader the first time something is drawn with it, on the page's only
## thread. Drawing a whole new scene at once means compiling dozens of shaders in one frame:
## on a first visit (or after an update that changes shaders) that frame can take tens of
## seconds, and Chrome offers to close the "unresponsive" page.
##
## reveal_gradually() avoids that: the scene's geometry starts hidden and is shown a couple of
## new materials per frame, so every frame stays short and the page keeps responding. run()
## does it behind the loading screen for a whole level, from above, with draw distances and
## area culling lifted, plus the common effects, so the freezes happen while loading instead
## of while playing. The browser keeps the compiled shaders, so later visits skip the work.

const FRAMES := 4
## Render layer used for geometry not yet revealed (no camera or light sees it).
const HIDDEN_LAYER := 1 << 19
## New materials shown per frame. One material is two to four shader programs (with and
## without instancing, plus extra lights), each taking seconds on a slow first compile.
const NEW_PER_FRAME := 1


static func run(scene: Node3D, progress := Callable()) -> void:
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
		p.emitting = false
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
	# The level's own effects (embers, sparks...) run too, so they draw; each starts emitting
	# when it is revealed (its process shader compiles then).
	var particles: Array = []
	for node in scene.find_children("*", "GPUParticles3D", true, false):
		var p := node as GPUParticles3D
		particles.append([p, p.process_mode, p.emitting])
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.emitting = false
	# The router keeps 3D drawing off until now, so nothing compiled before the reveal.
	viewport.disable_3d = false
	await reveal_gradually(scene, true, progress)
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


## Hides every piece of geometry under `root` at once (call it before the scene's first frame),
## then reveals it NEW_PER_FRAME new materials per frame, so no single frame compiles many
## shaders. Pieces whose materials are already known appear together. With `emit`, particle
## systems start emitting as they appear. `progress` (done, total) is called after each frame
## with the number of materials shown so far. Prints a summary line to the console.
static func reveal_gradually(root: Node, emit := false, progress := Callable()) -> void:
	var start := Time.get_ticks_msec()
	var geometry: Array[GeometryInstance3D] = []
	var layers: Array[int] = []
	var all_keys := {}
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		geometry.append(g)
		layers.append(g.layers)
		g.layers = HIDDEN_LAYER
		for key in _material_keys(g):
			all_keys[key] = true
	var total := all_keys.size()
	var lights: Array = []
	for node in root.find_children("*", "Light3D", true, false):
		var l := node as Light3D
		lights.append([l, l.light_cull_mask, l.shadow_caster_mask])
		l.light_cull_mask &= ~HIDDEN_LAYER
		l.shadow_caster_mask &= ~HIDDEN_LAYER
	var cameras: Array = []
	for node in root.find_children("*", "Camera3D", true, false):
		var c := node as Camera3D
		cameras.append([c, c.cull_mask])
		c.cull_mask &= ~HIDDEN_LAYER
	# Reflection probes draw the scene too (into their own cube maps).
	var probes: Array = []
	for node in root.find_children("*", "ReflectionProbe", true, false):
		var p := node as ReflectionProbe
		probes.append([p, p.cull_mask])
		p.cull_mask &= ~HIDDEN_LAYER
	# 3D drawing comes on now (callers may have kept it off). The first frame draws only the
	# sky and screen effects; the next a plain box, because the engine's default material
	# compiles with the first object drawn, on top of that object's own.
	root.get_viewport().disable_3d = false
	await RenderingServer.frame_post_draw
	var first := Time.get_ticks_msec() - start
	if first > 1500:
		print("[ShaderWarmup] slow first frame (sky and screen effects) %d ms" % first)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	root.add_child(box)
	var cam := root.get_viewport().get_camera_3d()
	if cam:
		box.global_position = cam.global_position - cam.global_basis.z * 3.0
	await RenderingServer.frame_post_draw
	box.queue_free()
	# Pieces with several materials (merged models) get a stand-in material on every surface
	# whose material is new, then their own materials back one per frame.
	if _stand_in == null:
		_stand_in = StandardMaterial3D.new()
		_stand_in.albedo_color = Color(0.5, 0.5, 0.5)
	var st := {"seen": {}, "fresh": 0, "frames": 0, "longest": 0, "last": Time.get_ticks_msec(),
		"batch": [], "total": total, "progress": progress}
	var seen: Dictionary = st["seen"]
	for i in geometry.size():
		var g := geometry[i]
		if not is_instance_valid(g):
			continue
		var pending: Array = []
		var mi := g as MeshInstance3D
		if mi and mi.material_override == null and mi.mesh and mi.mesh.get_surface_count() > 1:
			var kind := _kind(g)
			for s in mi.mesh.get_surface_count():
				var key := [kind, mi.get_active_material(s)]
				if not seen.has(key):
					pending.append([s, mi.get_surface_override_material(s), key])
					mi.set_surface_override_material(s, _stand_in)
			if not pending.is_empty():
				_mark(st, g, [kind, _stand_in])
		else:
			for key in _material_keys(g):
				_mark(st, g, key)
		g.layers = layers[i]
		if emit and g is GPUParticles3D:
			(g as GPUParticles3D).emitting = true
		await _maybe_break(st)
		for p: Array in pending:
			if not is_instance_valid(mi):
				break
			mi.set_surface_override_material(p[0], p[1])
			_mark(st, g, p[2])
			await _maybe_break(st)
	await RenderingServer.frame_post_draw
	for entry: Array in lights:
		if is_instance_valid(entry[0]):
			(entry[0] as Light3D).light_cull_mask = entry[1]
			(entry[0] as Light3D).shadow_caster_mask = entry[2]
	for entry: Array in cameras:
		if is_instance_valid(entry[0]):
			(entry[0] as Camera3D).cull_mask = entry[1]
	for entry: Array in probes:
		if is_instance_valid(entry[0]):
			var p := entry[0] as ReflectionProbe
			p.cull_mask = entry[1]
			# A probe that renders once has done so without the hidden pieces: once more.
			if p.update_mode == ReflectionProbe.UPDATE_ONCE:
				p.intensity = p.intensity + (0.0001 if p.intensity < 1.0 else -0.0001)
	print("[ShaderWarmup] %s: %d materials over %d frames in %.1f s, longest frame %d ms" % [
		root.name, seen.size(), st["frames"], (Time.get_ticks_msec() - start) / 1000.0, st["longest"]])


static var _stand_in: StandardMaterial3D


static func _mark(st: Dictionary, g: GeometryInstance3D, key: Array) -> void:
	var seen: Dictionary = st["seen"]
	if not seen.has(key):
		seen[key] = true
		st["fresh"] = int(st["fresh"]) + 1
		(st["batch"] as Array).append(_describe(g, key))


## Ends the frame once NEW_PER_FRAME new materials are on screen, and logs slow frames.
static func _maybe_break(st: Dictionary) -> void:
	if int(st["fresh"]) < NEW_PER_FRAME:
		return
	st["fresh"] = 0
	await RenderingServer.frame_post_draw
	var now := Time.get_ticks_msec()
	var took := now - int(st["last"])
	st["longest"] = maxi(int(st["longest"]), took)
	if took > 1500:
		print("[ShaderWarmup] slow frame %d ms: %s" % [took, ", ".join(st["batch"])])
	(st["batch"] as Array).clear()
	st["last"] = now
	st["frames"] = int(st["frames"]) + 1
	var progress: Callable = st["progress"]
	if progress.is_valid():
		progress.call(mini((st["seen"] as Dictionary).size(), int(st["total"])), int(st["total"]))


static func _describe(g: GeometryInstance3D, key: Array) -> String:
	var what := String(g.name)
	if key.size() > 1 and key[1] is Material:
		var m := key[1] as Material
		var src := m.resource_path
		if m is ShaderMaterial and (m as ShaderMaterial).shader:
			src = (m as ShaderMaterial).shader.resource_path
		what += "(%s %s)" % [m.get_class(), src.get_file()]
	return what


## What decides which shaders a piece needs: its materials and its kind (skinned, instanced,
## particles and text each compile their own variants).
static func _kind(g: GeometryInstance3D) -> String:
	var kind := g.get_class()
	if g is MeshInstance3D and (g as MeshInstance3D).skin != null:
		kind += ":skinned"
	return kind


static func _material_keys(g: GeometryInstance3D) -> Array:
	var kind := _kind(g)
	var keys: Array = []
	if g.material_override:
		keys.append([kind, g.material_override])
	elif g is MeshInstance3D and (g as MeshInstance3D).mesh:
		var mi := g as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			keys.append([kind, mi.get_active_material(s)])
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh and (g as MultiMeshInstance3D).multimesh.mesh:
		var mesh := (g as MultiMeshInstance3D).multimesh.mesh
		for s in mesh.get_surface_count():
			keys.append([kind, mesh.surface_get_material(s)])
	elif g is GPUParticles3D:
		var p := g as GPUParticles3D
		keys.append([kind, p.process_material])
		if p.draw_pass_1:
			for s in p.draw_pass_1.get_surface_count():
				keys.append([kind, p.draw_pass_1.surface_get_material(s)])
	else:
		keys.append([kind])
	if g.material_overlay:
		keys.append([kind, g.material_overlay])
	return keys
