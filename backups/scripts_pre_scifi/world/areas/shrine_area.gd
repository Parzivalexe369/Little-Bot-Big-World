extends AreaDecor
## The Forgotten Shrine: a plateau of ruins around a dormant core. Colonnades line the climb,
## lanterns ring the plaza, statues of little caretakers keep watch. Restoration lights the
## lanterns, starts the waterfall and opens the great door north into the garden.

const CORE := Vector2(30, -269)

var _lantern_lights: Array[OmniLight3D] = []
var _lanterns: Array[Node3D] = []


func _init() -> void:
	area_id = &"shrine"
	scatter_seed = 303


func build_landmarks() -> void:
	_build_plaza()
	# Colonnade along the ramp from the bridge up to the plaza.
	var s := 318.0
	var i := 0
	while s < 352.0:
		var p := WorldLayout.path_point_at(s)
		var ahead := WorldLayout.path_point_at(s + 1.0)
		var dir := (ahead - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		for k in [-1.0, 1.0]:
			var q: Vector2 = p + side * k * 5.2
			var broken := (i + int(k)) % 3 == 0
			place("pillar_broken" if broken else "pillar", q.x, q.y, rng.randf() * 20.0, 0.9, true, -0.1, 1.5)
		s += 7.0
		i += 1
	# Entrance arch onto the plaza.
	var ap := WorldLayout.path_point_at(353.0)
	var ad := (WorldLayout.path_point_at(354.0) - ap).normalized()
	place("arch", ap.x, ap.y, rad_to_deg(atan2(ad.x, ad.y)), 1.0, true, -0.1, 0.0)

	# Lanterns ring the plaza; they light when the shrine is restored.
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var p := CORE + Vector2(cos(a), sin(a)) * 9.6
		var lantern := place("stone_lantern", p.x, p.y, rad_to_deg(-a), 1.0, true, 0.0, 1.0)
		_lanterns.append(lantern)
		var light := OmniLight3D.new()
		light.position = Vector3(0, 1.6, 0)
		light.light_color = Color(1.0, 0.76, 0.45)
		light.omni_range = 6.5
		light.light_energy = 0.0
		lantern.add_child(light)
		_lantern_lights.append(light)

	# Caretaker statues facing the core.
	place("robot_statue", 23.0, -277.0, 135.0, 1.0)
	place("robot_statue", 37.0, -277.0, 225.0, 1.0)

	# Hidden chamber walls (the east wall is the HiddenWall device).
	place("wall_full", 8.0, -274.5, 0.0, 1.0, true, 0.0, 0.0)
	place("wall_full", 8.0, -269.5, 0.0, 1.0, true, 0.0, 0.0)
	place("wall_full", 5.5, -272.0, 90.0, 1.0, true, 0.0, 0.0)
	exclude(8.0, -272.0, 5.0)

	# Ruin staircase climbing to nowhere (a fragment waits on top).
	place("stairs", 14.0, -258.0, 180.0, 1.0, true, -0.05, 4.0)

	# The courier's alcove.
	place("wall_full", 37.0, -292.0, 0.0, 1.0, true, 0.0, 0.0)
	place("wall_broken", 34.2, -289.0, 90.0, 0.8, true, 0.0, 0.0)
	place("wall_broken", 39.8, -289.0, 90.0, 0.8, true, 0.0, 0.0)
	exclude(37.0, -289.0, 4.0)

	# Broken walls and fallen pillars scattered around the plateau.
	place("wall_broken", 44.0, -284.0, 30.0, 1.0)
	place("wall_broken", 16.0, -247.0, 75.0, 1.0)
	place("wall_broken", 50.0, -262.0, 100.0, 0.9)
	place("pillar_broken", 46.0, -276.0, 10.0, 1.0)
	place("pillar_broken", 20.0, -287.0, 50.0, 1.0)
	place("pillar", 52.0, -255.0, 0.0, 1.0)

	# Pool rocks around the waterfall basin.
	for k in 6:
		var a := TAU * k / 6.0 + 0.4
		var p := Vector2(47, -275) + Vector2(cos(a), sin(a)) * 7.6
		if point_ok(p.x, p.y, 3.5, 9999.0, 0.5):
			place("rock_moss_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.45, 0.7), true, -0.3, 1.0)

	GameState.flag_changed.connect(_on_flag)
	_set_lanterns(1.0 if GameState.has_flag(&"shrine_restored") else 0.0)


func _build_plaza() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 13.5
	mesh.bottom_radius = 13.8
	mesh.height = 0.5
	mesh.radial_segments = 64
	mesh.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/plaza.gdshader")
	mat.set_shader_parameter("noise_tex", PropLibrary.NOISE_TEX)
	var tex := PropLibrary.TEX_DIR + "sandstone_cracks/sandstone_cracks_%s.jpg"
	mat.set_shader_parameter("stone_albedo", load(tex % "diff"))
	mat.set_shader_parameter("stone_normal", load(tex % "nor"))
	mat.set_shader_parameter("stone_arm", load(tex % "arm"))
	mat.set_shader_parameter("stone_avg_lum", PropLibrary.SCAN_LUM["sandstone_cracks"])
	mat.set_shader_parameter("moss_albedo", load(PropLibrary.TEX_DIR + "mossy_rock/mossy_rock_diff.jpg"))
	var plaza := MeshInstance3D.new()
	plaza.name = "Plaza"
	plaza.mesh = mesh
	plaza.material_override = mat
	plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plaza)
	var c := WorldLayout.SHRINE_PLAZA_CENTER
	plaza.global_position = Vector3(c.x, WorldLayout.SHRINE_PLATEAU_HEIGHT - 0.2, c.y)


func build_scatter() -> void:
	var center: Vector2 = WorldLayout.SHRINE_CENTER
	# Bluebell beds around the plaza bloom with the restoration.
	for i in 36:
		var p := random_in_circle(center, 28.0)
		if point_ok(p.x, p.y, 3.6) and claim_spacing("flower", p.x, p.y, 2.4):
			add_instance("bluebell_a" if rng.randf() < 0.6 else "daisy_b", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.55, 0.85), 0.0, 200.0, "stem")
	for i in 16:
		var p := random_in_circle(center, 30.0)
		if point_ok(p.x, p.y, 4.0, 9999.0, 0.75, 0.5) and claim_spacing("rock", p.x, p.y, 6.0):
			add_instance("rock_moss_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.4, 0.8), -0.15, 200.0, "convex")
	for i in 24:
		var p := random_in_circle(center, 30.0)
		if point_ok(p.x, p.y, 3.2) and claim_spacing("fern", p.x, p.y, 3.0):
			add_instance("fern_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.0), 0.0, 100.0)
	for i in 30:
		var p := random_near_path(300.0, 400.0, 3.0, 6.0)
		if point_ok(p.x, p.y, 2.9) and claim_spacing("pebble", p.x, p.y, 1.6):
			add_instance("pebble", p.x, p.y, rng.randf() * 360.0, rng.randf_range(1.0, 2.2), -0.05, 80.0, "", 20.0)


func _on_flag(flag: StringName, value: Variant) -> void:
	if flag == &"shrine_restored" and value:
		var tween := create_tween()
		tween.tween_interval(1.5)
		tween.tween_method(_set_lanterns, 0.0, 1.0, 3.0)


func _set_lanterns(level: float) -> void:
	for light in _lantern_lights:
		light.light_energy = 1.3 * level
	for lantern in _lanterns:
		PropLibrary.set_power(lantern, level)
