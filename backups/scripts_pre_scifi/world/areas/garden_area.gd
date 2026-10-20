extends AreaDecor
## The Crystal Garden: a lavender valley of crystal clusters, glass flowers and reflecting
## pools, watched over by a towering crystal spire. A humming grotto hides a resonator.

const CENTER := Vector2(-6, -398)
const GROTTO := Vector2(-48, -408)


func _init() -> void:
	area_id = &"garden"
	scatter_seed = 404


func build_landmarks() -> void:
	# Landmark spires, visible from the pass as you come down from the shrine.
	place("crystal_spire", -42.0, -462.0, 20.0, 1.0, true, -1.0)
	place("crystal_spire", 44.0, -452.0, 140.0, 0.65, true, -1.0)
	place("crystal_spire", -64.0, -372.0, 260.0, 0.5, true, -1.0)

	# The humming grotto: tall crystals arc around a hollow, open toward the path.
	var open_angle := (Vector2(-30, -404) - GROTTO).angle()
	for i in 11:
		var a := TAU * i / 11.0
		if absf(wrapf(a - open_angle, -PI, PI)) < 0.55:
			continue
		var p := GROTTO + Vector2(cos(a), sin(a)) * rng.randf_range(8.5, 10.0)
		var kind := "crystal_violet_a" if i % 2 == 0 else "crystal_teal_a"
		var node := place(kind, p.x, p.y, rng.randf() * 360.0, rng.randf_range(2.2, 3.0), true, -0.5, 0.0)
		node.rotation.x = deg_to_rad(rng.randf_range(-12, 12))
	var hum_light := OmniLight3D.new()
	hum_light.light_color = Color(0.8, 0.6, 1.0)
	hum_light.light_energy = 1.2
	hum_light.omni_range = 10.0
	add_child(hum_light)
	hum_light.global_position = WorldTerrain.point_on_ground(GROTTO.x, GROTTO.y, 2.5)
	exclude(GROTTO.x, GROTTO.y, 11.0)

	# Stepping stones to a fragment perched above the crystals.
	place("rock_b", 13.5, -354.0, 30.0, 1.6, true, 0.0, 2.5)
	place("rock_moss_a", 16.0, -356.0, 80.0, 0.75, true, 0.0, 3.0)
	place("crystal_pink_a", 18.8, -358.0, 10.0, 0.8, true)

	# Crystal trees beside the path, glowing posts guiding the way down the pass.
	for s in [420.0, 445.0, 470.0, 495.0]:
		var p := random_near_path(s, s + 4.0, 5.0, 7.0)
		place("crystal_tree", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.9, 1.2), true, 0.0, 2.0)
	for k in 9:
		var s2 := 412.0 + k * 11.0
		var p2 := random_near_path(s2, s2 + 1.0, 3.3, 3.6)
		place("crystal_small", p2.x, p2.y, rng.randf() * 360.0, 0.8, false, 0.0, 0.6)


func build_scatter() -> void:
	var kinds := ["crystal_violet_a", "crystal_teal_a", "crystal_pink_a"]
	for i in 60:
		var p := random_in_circle(CENTER, 62.0)
		if point_ok(p.x, p.y, 6.0, 9999.0, 0.72, 1.5) and claim_spacing("cluster", p.x, p.y, 7.0):
			add_instance(kinds[rng.randi() % kinds.size()], p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.5), -0.2, 300.0, "convex", 12.0)
	for i in 120:
		var p := random_in_circle(CENTER, 64.0)
		if point_ok(p.x, p.y, 3.4) and claim_spacing("small", p.x, p.y, 2.0):
			add_instance("crystal_small", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.5, 1.2), -0.1, 120.0, "", 20.0)
	for i in 60:
		var p := random_in_circle(CENTER, 60.0)
		if point_ok(p.x, p.y, 3.8) and claim_spacing("flower", p.x, p.y, 2.6):
			add_instance("glass_flower", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.7, 1.15), 0.0, 200.0, "stem")
	for i in 14:
		var p := random_in_circle(CENTER, 62.0)
		if point_ok(p.x, p.y, 8.0, 9999.0, 0.75, 2.0) and claim_spacing("tree", p.x, p.y, 12.0):
			add_instance("crystal_tree", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.8, 1.4), 0.0, 300.0, "convex")
	for i in 16:
		var p := random_in_circle(CENTER, 62.0)
		if point_ok(p.x, p.y, 5.0, 9999.0, 0.7, 1.0) and claim_spacing("rock", p.x, p.y, 7.0):
			add_instance("rock_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.5, 1.0), -0.15, 240.0, "convex")
