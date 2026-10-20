extends AreaDecor
## The Mushroom Forest: trunks so tall they vanish into a leafy canopy, giant mushrooms,
## glowing plants around a still pool, a hollow log into a hidden fairy-ring glade, and old
## cables leading to the bridge machine.

const CENTER := Vector2(-30, -124)
const GLADE := Vector2(-80, -118)

var _glow_lights: Array[OmniLight3D] = []


func _init() -> void:
	area_id = &"forest"
	scatter_seed = 202


func build_landmarks() -> void:
	# Giant trunks around the forest rim and a few inside.
	var trunks := [
		Vector2(-62, -78), Vector2(-74, -98), Vector2(-86, -140), Vector2(-74, -166), Vector2(-50, -178),
		Vector2(10, -96), Vector2(22, -122), Vector2(20, -150), Vector2(-4, -78), Vector2(28, -178),
		Vector2(-58, -96), Vector2(-14, -142), Vector2(-56, -150), Vector2(4, -128),
	]
	for i in trunks.size():
		var t: Vector2 = trunks[i]
		if WorldTerrain.path_query_fast(t).x < 11.0:
			continue
		place("tree_trunk_a" if i % 3 != 2 else "tree_trunk_b", t.x, t.y, i * 47.0, rng.randf_range(0.85, 1.15), true, -0.5)
	_canopy()

	# Mushroom staircase to a fragment on the tallest cap.
	place("mushroom_step", -52.1, -94.3, 0.0, 0.5, true, 0.0, 1.5)
	place("mushroom_step", -49.8, -95.6, 30.0, 0.85, true, 0.0, 2.0)
	place("mushroom_step", -50.5, -99.4, 60.0, 1.2, true, 0.0, 2.5)
	place("mushroom_step", -55.0, -101.0, 90.0, 1.5, true, 0.0, 3.0)

	# Hollow log: the only easy way into the fairy-ring glade.
	place("log_hollow", -62.0, -128.0, 0.0, 1.0, true, 0.0, 8.0)
	_glade()

	# Glowing pool.
	var pool := Vector2(-8, -118)
	for i in 10:
		var a := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
		var p := pool + Vector2(cos(a), sin(a)) * rng.randf_range(11.0, 13.5)
		if point_ok(p.x, p.y, 3.5):
			if i % 2 == 0:
				place("glow_bulb", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.9, 1.4), false, 0.0, 1.0)
			else:
				place("mushroom_glow", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.9, 1.3), false, 0.0, 1.0)

	# Soft light pools from the glowing plants: dim while dormant, bright once restored.
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var lp := pool + Vector2(cos(a), sin(a)) * 12.0
		var light := OmniLight3D.new()
		light.light_color = Color(0.45, 1.0, 0.8)
		light.omni_range = 9.0
		light.shadow_enabled = false
		add_child(light)
		light.global_position = WorldTerrain.point_on_ground(lp.x, lp.y, 1.6)
		_glow_lights.append(light)
	_set_glow(1.0 if GameState.has_flag(&"bridge_raised") else 0.0)
	GameState.flag_changed.connect(func(flag: StringName, value: Variant) -> void:
		if flag == &"bridge_raised" and value:
			var tween := create_tween()
			tween.tween_interval(3.0)
			tween.tween_method(_set_glow, 0.0, 1.0, 4.0))

	# Root arches over the path and giant mushrooms marking the way.
	_arch_over_path(166.0)
	_arch_over_path(226.0)
	place("mushroom_red", -26.0, -100.0, 40.0, 1.0)
	place("mushroom_red", -48.0, -122.0, 100.0, 0.85)
	place("mushroom_tan", -20.0, -150.0, 200.0, 1.0)
	place("mushroom_red", -2.0, -166.0, 300.0, 1.1)
	place("mushroom_tan", -36.0, -78.0, 20.0, 0.9)
	place("mushroom_red_small", -10.0, -96.0, 70.0, 1.0)
	place("mushroom_red_small", -46.0, -146.0, 10.0, 1.1)
	place("pipe_segment", -15.0, -191.5, 80.0, 1.0, true, -0.6, 4.0)
	place("twig_a", 12.0, -110.0, 120.0, 1.1, true, -0.1, 7.0)
	place("rock_moss_b", -70.0, -150.0, 0.0, 1.1)
	place("rock_moss_a", 14.0, -160.0, 40.0, 0.9)


