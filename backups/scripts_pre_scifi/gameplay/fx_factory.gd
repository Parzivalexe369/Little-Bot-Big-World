class_name FxFactory
extends RefCounted
## Lightweight particle effects built in code with shared materials.

static var _quad_materials: Dictionary = {}


static func _glow_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _quad_materials.has(key):
		return _quad_materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	_quad_materials[key] = m
	return m


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_dot = tex
	return tex


static func _quad(size: float, color: Color) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _glow_material(color)
	return q


static func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.75, Color(1, 1, 1, 0.8))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Gentle looping sparkle around a point (fragments, active machines).
static func sparkles(color: Color, amount: int = 12, radius: float = 0.6, size: float = 0.09) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.preprocess = 1.0
	p.visibility_range_end = 50.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = color
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _quad(size, color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## One-shot burst that frees itself.
static func burst(color: Color, amount: int = 24, speed: float = 3.0, size: float = 0.12) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.gravity = Vector3(0, -1.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = color
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _quad(size, color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Large soft area effect: floating pollen / dust motes / fireflies in a box around a node.
static func ambient_motes(color: Color, amount: int, extents: Vector3, size: float = 0.07, rise: float = 0.1, lifetime: float = 6.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.visibility_aabb = AABB(-extents * 1.5, extents * 3.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.3, 1.0, 0.1)
	pm.spread = 60.0
	pm.initial_velocity_min = rise * 0.3
	pm.initial_velocity_max = rise
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color = color
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _quad(size, color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	return p


## Rising column of light particles (restorations, activations).
static func fountain(color: Color, amount: int = 60, height: float = 6.0, radius: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.4
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = height * 0.3
	pm.initial_velocity_max = height * 0.55
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color = color
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _quad(0.16, color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static var _dust_mat: StandardMaterial3D


## Soft, non-glowing billboard for dust (alpha blended, picks up the particle color).
static func _dust_material() -> StandardMaterial3D:
	if _dust_mat:
		return _dust_mat
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.3
	_dust_mat = m
	return m


static func _dust_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.15, Color(1, 1, 1, 1))
	g.add_point(0.5, Color(1, 1, 1, 0.6))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.45))
	c.add_point(Vector2(1.0, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


## One-shot ring of dust thrown outward along the ground (landings, take-offs, bumps).
static func dust_burst(color: Color, amount: int = 18, speed: float = 2.2, size: float = 0.5) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.25
	pm.emission_ring_inner_radius = 0.1
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(1, 0.25, 0)
	pm.spread = 180.0
	pm.flatness = 0.85
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.gravity = Vector3(0, 0.25, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.scale_curve = _grow_curve()
	pm.color = color
	pm.color_ramp = _dust_ramp()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _dust_material()
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Continuous dust kicked up behind a moving body; drive amount_ratio / emitting from code.
static func dust_trail(color: Color, amount: int = 24, size: float = 0.42) -> GPUParticles3D:
	var p := dust_burst(color, amount, 0.8, size)
	p.finished.disconnect(p.queue_free)
	p.one_shot = false
	p.explosiveness = 0.0
	p.lifetime = 1.0
	p.emitting = false
	return p


## Glowing motes left behind while boosting (world space, so they hang in the air as a trail).
static func energy_trail(color: Color, amount: int = 36, size: float = 0.07) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.55
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0, 0.2, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = color
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _quad(size, color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static var _ring_mats: Dictionary = {}


## Expanding glowing ring that fades out (interaction confirm, pickups). Adds itself to parent.
static func ring_pulse(parent: Node, position: Vector3, color: Color, radius: float = 1.0, duration: float = 0.55, vertical := false) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	mi.mesh = torus
	var key := color.to_html()
	if not _ring_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = color
		m.disable_receive_shadows = true
		_ring_mats[key] = m
	var mat: StandardMaterial3D = (_ring_mats[key] as StandardMaterial3D).duplicate()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = position
	if vertical:
		mi.rotation.x = PI * 0.5
	mi.scale = Vector3.ONE * radius * 0.2
	var tween := mi.create_tween().set_parallel(true)
	tween.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)
