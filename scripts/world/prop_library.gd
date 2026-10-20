class_name PropLibrary
extends RefCounted
## Access to the environment props modeled in tools/blender/build_props.py.
## Loads props.glb once, swaps Blender materials for Godot shaders (by material name),
## and hands out instances, meshes and cached collision shapes.

const PROPS_SCENE := "res://assets/environment/props.glb"
const FOLIAGE := preload("res://shaders/foliage.gdshader")
const ENVIRONMENT := preload("res://shaders/environment.gdshader")
const CRYSTAL := preload("res://shaders/crystal.gdshader")
const DEVICE := preload("res://shaders/emissive_device.gdshader")
const NOISE_TEX := preload("res://materials/noise_tex.tres")
## Photoscanned surface sets (Poly Haven CC0, see assets/textures/CREDITS.txt) and their mean
## linear luminance, used when a material only borrows a scan's detail and keeps its own color.
const TEX_DIR := "res://assets/textures/"
const SCAN_LUM := {
	"bark_brown_02": 0.103, "dark_rock": 0.013, "mossy_rock": 0.15, "rock_boulder_dry": 0.348,
	"rough_wood": 0.13, "rusty_metal_02": 0.308, "rusty_painted_metal": 0.078, "sandstone_cracks": 0.421,
}

## Collision used when a prop is placed with collision = true.
const COLLISION := {
	"rock_a": "convex", "rock_b": "convex", "rock_c": "convex", "rock_moss_a": "convex", "rock_moss_b": "convex",
	"twig_a": "trimesh", "watering_can": "trimesh", "charging_station": "convex", "root_gate": "trimesh",
	"power_pylon": "convex", "plant_stake": "convex",
	"mushroom_red": "trimesh", "mushroom_red_small": "trimesh", "mushroom_tan": "trimesh", "mushroom_step": "trimesh",
	"tree_trunk_a": "trimesh", "tree_trunk_b": "trimesh", "root_arch": "trimesh", "log_hollow": "trimesh",
	"bridge_machine": "convex", "valve_switch": "convex", "pipe_segment": "trimesh",
	"pillar": "convex", "pillar_broken": "trimesh", "arch": "trimesh", "wall_broken": "trimesh", "wall_full": "convex",
	"stairs": "trimesh", "shrine_core": "trimesh", "power_node": "convex", "mirror_pedestal": "convex",
	"sun_emitter": "convex", "stone_lantern": "convex", "robot_statue": "convex", "great_door": "trimesh",
	"lore_tablet": "convex", "falls_rock": "trimesh", "melody_stone": "convex", "crystal_heart": "trimesh",
	"crystal_violet_a": "convex", "crystal_teal_a": "convex", "crystal_pink_a": "convex", "crystal_spire": "trimesh",
	"crystal_tree": "convex", "resonator": "convex", "singing_crystal": "convex", "junction_straight": "convex",
	"junction_elbow": "convex", "conduit": "convex",
	"daisy_a": "stem", "daisy_b": "stem", "daisy_pink": "stem", "sunflower": "stem", "tulip_a": "stem",
	"dandelion_a": "stem", "bluebell_a": "stem",
}

static var _root: Node3D
static var _templates: Dictionary = {}
static var _materials: Dictionary = {}
static var _shapes: Dictionary = {}


static func ensure_loaded() -> void:
	if _root != null:
		return
	var packed := load(PROPS_SCENE) as PackedScene
	if packed == null:
		push_error("PropLibrary: could not load %s" % PROPS_SCENE)
		_root = Node3D.new()
		return
	_root = packed.instantiate() as Node3D
	for child in _root.get_children():
		_templates[String(child.name)] = child
		for mi in [child] + child.find_children("*", "MeshInstance3D", true, false):
			if mi is MeshInstance3D:
				_apply_materials(mi as MeshInstance3D)


static func has_prop(prop: String) -> bool:
	ensure_loaded()
	return _templates.has(prop)


## A fresh node tree for the prop (moving parts are named children).
static func instance(prop: String) -> Node3D:
	ensure_loaded()
	var template: Node3D = _templates.get(prop)
	if template == null:
		push_warning("PropLibrary: unknown prop '%s'" % prop)
		return Node3D.new()
	var node := template.duplicate() as Node3D
	node.transform = Transform3D.IDENTITY
	return node


