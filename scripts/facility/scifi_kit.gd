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
			var w := panel(Color(0.8, 0.82, 0.84), Color(0.74, 0.76, 0.79), 0.6, Vector2(1.0, 0.6), 0.12, 0.34, 0.2)
			scan(w, "blue_metal_plate", 0.9, 0.0, 0.6)
			_wear(w, 0.55, 0.15, 0.25, 0.3)
			w.set_shader_parameter("groove_depth", 0.008)
			m = w
		"sf_grey":
			var gr := panel(Color(0.42, 0.44, 0.48), Color(0.38, 0.4, 0.44), 0.5, Vector2(1.0, 0.8), 0.45, 0.4, 0.28)
			scan(gr, "blue_metal_plate", 1.0, 0.1, 0.65)
			_wear(gr, 0.6, 0.2, 0.2, 0.2)
			gr.set_shader_parameter("groove_depth", 0.008)
			m = gr
		"sf_dark":
			var dk := panel(Color(0.09, 0.1, 0.115), Color(0.12, 0.13, 0.15), 0.45, Vector2(1.0, 0.7), 0.6, 0.36, 0.22)
			scan(dk, "blue_metal_plate", 1.1, 0.1, 0.6)
			_wear(dk, 0.5, 0.2, 0.15, 0.0)
			dk.set_shader_parameter("groove_depth", 0.008)
			m = dk
		"sf_metal":
			# Scratched steel: roughness and normal from a scratched painted-steel scan.
			var st := _std(Color(0.62, 0.64, 0.68), 1.0, 1.1)
			_scratched(st, 0.45, 0.9)
			m = st
		"sf_chrome":
			var ch := _std(Color(0.95, 0.95, 0.97), 1.0, 0.35)
			_scratched(ch, 0.0, 1.3)
			m = ch
		"sf_rubber":
			var rb := _std(Color(0.04, 0.04, 0.045), 0.0, 0.85)
			rb.normal_enabled = true
			rb.normal_texture = load(SCIFI_TEX + "concrete_floor_worn_001/concrete_floor_worn_001_nor.jpg")
			rb.normal_scale = 0.6
			rb.uv1_triplanar = true
			rb.uv1_world_triplanar = true
			rb.uv1_scale = Vector3.ONE * 2.0
			m = rb
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
			# Dark alien alloy: heavy worn plating without a panel grid.
			var al := panel(Color(0.11, 0.1, 0.14), Color(0.14, 0.12, 0.17), 2.0, Vector2(1.0, 1.0), 0.75, 0.34, 0.25)
			al.set_shader_parameter("seam_width", 0.0)
			al.set_shader_parameter("rivets", 0.0)
			al.set_shader_parameter("vent_chance", 0.0)
			scan(al, "metal_plate_02", 1.0, 0.2, 0.55, 0.6)
			_wear(al, 0.35, 0.0, 0.3, 0.0)
			al.set_shader_parameter("streak_color", Color(0.16, 0.3, 0.26))
			m = al
		"sf_alien_glow":
			m = glow(Color(0.35, 1.0, 0.85), 3.0)
		"sf_quantum":
			var q := _std(Color(0.84, 0.84, 0.89), 0.0, 0.22)
			q.clearcoat_enabled = true
			q.clearcoat = 0.6
			q.clearcoat_roughness = 0.12
			q.rim_enabled = true
			q.rim = 0.3
			q.rim_tint = 0.8
			q.normal_enabled = true
			q.normal_texture = load(SCIFI_TEX + "concrete_floor_worn_001/concrete_floor_worn_001_nor.jpg")
			q.normal_scale = 0.12
			q.uv1_triplanar = true
			q.uv1_world_triplanar = true
			q.uv1_scale = Vector3.ONE * 0.6
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


## Puts a photoscanned PBR surface under a panel material. detail: how much of the scan's
## light/dark variation shows; color: 0 = tinted by the panel colour, 1 = the scan's colour.
static func scan(m: ShaderMaterial, set_name: String, scale: float, color: float, detail: float, metal := 0.0) -> void:
	var base := SCIFI_TEX + "%s/%s" % [set_name, set_name]
	m.set_shader_parameter("use_scan", 1.0)
	m.set_shader_parameter("scan_albedo", load(base + "_diff.jpg"))
	m.set_shader_parameter("scan_normal", load(base + "_nor.jpg"))
	m.set_shader_parameter("scan_arm", load(base + "_arm.jpg"))
	m.set_shader_parameter("scan_lum", SCAN_LUM[set_name])
	m.set_shader_parameter("scan_scale", scale)
	m.set_shader_parameter("scan_color", color)
	m.set_shader_parameter("scan_detail", detail)
	m.set_shader_parameter("scan_metal", metal)
	m.set_shader_parameter("detail_strength", 0.25)


