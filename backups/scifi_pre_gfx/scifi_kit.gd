class_name ScifiKit
extends RefCounted
## Building blocks for the three facility areas: the Blender-modelled sci-fi props
## (assets/environment/scifi_props.glb) with their materials swapped for Godot shaders,
## architecture blocks (walls, floors, trims) with collision, lights, and glow overrides.

const PROPS_SCENE := "res://assets/environment/scifi_props.glb"
const PANEL := preload("res://shaders/scifi_panel.gdshader")
const GLASS := preload("res://shaders/scifi_glass.gdshader")
const SCREEN := preload("res://shaders/scifi_screen.gdshader")
const HOLO := preload("res://shaders/hologram.gdshader")
const ENERGY := preload("res://shaders/energy_field.gdshader")
const PORTAL := preload("res://shaders/portal.gdshader")
const NOISE := preload("res://materials/noise_tex.tres")
const TEX := "res://assets/textures/"
const SCIFI_TEX := "res://assets/textures/scifi/"
## Mean linear luminance of each sci-fi scan's albedo (the shader keeps its detail while
## the material keeps its own colour).
const SCAN_LUM := {
	"blue_metal_plate": 0.044, "concrete_floor_worn_001": 0.093, "hangar_concrete_floor": 0.031,
	"large_floor_tiles_02": 0.183, "metal_plate": 0.036, "metal_plate_02": 0.072,
}

## Collision used by place(): "box" (mesh bounds), "convex", "trimesh" or "" (none).
const COLLISION := {
	"sf_console": "box", "sf_table": "trimesh", "sf_chamber": "convex", "sf_rack": "box", "sf_crate": "box",
	"sf_pipe": "convex", "sf_arm": "", "sf_lamp": "", "sf_door": "trimesh", "sf_emitter": "convex",
	"sf_receiver": "convex", "sf_cart": "box", "sf_rail": "", "sf_lever": "box", "sf_coupler": "",
	"sf_projector": "convex", "sf_lift": "trimesh", "sf_terminal": "box", "sf_shelf": "trimesh", "sf_grate": "",
	"rx_core": "convex", "rx_ring": "", "rx_gear": "", "rx_pylon": "convex", "rx_arm": "", "rx_platform": "convex",
	"rx_node": "convex", "rx_vent": "", "rx_valve": "box", "rx_lift": "",
	"qt_platform": "box", "qt_portal": "trimesh", "qt_console": "convex", "qt_pad": "", "qt_stairs": "trimesh",
	"qt_blade": "", "qt_core": "convex", "qt_pillar": "convex",
}

static var _root: Node3D
static var _materials: Dictionary = {}
static var _glow_cache: Dictionary = {}
static var _shapes: Dictionary = {}