## The mesh of a single-mesh prop (used for MultiMesh scatter).
static func mesh(prop: String) -> Mesh:
	ensure_loaded()
	var template: Node3D = _templates.get(prop)
	if template is MeshInstance3D:
		return (template as MeshInstance3D).mesh
	if template:
		for mi in template.find_children("*", "MeshInstance3D", true, false):
			return (mi as MeshInstance3D).mesh
	return null


## Places a prop with optional static collision. Returns the prop node.
static func place(parent: Node, prop: String, pos: Vector3, yaw_deg: float = 0.0, scale: float = 1.0, collision: bool = true) -> Node3D:
	var node := instance(prop)
	parent.add_child(node)
	node.position = pos
	node.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	node.scale = Vector3.ONE * scale
	if collision:
		add_collision(node, prop)
	if OS.has_feature("web"):
		_limit_draw_distance(node, scale)
	return node


## Browsers: a prop stops drawing beyond a distance that grows with its size (flowers ~45 m,
## big rocks ~60 m, trunks and giant mushrooms up to 160 m). Every drawn object is a WebGL
## draw call, and distant props made up most of the garden's ~2,500 a frame.
static func _limit_draw_distance(node: Node3D, scale: float) -> void:
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	var size := 0.0
	for mi: MeshInstance3D in meshes:
		if mi.mesh:
			size = maxf(size, mi.mesh.get_aabb().size.length())
	var view_range := clampf(20.0 + size * scale * 8.0, 45.0, 160.0)
	for mi: MeshInstance3D in meshes:
		mi.visibility_range_end = view_range
		mi.visibility_range_end_margin = view_range * 0.1


## root_only skips moving child parts (devices give those their own colliders).
static func add_collision(node: Node3D, prop: String, root_only: bool = false) -> StaticBody3D:
	var mode: String = COLLISION.get(prop, "")
	if mode == "":
		return null
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	if mode == "stem":
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.16
		cyl.height = 3.0
		cs.shape = cyl
		cs.position = Vector3(0.0, 1.5, 0.0)
		body.add_child(cs)
		return body
	# One shape per mesh in the prop (moving parts keep their own transform).
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	if not root_only or meshes.is_empty():
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			meshes.append(mi as MeshInstance3D)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var key := "%s:%s:%s" % [prop, mi.name, mode]
		var shape: Shape3D = _shapes.get(key)
		if shape == null:
			shape = mi.mesh.create_trimesh_shape() if mode == "trimesh" else mi.mesh.create_convex_shape(true, true)
			_shapes[key] = shape
		var cs2 := CollisionShape3D.new()
		cs2.shape = shape
		body.add_child(cs2)
		if mi != node:
			cs2.transform = _relative_transform(node, mi)
	return body


