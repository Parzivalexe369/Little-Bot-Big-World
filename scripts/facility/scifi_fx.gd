class_name ScifiFx
extends RefCounted
## Particle and ambient effects for the sci-fi areas: dust motes in the light, rising embers,
## steam, spark showers, energy motes, and jagged electrical arcs. All GPU particles with soft
## additive sprites (generated once), no collision, sized so they never hide the robot,
## hazards or puzzle parts.

static var _sprite: Texture2D
static var _materials: Dictionary = {}


## A soft round sprite (radial falloff), generated once.
static func sprite() -> Texture2D:
	if _sprite == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
		img.generate_mipmaps()
		_sprite = ImageTexture.create_from_image(img)
	return _sprite


## Billboard material for particles. additive: glowing (embers, sparks, motes); otherwise
## alpha-blended and lit (dust, steam).
static func _material(color: Color, additive: bool, energy: float) -> StandardMaterial3D:
	var key := "%s|%s|%.2f" % [color.to_html(), additive, energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = sprite()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if additive else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.4
	m.distance_fade_max_distance = 1.6
	if additive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	m.disable_receive_shadows = true
	_materials[key] = m
	return m


static func _emitter(parent: Node, pos: Vector3, amount: int, lifetime: float, mat: Material, pm: ParticleProcessMaterial, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.preprocess = lifetime
	parent.add_child(p)
	p.position = pos
	p.visibility_aabb = AABB(-Vector3(30, 30, 30), Vector3(60, 60, 60))
	return p


static func _fade_curve(peak := 0.2) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(peak, 1.0))
	c.add_point(Vector2(0.75, 0.8))
	c.add_point(Vector2(1.0, 0.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _alpha_ramp(color: Color, peak := 0.2) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.set_color(1, Color(color, 0.0))
	g.add_point(peak, color)
	g.add_point(0.7, Color(color, color.a * 0.7))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Slow dust motes drifting in a room (catch the light; lit, not glowing).
static func dust(parent: Node, center: Vector3, size: Vector3, amount := 160, color := Color(0.85, 0.85, 0.8, 0.35)) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5
	pm.gravity = Vector3(0, -0.01, 0)
	pm.direction = Vector3(1, 0.2, 0.3)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed_random = 0.3
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color_ramp = _alpha_ramp(color, 0.3)
	return _emitter(parent, center, amount, 12.0, _material(Color.WHITE, false, 0.0), pm, 0.03)


## Glowing embers rising from a surface (plasma, sparks over a fire).
static func embers(parent: Node, center: Vector3, size: Vector3, color: Color, amount := 300, rise := 1.6, energy := 3.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = rise * 0.5
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0, 0.1, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.scale_curve = _fade_curve(0.15)
	pm.color = color
	var p := _emitter(parent, center, amount, 9.0, _material(Color.WHITE, true, energy), pm, 0.12)
	p.visibility_aabb = AABB(-Vector3(size.x, 4, size.z) * 0.6, Vector3(size.x * 1.2, 40.0, size.z * 1.2))
	return p


## Soft steam or haze rising from a vent or pipe (lit by the scene).
static func steam(parent: Node, pos: Vector3, direction := Vector3.UP, amount := 40, color := Color(0.8, 0.85, 0.85, 0.22), speed := 1.2, spread := 12.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = direction
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.25))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.color_ramp = _alpha_ramp(color, 0.15)
	return _emitter(parent, pos, amount, 3.5, _material(Color.WHITE, false, 0.0), pm, 1.1)


## Bursts of sparks spraying from damaged machinery every few seconds (one-shot, re-fired).
static func sparks(parent: Node, pos: Vector3, direction: Vector3, color := Color(1.0, 0.7, 0.35), amount := 40) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction = direction
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.3
	pm.scale_max = 0.7
	pm.scale_curve = _fade_curve(0.05)
	pm.color = color
	pm.particle_flag_align_y = true
	var p := _emitter(parent, pos, amount, 0.9, _material(Color.WHITE, true, 6.0), pm, 0.06)
	(p.draw_pass_1 as QuadMesh).size = Vector2(0.03, 0.14)
	var m := (p.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	m = m.duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	(p.draw_pass_1 as QuadMesh).material = m
	p.one_shot = true
	p.explosiveness = 0.9
	p.preprocess = 0.0
	p.emitting = false
	return p


## Energy motes spiralling around a column (reactor heart, cores, portals).
static func motes(parent: Node, center: Vector3, radius: float, height: float, color: Color, amount := 120, energy := 3.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.6
	pm.emission_ring_height = height
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3.ZERO
	pm.orbit_velocity_min = 0.08
	pm.orbit_velocity_max = 0.2
	pm.radial_accel_min = -0.3
	pm.radial_accel_max = 0.0
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.scale_curve = _fade_curve(0.2)
	pm.color = color
	return _emitter(parent, center, amount, 4.0, _material(Color.WHITE, true, energy), pm, 0.1)


## A flickering electrical arc between two points: a jagged glowing line rebuilt at random
## intervals, with a light that flashes with it.
class Arc extends Node3D:
	var a := Vector3.ZERO
	var b := Vector3(0, 1, 0)
	var color := Color(0.55, 0.85, 1.0)
	var jitter := 0.12
	var rate := 0.35          # chance per second of a crackle burst
	var _mesh: ImmediateMesh
	var _mi: MeshInstance3D
	var _light: OmniLight3D
	var _t := 0.0
	var _burst := 0.0

	func _ready() -> void:
		_mesh = ImmediateMesh.new()
		_mi = MeshInstance3D.new()
		_mi.mesh = _mesh
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 6.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mi.material_override = m
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.omni_range = 4.0
		_light.light_energy = 0.0
		add_child(_light)
		_light.position = (a + b) * 0.5

	func _process(delta: float) -> void:
		_t -= delta
		if _burst <= 0.0 and randf() < rate * delta:
			_burst = randf_range(0.15, 0.5)
		if _burst > 0.0:
			_burst -= delta
			if _t <= 0.0:
				_t = 0.045
				_rebuild()
			_light.light_energy = randf_range(0.8, 2.2)
			_mi.visible = randf() > 0.15
		else:
			_mi.visible = false
			_light.light_energy = 0.0

	func _rebuild() -> void:
		_mesh.clear_surfaces()
		var dir := b - a
		var side := dir.cross(Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(dir).normalized()
		var cam := get_viewport().get_camera_3d()
		var w := 0.012
		var pts: Array[Vector3] = [a]
		var segs := 9
		for i in range(1, segs):
			var t := float(i) / segs
			var off := (side * randf_range(-1, 1) + up * randf_range(-1, 1)) * jitter * sin(t * PI)
			pts.append(a.lerp(b, t) + off)
		pts.append(b)
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var view := (cam.global_position - global_transform * p0).normalized() if cam else Vector3.UP
			var s := (p1 - p0).cross(global_transform.basis.inverse() * view).normalized() * w
			_mesh.surface_add_vertex(p0 - s)
			_mesh.surface_add_vertex(p1 + s)
			_mesh.surface_add_vertex(p1 - s)
			_mesh.surface_add_vertex(p0 - s)
			_mesh.surface_add_vertex(p0 + s)
			_mesh.surface_add_vertex(p1 + s)
		_mesh.surface_end()