static func ensure_loaded() -> void:
	if _root != null:
		return
	_root = (load(PROPS_SCENE) as PackedScene).instantiate() as Node3D
	for mi: MeshInstance3D in _root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var m := material(src.resource_name if src else "")
			if m:
				mi.mesh.surface_set_material(s, m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Frees the cached prop scene (called by the facility on exit).
static func release() -> void:
	if _root != null:
		_root.free()
		_root = null
	_materials.clear()
	_glow_cache.clear()
	_shapes.clear()


## A fresh copy of a prop (with its moving child parts).
static func instance(prop: String) -> Node3D:
	ensure_loaded()
	var src := _root.get_node_or_null(prop) as Node3D
	if src == null:
		push_error("ScifiKit: no prop '%s'" % prop)
		return Node3D.new()
	var copy := src.duplicate() as Node3D
	copy.transform = Transform3D.IDENTITY
	return copy


static func place(parent: Node, prop: String, pos: Vector3, yaw_deg := 0.0, scale := 1.0, collision := "default") -> Node3D:
	var node := instance(prop)
	parent.add_child(node)
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	node.scale = Vector3.ONE * scale
	var mode: String = COLLISION.get(prop, "") if collision == "default" else collision
	if mode != "":
		add_collision(node, prop, mode)
	return node


## Static collision for a prop's root mesh (child parts are left to their owners).
static func add_collision(node: Node3D, prop: String, mode: String) -> StaticBody3D:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return null
	var key := "%s|%s" % [prop, mode]
	if not _shapes.has(key):
		match mode:
			"trimesh":
				_shapes[key] = mi.mesh.create_trimesh_shape()
			"convex":
				_shapes[key] = mi.mesh.create_convex_shape(true, true)
			_:
				var bb := mi.mesh.get_aabb()
				var box := BoxShape3D.new()
				box.size = bb.size
				_shapes[key] = [box, bb.get_center()]
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var cs := CollisionShape3D.new()
	var entry: Variant = _shapes[key]
	if entry is Array:
		cs.shape = entry[0]
		cs.position = entry[1]
	else:
		cs.shape = entry
	body.add_child(cs)
	return body


# --- Materials ----------------------------------------------------------------------

static func material(mat_name: String) -> Material:
	if _materials.has(mat_name):
		return _materials[mat_name]
	var m: Material = null
	match mat_name:
		"sf_white":
			m = panel(Color(0.82, 0.84, 0.86), Color(0.75, 0.77, 0.8), 0.6, Vector2(1.0, 0.6), 0.12, 0.34, 0.15)
		"sf_grey":
			m = panel(Color(0.44, 0.46, 0.5), Color(0.4, 0.42, 0.46), 0.5, Vector2(1.0, 0.8), 0.45, 0.42, 0.25)
		"sf_dark":
			m = panel(Color(0.1, 0.11, 0.13), Color(0.13, 0.14, 0.16), 0.45, Vector2(1.0, 0.7), 0.6, 0.36, 0.2)
		"sf_metal":
			m = _std(Color(0.62, 0.64, 0.68), 1.0, 0.3)
			_detail(m as StandardMaterial3D, "rusty_metal_02", 0.25)
		"sf_chrome":
			m = _std(Color(0.95, 0.95, 0.97), 1.0, 0.07)
		"sf_rubber":
			m = _std(Color(0.04, 0.04, 0.045), 0.0, 0.85)
		"sf_glass":
			var g := ShaderMaterial.new()
			g.shader = GLASS
			g.set_shader_parameter("noise_tex", NOISE)
			g.render_priority = 1
			m = g
		"sf_screen":
			var s := ShaderMaterial.new()
			s.shader = SCREEN
			m = s
		"sf_light":
			m = glow(Color(1.0, 0.96, 0.88), 3.2)
		"sf_glow_cyan":
			m = glow(Color(0.3, 0.9, 1.0), 2.6)
		"sf_glow_orange":
			m = glow(Color(1.0, 0.55, 0.15), 2.4)
		"sf_glow_red":
			m = glow(Color(1.0, 0.22, 0.15), 2.4)
		"sf_glow_green":
			m = glow(Color(0.3, 1.0, 0.45), 2.4)
		"sf_hazard":
			m = _hazard()
		"sf_alien":
			m = _std(Color(0.15, 0.13, 0.19), 0.75, 0.32)
			_detail(m as StandardMaterial3D, "dark_rock", 0.6)
			(m as StandardMaterial3D).rim_enabled = true
			(m as StandardMaterial3D).rim = 0.25
		"sf_alien_glow":
			m = glow(Color(0.35, 1.0, 0.85), 3.0)
		"sf_quantum":
			var q := _std(Color(0.9, 0.9, 0.95), 0.0, 0.16)
			q.clearcoat_enabled = true
			q.clearcoat = 0.8
			q.rim_enabled = true
			q.rim = 0.3
			q.rim_tint = 0.8
			m = q
		"sf_quantum_glow":
			m = glow(Color(0.75, 0.5, 1.0), 3.0)
	_materials[mat_name] = m
	return m


static func panel(base: Color, alt: Color, size: float, aspect: Vector2, metal: float, rough: float, grime: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PANEL
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("alt_color", alt)
	m.set_shader_parameter("panel_size", size)
	m.set_shader_parameter("panel_aspect", aspect)
	m.set_shader_parameter("metallic_value", metal)
	m.set_shader_parameter("roughness_value", rough)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("noise_tex", NOISE)
	m.set_shader_parameter("detail_normal", load(TEX + "rusty_painted_metal/rusty_painted_metal_nor.jpg"))
	m.set_shader_parameter("detail_arm", load(TEX + "rusty_painted_metal/rusty_painted_metal_arm.jpg"))
	return m


static func glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m


static func _std(albedo: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metal
	m.roughness = rough
	return m


static func _detail(m: StandardMaterial3D, set_name: String, strength: float) -> void:
	m.normal_enabled = true
	m.normal_texture = load(TEX + "%s/%s_nor.jpg" % [set_name, set_name])
	m.normal_scale = strength
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.8


static func _hazard() -> StandardMaterial3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var yellow := int(floor((x + y) / 16.0)) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.72, 0.08) if yellow else Color(0.06, 0.06, 0.07))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.55
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	return m


## Recolors a prop's glowing parts (per instance), e.g. a lamp going from red to green.
static func set_glow(node: Node, color: Color, energy := 2.6) -> void:
	var key := "%s|%.2f" % [color.to_html(), energy]
	if not _glow_cache.has(key):
		_glow_cache[key] = glow(color, energy)
	var m: Material = _glow_cache[key]
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi: MeshInstance3D in meshes:
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src is StandardMaterial3D and (src as StandardMaterial3D).emission_enabled and src != _materials.get("sf_light"):
				mi.set_surface_override_material(s, m)


## Sets the facility-power instance uniform on every mesh of a node (screens, panels' strips).
static func set_power(node: Node, level: float) -> void:
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi: MeshInstance3D in meshes:
		mi.set_instance_shader_parameter("power_level", level)


# --- Architecture -------------------------------------------------------------------

static var _styles: Dictionary = {}


## Shared architecture materials by style name.
static func style(name: StringName) -> Material:
	if _styles.has(name):
		return _styles[name]
	var m: ShaderMaterial
	match name:
		&"lab_wall":
			m = panel(Color(0.8, 0.82, 0.84), Color(0.72, 0.74, 0.77), 1.6, Vector2(1.0, 0.5), 0.1, 0.38, 0.3)
			m.set_shader_parameter("strip_spacing", 2.4)
			m.set_shader_parameter("strip_energy", 2.2)
			m.set_shader_parameter("strip_color", Color(0.4, 0.85, 1.0))
			m.set_shader_parameter("vent_chance", 0.06)
		&"lab_wall_dark":
			m = panel(Color(0.2, 0.22, 0.25), Color(0.16, 0.18, 0.2), 1.6, Vector2(1.0, 0.5), 0.5, 0.4, 0.3)
		&"lab_floor":
			m = panel(Color(0.32, 0.34, 0.37), Color(0.28, 0.3, 0.33), 1.2, Vector2(1.0, 1.0), 0.55, 0.45, 0.4)
			m.set_shader_parameter("vent_chance", 0.1)
		&"lab_ceiling":
			m = panel(Color(0.55, 0.57, 0.6), Color(0.5, 0.52, 0.55), 1.2, Vector2(1.0, 1.0), 0.3, 0.5, 0.1)
		&"trim":
			m = panel(Color(0.08, 0.09, 0.1), Color(0.1, 0.11, 0.12), 0.8, Vector2(1.0, 0.5), 0.7, 0.35, 0.2)
			m.set_shader_parameter("rivets", 0.0)
		&"reactor_wall":
			m = panel(Color(0.13, 0.12, 0.17), Color(0.17, 0.15, 0.21), 2.4, Vector2(1.0, 0.6), 0.7, 0.32, 0.25)
			m.set_shader_parameter("strip_spacing", 4.0)
			m.set_shader_parameter("strip_energy", 2.6)
			m.set_shader_parameter("strip_color", Color(0.35, 1.0, 0.85))
			m.set_shader_parameter("damage", 0.25)
		&"reactor_cavern":
			m = panel(Color(0.07, 0.07, 0.09), Color(0.1, 0.09, 0.12), 3.2, Vector2(1.0, 0.45), 0.6, 0.45, 0.4)
			m.set_shader_parameter("damage", 0.4)
			m.set_shader_parameter("vent_chance", 0.12)
		&"reactor_support":
			m = panel(Color(0.12, 0.11, 0.15), Color(0.15, 0.13, 0.18), 1.6, Vector2(1.0, 0.8), 0.7, 0.35, 0.35)
			m.set_shader_parameter("damage", 0.2)
		&"reactor_floor":
			m = panel(Color(0.18, 0.17, 0.22), Color(0.22, 0.2, 0.26), 2.0, Vector2(1.0, 1.0), 0.75, 0.3, 0.35)
			m.set_shader_parameter("vent_chance", 0.14)
		&"quantum_white":
			m = panel(Color(0.9, 0.9, 0.94), Color(0.84, 0.85, 0.9), 2.4, Vector2(1.0, 1.0), 0.05, 0.2, 0.0)
			m.set_shader_parameter("vent_chance", 0.02)
			m.set_shader_parameter("strip_spacing", 3.0)
			m.set_shader_parameter("strip_energy", 2.0)
			m.set_shader_parameter("strip_color", Color(0.75, 0.55, 1.0))
			m.set_shader_parameter("rivets", 0.0)
		_:
			m = panel(Color(0.5, 0.5, 0.5), Color(0.45, 0.45, 0.45), 1.0, Vector2.ONE, 0.3, 0.5, 0.2)
	_styles[name] = m
	return m


## A solid block (wall, floor slab, column) with matching box collision.
static func block(parent: Node, size: Vector3, center: Vector3, style_name: StringName, collide := true, yaw_deg := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = style(style_name)
	parent.add_child(mi)
	mi.position = center
	mi.rotation_degrees.y = yaw_deg
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		mi.add_child(body)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
	return mi


static func light(parent: Node, pos: Vector3, color: Color, energy: float, light_range: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = 1.4
	l.distance_fade_enabled = true
	l.distance_fade_begin = 45.0
	l.distance_fade_length = 15.0
	parent.add_child(l)
	l.position = pos
	return l


static func spot(parent: Node, pos: Vector3, target: Vector3, color: Color, energy: float, light_range: float, angle := 40.0, shadow := true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = light_range
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = 2.0
	parent.add_child(l)
	l.look_at_from_position(pos, target, Vector3.UP if absf((target - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	return l


## A label floating in the world (signs, holographic notes).
static func sign(parent: Node, text: String, pos: Vector3, yaw_deg := 0.0, size := 0.06, color := Color(0.6, 0.95, 1.0)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = MenuWidgets.font(MenuWidgets.FONT_TEXT, 650)
	l.pixel_size = size * 0.025
	l.font_size = 64
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.shaded = false
	l.double_sided = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = 1600.0
	parent.add_child(l)
	l.position = pos
	l.rotation_degrees.y = yaw_deg
	return l


## Mesh with an energy-field material (cores, bridges, hazards).
static func energy_mesh(parent: Node, mesh: Mesh, pos: Vector3, color_a: Color, color_b: Color, intensity := 2.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = ENERGY
	m.set_shader_parameter("color_a", color_a)
	m.set_shader_parameter("color_b", color_b)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("noise_tex", NOISE)
	# Drawn after glass (priority 1), so energy inside cores and tubes shows through.
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	return mi


static func holo_material(color: Color, fill := 0.35, energy := 1.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HOLO
	m.set_shader_parameter("holo_color", color)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("energy", energy)
	return m