static func _relative_transform(root: Node3D, child: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = child
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Sets the "power" instance uniform on every device-glow surface below node.
static func set_power(node: Node, value: float) -> void:
	var targets: Array = [node] + node.find_children("*", "GeometryInstance3D", true, false)
	for g in targets:
		if g is GeometryInstance3D:
			(g as GeometryInstance3D).set_instance_shader_parameter(&"power", value)


static func material(mat_name: String) -> Material:
	if _materials.has(mat_name):
		return _materials[mat_name]
	var m := _create_material(mat_name)
	_materials[mat_name] = m
	return m


static func _apply_materials(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var source := mi.mesh.surface_get_material(s)
		var name := source.resource_name if source else ""
		var replacement := material(name)
		if replacement:
			mi.mesh.surface_set_material(s, replacement)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _foliage(color: Color, dormant: Color, amp: float, stiffness: float, backlight: float = 0.35, push: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE
	m.set_shader_parameter("albedo_color", _v3(color))
	m.set_shader_parameter("dormant_color", _v3(dormant))
	m.set_shader_parameter("wind_amplitude", amp)
	m.set_shader_parameter("wind_stiffness", stiffness)
	m.set_shader_parameter("backlight_amount", backlight)
	m.set_shader_parameter("player_push", push)
	return m


static func _env(c1: Color, c2: Color, rough: float = 0.9, metal: float = 0.0, moss: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENVIRONMENT
	m.set_shader_parameter("albedo_color", _v3(c1))
	m.set_shader_parameter("albedo_color_2", _v3(c2))
	m.set_shader_parameter("roughness_value", rough)
	m.set_shader_parameter("metallic_value", metal)
	m.set_shader_parameter("moss_amount", moss)
	m.set_shader_parameter("noise_tex", NOISE_TEX)
	if moss > 0.0:
		m.set_shader_parameter("use_moss_texture", true)
		m.set_shader_parameter("moss_albedo", load(TEX_DIR + "mossy_rock/mossy_rock_diff.jpg"))
		m.set_shader_parameter("moss_normal", load(TEX_DIR + "mossy_rock/mossy_rock_nor.jpg"))
	return m


## Adds a scan to an environment material. photo 1 = the scan's colors (times tint),
## 0 = the material's own palette modulated by the scan's luminance detail.
static func _scan(m: ShaderMaterial, set_name: String, scale: float, photo: float, tint := Color.WHITE,
		normal_strength := 1.0, rough_mix := 1.0, metal_mix := 0.0) -> ShaderMaterial:
	m.set_shader_parameter("use_textures", true)
	m.set_shader_parameter("tex_albedo", load(TEX_DIR + "%s/%s_diff.jpg" % [set_name, set_name]))
	m.set_shader_parameter("tex_normal", load(TEX_DIR + "%s/%s_nor.jpg" % [set_name, set_name]))
	m.set_shader_parameter("tex_arm", load(TEX_DIR + "%s/%s_arm.jpg" % [set_name, set_name]))
	m.set_shader_parameter("tex_avg_lum", SCAN_LUM[set_name])
	m.set_shader_parameter("tex_scale", scale)
	m.set_shader_parameter("tex_photo", photo)
	m.set_shader_parameter("tex_tint", _v3(tint))
	m.set_shader_parameter("tex_normal_strength", normal_strength)
	m.set_shader_parameter("tex_rough_mix", rough_mix)
	m.set_shader_parameter("tex_metal_mix", metal_mix)
	return m


static func _crystal(core: Color, edge: Color, energy: float = 1.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CRYSTAL
	m.set_shader_parameter("core_color", _v3(core))
	m.set_shader_parameter("edge_color", _v3(edge))
	m.set_shader_parameter("glow_energy", energy)
	m.set_shader_parameter("noise_tex", NOISE_TEX)
	return m


static func _device(glow: Color, energy: float = 3.0, flow: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DEVICE
	m.set_shader_parameter("glow_color", _v3(glow))
	m.set_shader_parameter("glow_energy", energy)
	m.set_shader_parameter("flow_speed", flow)
	return m


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Frees the cached prop scene (called on exit so nothing is reported as leaked).
static func release() -> void:
	if _root != null:
		_root.free()
		_root = null
	_templates.clear()
	_materials.clear()
	_shapes.clear()


static func _create_material(mat_name: String) -> Material:
	match mat_name:
		"grass":
			var grass := _foliage(Color(0.36, 0.54, 0.18), Color(0.5, 0.56, 0.38), 0.5, 0.7, 0.45, 1.0)
			grass.set_shader_parameter("dormant_mix", 0.45)
			grass.set_shader_parameter("use_area_tint", true)
			grass.set_shader_parameter("variation", 0.32)
			grass.set_shader_parameter("normal_up_bias", 0.28)
			grass.set_shader_parameter("tip_gradient", 0.5)
			grass.set_shader_parameter("dry_amount", 0.55)
			grass.set_shader_parameter("roughness_value", 0.5)
			return grass
		"grass_tall":
			var tall := _foliage(Color(0.34, 0.52, 0.18), Color(0.5, 0.55, 0.38), 0.8, 0.8, 0.45, 0.6)
			tall.set_shader_parameter("dormant_mix", 0.45)
			tall.set_shader_parameter("use_area_tint", true)
			tall.set_shader_parameter("variation", 0.32)
			tall.set_shader_parameter("normal_up_bias", 0.25)
			tall.set_shader_parameter("tip_gradient", 0.5)
			tall.set_shader_parameter("dry_amount", 0.7)
			tall.set_shader_parameter("roughness_value", 0.5)
			return tall
		"stem":
			return _foliage(Color(0.36, 0.6, 0.2), Color(0.55, 0.55, 0.36), 0.35, 1.2)
		"leaf":
			var leaf := _foliage(Color(0.36, 0.62, 0.2), Color(0.58, 0.56, 0.34), 0.45, 0.8, 0.4, 1.0)
			leaf.set_shader_parameter("normal_up_bias", 0.35)
			leaf.set_shader_parameter("tip_gradient", 0.4)
			return leaf
		"leaf_dark":
			return _foliage(Color(0.2, 0.42, 0.16), Color(0.32, 0.34, 0.22), 0.6, 1.5, 0.5)
		"leaf_fern":
			return _foliage(Color(0.27, 0.52, 0.18), Color(0.36, 0.38, 0.24), 0.4, 1.0, 0.4, 0.6)
		"leaf_dry":
			var dry := _foliage(Color(0.34, 0.23, 0.12), Color(0.36, 0.3, 0.22), 0.0, 1.0, 0.3)
			dry.set_shader_parameter("variation", 0.35)
			dry.set_shader_parameter("near_fade_start", 0.0)
			dry.set_shader_parameter("near_fade_end", 0.01)
			return dry
		"leaf_clover":
			return _foliage(Color(0.3, 0.58, 0.22), Color(0.5, 0.52, 0.34), 0.2, 1.0, 0.4, 1.0)
		"petal_white":
			return _foliage(Color(0.97, 0.96, 0.92), Color(0.78, 0.76, 0.66), 0.35, 1.2, 0.5)
		"petal_pink":
			return _foliage(Color(1.0, 0.62, 0.8), Color(0.75, 0.62, 0.62), 0.35, 1.2, 0.5)
		"petal_red":
			return _foliage(Color(0.95, 0.3, 0.36), Color(0.62, 0.42, 0.38), 0.35, 1.2, 0.5)
		"petal_blue":
			return _foliage(Color(0.5, 0.6, 1.0), Color(0.55, 0.56, 0.62), 0.35, 1.2, 0.5)
		"petal_yellow":
			return _foliage(Color(1.0, 0.84, 0.3), Color(0.72, 0.64, 0.4), 0.35, 1.2, 0.5)
		"flower_center":
			return _foliage(Color(1.0, 0.72, 0.18), Color(0.62, 0.52, 0.3), 0.35, 1.2, 0.3)
		"seed_fluff":
			var fluff := _foliage(Color(0.96, 0.96, 0.92), Color(0.82, 0.8, 0.74), 0.3, 1.4, 0.7)
			fluff.set_shader_parameter("emission_amount", 0.12)
			return fluff
		"glass_petal":
			var glass := _foliage(Color(0.72, 0.85, 1.0), Color(0.6, 0.62, 0.68), 0.25, 1.4, 0.8)
			glass.set_shader_parameter("emission_amount", 0.35)
			glass.set_shader_parameter("roughness_value", 0.15)
			return glass
		"rock":
			return _scan(_env(Color(0.6, 0.58, 0.54), Color(0.44, 0.42, 0.4), 0.9, 0.0, 0.35),
				"rock_boulder_dry", 0.32, 1.0, Color(0.95, 0.97, 1.02))
		"moss":
			var moss := _env(Color(0.34, 0.52, 0.2), Color(0.26, 0.42, 0.16), 0.95, 0.0, 1.0)
			return _scan(moss, "mossy_rock", 0.45, 1.0, Color(1.05, 1.1, 0.95))
		"bark":
			return _scan(_env(Color(0.42, 0.32, 0.24), Color(0.3, 0.22, 0.17), 0.95, 0.0, 0.25),
				"bark_brown_02", 0.3, 1.0, Color(1.12, 1.05, 1.0), 1.2)
		"wood":
			return _scan(_env(Color(0.6, 0.46, 0.3), Color(0.48, 0.36, 0.24), 0.85, 0.0, 0.0),
				"rough_wood", 0.5, 0.55, Color(1.35, 1.2, 1.0))
		"wood_painted":
			return _scan(_env(Color(0.88, 0.84, 0.7), Color(0.7, 0.66, 0.54), 0.8, 0.0, 0.1),
				"rough_wood", 0.5, 0.0, Color.WHITE, 0.6, 0.5)
		"mushroom_stem":
			return _scan(_env(Color(0.94, 0.9, 0.8), Color(0.84, 0.78, 0.68), 0.8),
				"rough_wood", 0.35, 0.0, Color.WHITE, 0.3, 0.3)
		"mushroom_cap_red":
			return _scan(_env(Color(0.86, 0.22, 0.16), Color(0.7, 0.16, 0.12), 0.55),
				"rock_boulder_dry", 0.4, 0.0, Color.WHITE, 0.25, 0.2)
		"mushroom_cap_tan":
			return _scan(_env(Color(0.76, 0.58, 0.38), Color(0.62, 0.46, 0.3), 0.6),
				"rock_boulder_dry", 0.4, 0.0, Color.WHITE, 0.3, 0.2)
		"mushroom_cap_glow":
			var glow := _env(Color(0.36, 0.86, 0.92), Color(0.3, 0.7, 0.8), 0.4)
			glow.set_shader_parameter("emission_color", Vector3(0.3, 0.95, 1.0))
			glow.set_shader_parameter("emission_energy", 2.2)
			glow.set_shader_parameter("emission_dormant", 0.12)
			return glow
		"mushroom_gill":
			return _env(Color(0.86, 0.76, 0.6), Color(0.76, 0.66, 0.5), 0.9)
		"mushroom_spot":
			return _env(Color(0.98, 0.96, 0.92), Color(0.9, 0.88, 0.84), 0.7)
		"glow_bulb":
			var bulb := _env(Color(0.6, 1.0, 0.72), Color(0.5, 0.9, 0.62), 0.35)
			bulb.set_shader_parameter("emission_color", Vector3(0.5, 1.0, 0.6))
			bulb.set_shader_parameter("emission_energy", 2.6)
			bulb.set_shader_parameter("emission_dormant", 0.1)
			return bulb
		"stone":
			return _scan(_env(Color(0.68, 0.66, 0.6), Color(0.54, 0.52, 0.48), 0.9, 0.0, 0.3),
				"sandstone_cracks", 0.35, 0.2, Color(0.62, 0.78, 0.98))
		"stone_dark":
			return _scan(_env(Color(0.44, 0.44, 0.45), Color(0.34, 0.34, 0.36), 0.85, 0.0, 0.25),
				"dark_rock", 0.4, 0.0)
		"stone_carved":
			return _scan(_env(Color(0.76, 0.72, 0.64), Color(0.64, 0.6, 0.54), 0.85, 0.0, 0.15),
				"sandstone_cracks", 0.4, 0.15, Color(0.7, 0.82, 1.0))
		"metal_rust":
			return _scan(_env(Color(0.58, 0.36, 0.22), Color(0.4, 0.24, 0.16), 0.75, 0.35, 0.1),
				"rusty_metal_02", 0.6, 1.0, Color.WHITE, 1.0, 1.0, 1.0)
		"metal_paint":
			return _scan(_env(Color(0.32, 0.62, 0.6), Color(0.5, 0.36, 0.26), 0.6, 0.2),
				"rusty_painted_metal", 0.6, 0.0, Color.WHITE, 1.0, 0.8, 0.6)
		"metal_cream":
			return _scan(_env(Color(0.92, 0.88, 0.78), Color(0.84, 0.8, 0.7), 0.45, 0.15),
				"rusty_painted_metal", 0.6, 0.0, Color.WHITE, 0.7, 0.6, 0.4)
		"metal_dark":
			return _scan(_env(Color(0.26, 0.27, 0.3), Color(0.2, 0.21, 0.24), 0.4, 0.8),
				"rusty_metal_02", 0.6, 0.0, Color.WHITE, 0.6, 0.5, 0.0)
		"metal_gold":
			return _env(Color(0.92, 0.74, 0.4), Color(0.78, 0.6, 0.3), 0.3, 1.0)
		"rubber":
			return _env(Color(0.12, 0.12, 0.13), Color(0.1, 0.1, 0.11), 0.7)
		"mirror":
			var mirror := StandardMaterial3D.new()
			mirror.albedo_color = Color(0.95, 0.96, 0.98)
			mirror.metallic = 1.0
			mirror.roughness = 0.03
			return mirror
		"screen":
			return _device(Color(0.4, 1.0, 0.8), 1.4, 0.0)
		"energy":
			return _device(Color(0.35, 0.95, 1.0), 3.2, 0.0)
		"conduit_line":
			return _device(Color(0.35, 0.95, 1.0), 3.0, 4.0)
		"lantern_glow":
			return _device(Color(1.0, 0.78, 0.45), 3.4, 0.0)
		"crystal_violet":
			return _crystal(Color(0.5, 0.32, 0.92), Color(0.86, 0.76, 1.0))
		"crystal_teal":
			return _crystal(Color(0.2, 0.75, 0.8), Color(0.75, 1.0, 0.98))
		"crystal_pink":
			return _crystal(Color(0.9, 0.4, 0.7), Color(1.0, 0.8, 0.92))
		"crystal_core":
			return _crystal(Color(0.3, 0.8, 1.0), Color(0.85, 1.0, 1.0), 2.0)
		"crystal_heart":
			return _crystal(Color(0.95, 0.45, 0.85), Color(1.0, 0.85, 0.98), 2.4)
		"crystal_sun":
			return _crystal(Color(1.0, 0.75, 0.35), Color(1.0, 0.95, 0.8), 2.0)
		"fragment":
			return _crystal(Color(0.3, 0.9, 1.0), Color(0.9, 1.0, 1.0), 2.6)
	return null