## Surface ageing: paint wear on edges, dust on top faces, streaks under seams, stencils.
static func _wear(m: ShaderMaterial, wear: float, dust_amount: float, streak: float, marks: float) -> void:
	m.set_shader_parameter("edge_wear", wear)
	m.set_shader_parameter("dust", dust_amount)
	m.set_shader_parameter("streaks", streak)
	m.set_shader_parameter("markings", marks)


static func _scratched(m: StandardMaterial3D, normal_strength: float, scale: float) -> void:
	m.roughness_texture = load(SCIFI_TEX + "blue_metal_plate/blue_metal_plate_arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	if normal_strength > 0.0:
		m.normal_enabled = true
		m.normal_texture = load(SCIFI_TEX + "blue_metal_plate/blue_metal_plate_nor.jpg")
		m.normal_scale = normal_strength
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale


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
	m.normal_enabled = true
	m.normal_texture = load(SCIFI_TEX + "blue_metal_plate/blue_metal_plate_nor.jpg")
	m.normal_scale = 0.5
	m.roughness_texture = load(SCIFI_TEX + "blue_metal_plate/blue_metal_plate_arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.4
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
			if src is StandardMaterial3D and (src as StandardMaterial3D).emission_enabled:
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
static var _bevel_meshes: Dictionary = {}

## Chamfer size of each architecture style's block edges (metres).
const STYLE_BEVEL := {
	&"lab_wall": 0.035, &"lab_wall_dark": 0.035, &"lab_floor": 0.025, &"lab_ceiling": 0.04, &"trim": 0.02,
	&"reactor_wall": 0.05, &"reactor_cavern": 0.0, &"reactor_support": 0.06, &"reactor_floor": 0.04,
	&"quantum_white": 0.03,
}


## Shared architecture materials by style name.
static func style(name: StringName) -> Material:
	if _styles.has(name):
		return _styles[name]
	var m: ShaderMaterial
	match name:
		&"lab_wall":
			# Off-white painted steel panels, scuffed and streaked, with stencilled labels.
			m = panel(Color(0.78, 0.8, 0.82), Color(0.7, 0.72, 0.75), 1.6, Vector2(1.0, 0.5), 0.1, 0.36, 0.32)
			m.set_shader_parameter("strip_spacing", 2.4)
			m.set_shader_parameter("strip_energy", 2.2)
			m.set_shader_parameter("strip_color", Color(0.4, 0.85, 1.0))
			m.set_shader_parameter("vent_chance", 0.06)
			scan(m, "blue_metal_plate", 0.35, 0.0, 0.85)
			_wear(m, 0.6, 0.0, 0.4, 0.55)
			m.set_shader_parameter("groove_depth", 0.03)
			m.set_shader_parameter("recess_chance", 0.14)
		&"lab_wall_dark":
			m = panel(Color(0.19, 0.2, 0.22), Color(0.15, 0.16, 0.18), 1.6, Vector2(1.0, 0.5), 0.5, 0.4, 0.32)
			scan(m, "blue_metal_plate", 0.35, 0.05, 0.9)
			_wear(m, 0.65, 0.0, 0.3, 0.3)
			m.set_shader_parameter("groove_depth", 0.03)
			m.set_shader_parameter("recess_chance", 0.18)
		&"lab_floor":
			# Coated deck plates: polished where people walked, dusty in the corners.
			m = panel(Color(0.3, 0.315, 0.33), Color(0.26, 0.275, 0.29), 2.4, Vector2(1.0, 0.5), 0.2, 0.42, 0.4)
			m.set_shader_parameter("vent_chance", 0.05)
			scan(m, "hangar_concrete_floor", 0.3, 0.15, 0.9)
			_wear(m, 0.45, 0.45, 0.0, 0.0)
			m.set_shader_parameter("gloss", 0.6)
			m.set_shader_parameter("groove_depth", 0.015)
			m.set_shader_parameter("recess_chance", 0.0)
		&"lab_ceiling":
			m = panel(Color(0.5, 0.52, 0.55), Color(0.46, 0.48, 0.51), 1.2, Vector2(1.0, 1.0), 0.2, 0.55, 0.15)
			scan(m, "concrete_floor_worn_001", 0.4, 0.1, 0.8)
			m.set_shader_parameter("groove_depth", 0.045)
			m.set_shader_parameter("recess_chance", 0.35)
		&"trim":
			# Dark gunmetal kick plates and end caps, worn bright on the edges.
			m = panel(Color(0.08, 0.085, 0.095), Color(0.1, 0.105, 0.115), 0.8, Vector2(1.0, 0.5), 0.7, 0.34, 0.2)
			m.set_shader_parameter("rivets", 0.0)
			scan(m, "metal_plate_02", 0.8, 0.15, 0.8, 0.5)
			_wear(m, 0.75, 0.15, 0.0, 0.0)
			m.set_shader_parameter("groove_depth", 0.006)
		&"reactor_wall":
			m = panel(Color(0.13, 0.12, 0.17), Color(0.17, 0.15, 0.21), 2.4, Vector2(1.0, 0.6), 0.7, 0.32, 0.25)
			m.set_shader_parameter("strip_spacing", 4.0)
			m.set_shader_parameter("strip_energy", 2.6)
			m.set_shader_parameter("strip_color", Color(0.35, 1.0, 0.85))
			m.set_shader_parameter("damage", 0.25)
			scan(m, "metal_plate_02", 0.3, 0.15, 0.9, 0.6)
			_wear(m, 0.4, 0.0, 0.35, 0.0)
		&"reactor_cavern":
			# Colossal alien plating, streaked with oxidation.
			m = panel(Color(0.07, 0.07, 0.09), Color(0.1, 0.09, 0.12), 3.2, Vector2(1.0, 0.45), 0.6, 0.42, 0.4)
			m.set_shader_parameter("damage", 0.4)
			m.set_shader_parameter("vent_chance", 0.12)
			scan(m, "metal_plate_02", 0.12, 0.2, 1.0, 0.6)
			_wear(m, 0.3, 0.0, 0.5, 0.0)
			m.set_shader_parameter("streak_color", Color(0.16, 0.32, 0.27))
			m.set_shader_parameter("groove_depth", 0.08)
			m.set_shader_parameter("recess_chance", 0.25)
		&"reactor_support":
			m = panel(Color(0.12, 0.11, 0.15), Color(0.15, 0.13, 0.18), 1.6, Vector2(1.0, 0.8), 0.7, 0.35, 0.35)
			m.set_shader_parameter("damage", 0.2)
			scan(m, "metal_plate_02", 0.4, 0.2, 0.9, 0.6)
			_wear(m, 0.5, 0.0, 0.45, 0.0)
			m.set_shader_parameter("streak_color", Color(0.16, 0.32, 0.27))
			m.set_shader_parameter("groove_depth", 0.04)
		&"reactor_floor":
			# Tread-plate deck in dark steel, edges polished by traffic.
			m = panel(Color(0.17, 0.165, 0.2), Color(0.2, 0.19, 0.23), 2.0, Vector2(1.0, 1.0), 0.75, 0.32, 0.35)
			m.set_shader_parameter("vent_chance", 0.14)
			scan(m, "metal_plate", 0.5, 0.15, 0.9, 0.5)
			_wear(m, 0.6, 0.25, 0.0, 0.0)
			m.set_shader_parameter("gloss", 0.3)
			m.set_shader_parameter("groove_depth", 0.02)
			m.set_shader_parameter("recess_chance", 0.0)
		&"quantum_white":
			# Pristine white ceramic tiles with a glossy glaze.
			m = panel(Color(0.9, 0.9, 0.94), Color(0.85, 0.86, 0.91), 2.4, Vector2(1.0, 1.0), 0.05, 0.16, 0.0)
			m.set_shader_parameter("vent_chance", 0.02)
			m.set_shader_parameter("strip_spacing", 3.0)
			m.set_shader_parameter("strip_energy", 2.0)
			m.set_shader_parameter("strip_color", Color(0.75, 0.55, 1.0))
			m.set_shader_parameter("rivets", 0.0)
			scan(m, "large_floor_tiles_02", 0.3, 0.0, 0.3)
			m.set_shader_parameter("scan_rough", 0.15)
			m.set_shader_parameter("scan_normal_strength", 0.35)
			m.set_shader_parameter("groove_depth", 0.012)
			m.set_shader_parameter("recess_chance", 0.06)
			m.set_shader_parameter("edge_wear", 0.08)
			m.set_shader_parameter("wear_color", Color(0.75, 0.7, 0.9))
		_:
			m = panel(Color(0.5, 0.5, 0.5), Color(0.45, 0.45, 0.45), 1.0, Vector2.ONE, 0.3, 0.5, 0.2)
	m.set_shader_parameter("vertex_edges", 1.0)
	_styles[name] = m
	return m


## A solid block (wall, floor slab, column) with matching box collision. The visual mesh is
## a chamfered box (edges catch the light and show paint wear); collision stays the box.
static func block(parent: Node, size: Vector3, center: Vector3, style_name: StringName, collide := true, yaw_deg := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = bevel_box(size, STYLE_BEVEL.get(style_name, 0.03))
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


## A box with chamfered edges and corners, exactly filling `size`. Vertex colour red is 1 on
## the chamfers (the panel shader wears paint there). Cached per size.
static func bevel_box(size: Vector3, chamfer: float) -> Mesh:
	var c := minf(chamfer, minf(size.x, minf(size.y, size.z)) * 0.3)
	if c < 0.004:
		var plain := BoxMesh.new()
		plain.size = size
		return plain
	var key := "%.3f|%.3f|%.3f|%.3f" % [size.x, size.y, size.z, c]
	if _bevel_meshes.has(key):
		return _bevel_meshes[key]
	var e := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Main faces (inset by the chamfer).
	for axis in 3:
		for s in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var q: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = s * e[axis]
				p[u] = corner.x * (e[u] - c)
				p[v] = corner.y * (e[v] - c)
				q.append(p)
			_quad(st, q, n, 0.0)
	# Edge chamfers: between faces on two axes.
	for a in 3:
		var b := (a + 1) % 3
		var w := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[a] = sa
				n[b] = sb
				n = n.normalized()
				var q: Array[Vector3] = []
				for sw in [-1.0, 1.0]:
					var p1 := Vector3.ZERO
					p1[a] = sa * e[a]
					p1[b] = sb * (e[b] - c)
					p1[w] = sw * (e[w] - c)
					var p2 := Vector3.ZERO
					p2[a] = sa * (e[a] - c)
					p2[b] = sb * e[b]
					p2[w] = sw * (e[w] - c)
					q.append(p1)
					q.append(p2)
				_quad(st, [q[0], q[1], q[3], q[2]], n, 1.0)
	# Corner triangles.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				var t: Array[Vector3] = [
					Vector3(sx * e.x, sy * (e.y - c), sz * (e.z - c)),
					Vector3(sx * (e.x - c), sy * e.y, sz * (e.z - c)),
					Vector3(sx * (e.x - c), sy * (e.y - c), sz * e.z),
				]
				_tri(st, t[0], t[1], t[2], n, 1.0)
	var mesh := st.commit()
	_bevel_meshes[key] = mesh
	return mesh


static func _quad(st: SurfaceTool, q: Array, n: Vector3, edge: float) -> void:
	_tri(st, q[0], q[1], q[2], n, edge)
	_tri(st, q[0], q[2], q[3], n, edge)


## One triangle facing `n` (Godot front faces wind clockwise).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, edge: float) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for p: Vector3 in [a, b, c]:
		st.set_color(Color(edge, 0, 0))
		st.set_normal(n)
		st.add_vertex(p)


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


## A box-projected reflection probe for a room, rendered once (call refresh_probe after the
## room's lighting changes). The robot is left out so it never appears baked into walls.
static func probe(parent: Node, center: Vector3, size: Vector3, intensity := 1.0) -> ReflectionProbe:
	var p := ReflectionProbe.new()
	p.size = size
	p.box_projection = true
	p.interior = true
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	p.intensity = intensity
	p.blend_distance = 1.5
	p.max_distance = size.length() + 10.0
	p.cull_mask = 0xFFFFF & ~RobotMaterials.ROBOT_LAYER
	p.enable_shadows = true
	p.mesh_lod_threshold = 2.0
	parent.add_child(p)
	p.position = center
	return p


## Re-renders a probe (UPDATE_ONCE probes redraw when a property changes).
static func refresh_probe(p: ReflectionProbe) -> void:
	if is_instance_valid(p):
		p.intensity = p.intensity + (0.0001 if p.intensity < 1.0 else -0.0001)


## A floating holographic interface panel (readouts, graph, gauge). Follows set_power().
static var _holo_ui: ShaderMaterial

static func holo_panel(parent: Node, pos: Vector3, size: Vector2, yaw_deg: float, tint: Color) -> MeshInstance3D:
	if _holo_ui == null:
		_holo_ui = ShaderMaterial.new()
		_holo_ui.shader = preload("res://shaders/holo_ui.gdshader")
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	mi.material_override = _holo_ui
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	return mi


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