func build_scatter() -> void:
	for i in 26:
		var p := random_in_circle(CENTER, 58.0)
		if point_ok(p.x, p.y, 7.0, 9999.0, 0.75, 2.0) and claim_spacing("bigmush", p.x, p.y, 10.0):
			var kind := "mushroom_red" if rng.randf() < 0.45 else ("mushroom_tan" if rng.randf() < 0.6 else "mushroom_red_small")
			add_instance(kind, p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.2), 0.0, 320.0, "trimesh")
	for i in 70:
		var p := random_in_circle(CENTER, 60.0)
		if point_ok(p.x, p.y, 3.4) and claim_spacing("fern", p.x, p.y, 2.6):
			add_instance("fern_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.7, 1.4), 0.0, 110.0)
	for i in 45:
		var p := random_in_circle(CENTER, 60.0)
		if point_ok(p.x, p.y, 3.2) and claim_spacing("cluster", p.x, p.y, 3.5):
			add_instance("mushroom_cluster", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.4), 0.0, 110.0)
	# Glow mushrooms trace the path edges: dim while dormant, a lit trail once restored.
	for i in 40:
		var p := random_near_path(140.0, 290.0, 3.4, 7.0)
		if point_ok(p.x, p.y, 3.2) and claim_spacing("glow", p.x, p.y, 4.0):
			add_instance("mushroom_glow", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.1), 0.0, 140.0)
	for i in 20:
		var p := random_in_circle(CENTER, 58.0)
		if point_ok(p.x, p.y, 5.0, 9999.0, 0.7, 1.0) and claim_spacing("rock", p.x, p.y, 7.0):
			add_instance("rock_moss_a" if rng.randf() < 0.6 else "rock_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.2), -0.15, 240.0, "convex")


func _set_glow(level: float) -> void:
	for light in _glow_lights:
		light.light_energy = 0.15 + 1.1 * level


func _canopy() -> void:
	# Huge leaves high overhead: dappled shade on the forest floor.
	for i in 46:
		var p := random_in_circle(CENTER, 64.0)
		var leaf := PropLibrary.instance("canopy_leaf")
		add_child(leaf)
		var ground := WorldTerrain.height_at_world(p.x, p.y)
		leaf.global_position = Vector3(p.x, ground + rng.randf_range(24.0, 36.0), p.y)
		leaf.rotation = Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25))
		leaf.scale = Vector3.ONE * rng.randf_range(2.0, 3.0)


func _glade() -> void:
	var opening := Vector2(-69, -128)
	var open_angle := (opening - GLADE).angle()
	for i in 9:
		var a := TAU * i / 9.0
		if absf(wrapf(a - open_angle, -PI, PI)) < 0.45:
			continue
		var p := GLADE + Vector2(cos(a), sin(a)) * 12.5
		place("rock_c" if i % 2 == 0 else "rock_moss_b", p.x, p.y, rng.randf() * 360.0, rng.randf_range(1.35, 1.6), true, -0.4, 0.0)
	# The fairy ring itself.
	for i in 12:
		var a := TAU * i / 12.0
		var p := GLADE + Vector2(cos(a), sin(a)) * 4.2
		place("mushroom_glow" if i % 2 == 0 else "mushroom_cluster", p.x, p.y, rng.randf() * 360.0, 0.9, false, 0.0, 0.0)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.85)
	glow.light_energy = 1.0
	glow.omni_range = 8.0
	add_child(glow)
	glow.global_position = WorldTerrain.point_on_ground(GLADE.x, GLADE.y, 1.2)
	exclude(GLADE.x, GLADE.y, 14.0)


func _arch_over_path(distance_along: float) -> void:
	var p := WorldLayout.path_point_at(distance_along)
	var ahead := WorldLayout.path_point_at(distance_along + 1.0)
	var dir := (ahead - p).normalized()
	var yaw := rad_to_deg(atan2(dir.x, dir.y))
	place("root_arch", p.x, p.y, yaw, 1.15, true, -0.2, 0.0)
