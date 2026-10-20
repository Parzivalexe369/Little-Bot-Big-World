class_name RobotMaterials
extends RefCounted
## Godot-side replacements for robot materials whose Blender node setups do not survive glTF
## (color ramps, Fresnel glass) plus tuned PBR values for the rest. Matched by material name.

const CANDY_SHADER := preload("res://shaders/robot_candy.gdshader")
const GLASS_SHADER := preload("res://shaders/robot_glass.gdshader")
const PEARL_SHADER := preload("res://shaders/robot_pearl.gdshader")
## Render layer for the robot's meshes, so a character light rig can light only the robot
## (and so effects such as ground decals can skip it).
const ROBOT_LAYER := 1 << 10
## Base emission of the per-instance glow materials (scaled by power / boost at runtime).
const VENT_GLOW := 0.0
const LIME_GLOW := 0.9

static var _shared: Dictionary = {}


static func apply(root: Node, glow_out: Dictionary = {}) -> Array[StandardMaterial3D]:
	## Applies overrides to every mesh below root. Returns the per-instance eye materials
	## so the caller can animate their glow. glow_out receives per-instance "vent" and
	## "lime" materials (accents that brighten with power and boost).
	var eye_materials: Array[StandardMaterial3D] = []
	var eye_material: StandardMaterial3D = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(s)
			if source == null:
				continue
			var mat_name := source.resource_name
			if mat_name == "M_EyeGreen":
				if eye_material == null:
					eye_material = _make_eye(Color(0.12, 0.62, 0.14), Color(0.3, 1.0, 0.26))
					eye_materials.append(eye_material)
				mi.set_surface_override_material(s, eye_material)
				continue
			if mat_name == "M_PinkLight" or mat_name == "M_LimeAccent":
				var key := "vent" if mat_name == "M_PinkLight" else "lime"
				if not glow_out.has(key):
					var base := _shared_material(mat_name) as StandardMaterial3D
					var inst := base.duplicate() as StandardMaterial3D
					inst.emission_enabled = true
					if key == "vent":
						inst.emission = Color(1.0, 0.45, 0.75)
						inst.emission_energy_multiplier = VENT_GLOW
					glow_out[key] = inst
				mi.set_surface_override_material(s, glow_out[key])
				continue
			var replacement := _shared_material(mat_name)
			if replacement:
				mi.set_surface_override_material(s, replacement)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return eye_materials


static func _make_eye(albedo: Color, emission: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = 3.0
	return m


static func _shared_material(mat_name: String) -> Material:
	if _shared.has(mat_name):
		return _shared[mat_name]
	var m: Material = null
	match mat_name:
		"M_CandyPink":
			# Slightly warmer than the Blender values so AgX keeps it candy pink, not lilac.
			m = _candy(Color(1.0, 0.27, 0.56), Color(0.86, 0.07, 0.44))
		"BALL_Shell_Yellow":
			m = _candy(Color(1.0, 0.8, 0.3), Color(0.98, 0.55, 0.14))
		"M_BlackGlass", "BALL_Visor_Glass", "TB2_BlackGlass":
			var g := ShaderMaterial.new()
			g.shader = GLASS_SHADER
			g.render_priority = 1
			m = g
		"M_PearlWhite":
			var pearl := ShaderMaterial.new()
			pearl.shader = PEARL_SHADER
			m = pearl
		"M_PinkLight":
			m = _std(Color(1.0, 0.76, 0.9), 0.0, 0.3, 0.6)
		"M_Gunmetal", "BALL_Dark_Metal", "TB2_Gunmetal":
			m = _std(Color(0.33, 0.34, 0.37), 1.0, 0.32, 0.0)
		"M_PolishedSilver", "TB2_Chrome":
			m = _std(Color(0.95, 0.95, 0.96), 1.0, 0.1, 0.0)
		"M_BrushedAlu", "BALL_Aluminum_Brushed", "TB2_HubMetal":
			m = _std(Color(0.88, 0.89, 0.91), 1.0, 0.3, 0.0)
		"M_DisplayBlack", "BALL_Interior_Charcoal", "TB2_DisplayCore":
			m = _std(Color(0.05, 0.05, 0.06), 0.0, 0.15, 0.0)
		"M_LimeAccent":
			var lime := _std(Color(0.74, 0.97, 0.25), 0.0, 0.25, 0.0)
			lime.emission_enabled = true
			lime.emission = Color(0.8, 1.0, 0.25)
			lime.emission_energy_multiplier = 0.9
			m = lime
		"M_InnerPlate":
			m = _std(Color(0.6, 0.61, 0.63), 0.0, 0.35, 0.0)
	_shared[mat_name] = m
	return m


static func _candy(face: Color, edge: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CANDY_SHADER
	m.set_shader_parameter("face_color", Vector3(face.r, face.g, face.b))
	m.set_shader_parameter("edge_color", Vector3(edge.r, edge.g, edge.b))
	return m


static func _std(albedo: Color, metallic: float, roughness: float, clearcoat: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.08
	return m
