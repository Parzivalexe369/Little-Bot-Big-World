extends AreaDecor
## The Quiet Meadow: oversized flowers, a pond, the abandoned dock, a giant's watering can
## and the path that winds north to the old gate.


func _init() -> void:
	area_id = &"meadow"
	scatter_seed = 101


func build_landmarks() -> void:
	# Stepping stones up to a fragment on the big mossy boulder.
	place("rock_b", 23.2, 4.6, 20.0, 1.6, true, 0.0, 2.5)
	place("rock_moss_a", 26.0, 2.0, 70.0, 0.75, true, 0.0, 3.0)
	place("rock_c", 31.0, -3.0, 140.0, 0.9)
	place("rock_a", 19.0, 9.0, 10.0, 1.0)

	# The giant's watering can, half sunk, open end facing the path. A secret inside.
	place("watering_can", 40.0, 28.0, 180.0, 1.0, true, -0.6, 9.0)
	var can_light := OmniLight3D.new()
	can_light.light_color = Color(1.0, 0.75, 0.45)
	can_light.light_energy = 0.9
	can_light.omni_range = 5.0
	add_child(can_light)
	can_light.global_position = WorldTerrain.point_on_ground(41.0, 28.0, 1.8)
	place("mushroom_glow", 42.6, 27.0, 0.0, 0.7, false, 0.0, 0.0)

	place("twig_a", -22.0, -22.0, 30.0, 1.0, true, -0.1, 7.0)
	place("plant_stake", 15.0, 41.0, -20.0, 1.0)
	place("pipe_segment", -46.0, 10.0, 60.0, 1.0, true, -0.5, 5.0)

	# Tall beacons: dandelions mid-meadow, sunflowers framing the gate at the path's end.
	place("dandelion_a", 13.0, 22.0, 0.0, 1.3)
	place("dandelion_a", -32.0, -30.0, 90.0, 1.1)
	place("sunflower", -13.0, -45.0, 30.0, 1.0)
	place("sunflower", 9.5, -44.0, -40.0, 1.15)
	place("sunflower", -17.0, -38.0, 160.0, 0.9)
	place("sunflower", 24.0, 46.0, 10.0, 0.85)

	# Flowers welcoming the robot around the dock.
	place("daisy_a", -4.0, 63.0, 10.0, 0.9)
	place("tulip_a", 5.0, 62.5, 80.0, 0.8)
	place("daisy_pink", -6.0, 56.0, 200.0, 0.85)
	place("bluebell_a", 6.5, 55.0, 250.0, 0.9)

	# Pond: lily pads and big rounded stones.
	_lily_pads(Vector2(-30, 30), 8.0, 14)
	place("rock_moss_a", -40.5, 31.0, 0.0, 0.8)
	place("rock_b", -23.5, 37.0, 60.0, 1.2)

	# Boulders and mossy giants near the meadow's rim.
	place("rock_moss_b", -50.0, -14.0, 30.0, 1.2)
	place("rock_moss_b", 52.0, -10.0, 200.0, 1.0)
	place("rock_c", 46.0, 48.0, 75.0, 1.1)
	place("rock_c", -44.0, 52.0, 300.0, 1.2)


func build_scatter() -> void:
	var flowers := ["daisy_a", "daisy_a", "daisy_b", "daisy_pink", "tulip_a", "bluebell_a"]
	var center: Vector2 = WorldLayout.AREAS[&"meadow"]["center"]
	# Clusters of flowers, denser close to the path so the walk feels framed.
	for c in 34:
		var cc := random_near_path(5.0, 122.0, 6.0, 26.0) if c < 22 else random_in_circle(center, 56.0)
		var kind: String = flowers[rng.randi() % flowers.size()]
		for k in rng.randi_range(3, 6):
			var p := cc + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))
			if not point_ok(p.x, p.y, 4.0) or not claim_spacing("flower", p.x, p.y, 2.2):
				continue
			var s := rng.randf_range(0.7, 1.15)
			add_instance(kind if rng.randf() < 0.7 else flowers[rng.randi() % flowers.size()], p.x, p.y, rng.randf() * 360.0, s, 0.0, 220.0, "stem")
	# Pebbles and small rocks along the path edges.
	for i in 60:
		var p := random_near_path(0.0, 125.0, 3.0, 7.0)
		if point_ok(p.x, p.y, 2.9) and claim_spacing("pebble", p.x, p.y, 1.5):
			add_instance("pebble" if rng.randf() < 0.7 else "rock_b", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.8, 1.8), -0.05, 90.0, "", 15.0)
	# Bigger rocks scattered across the field.
	for i in 18:
		var p := random_in_circle(center, 60.0)
		if point_ok(p.x, p.y, 6.0, 9999.0, 0.75, 1.0) and claim_spacing("rock", p.x, p.y, 8.0):
			add_instance("rock_a" if rng.randf() < 0.6 else "rock_moss_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.1), -0.1, 260.0, "convex")
	# A few mushroom clusters in damp corners and ferns by the pond.
	for i in 10:
		var p := random_in_circle(center, 58.0)
		if point_ok(p.x, p.y, 5.0) and claim_spacing("mush", p.x, p.y, 6.0):
			add_instance("mushroom_cluster", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.6, 1.0), 0.0, 120.0)
	for i in 10:
		var p := random_in_circle(Vector2(-30, 30), 14.0)
		if point_ok(p.x, p.y, 4.0) and claim_spacing("fern", p.x, p.y, 2.5):
			add_instance("fern_a", p.x, p.y, rng.randf() * 360.0, rng.randf_range(0.7, 1.0), 0.0, 120.0)


func _lily_pads(center: Vector2, radius: float, count: int) -> void:
	var level := WorldTerrain.pond_level("meadow_pond")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.9
	mesh.bottom_radius = 0.9
	mesh.height = 0.04
	mesh.radial_segments = 16
	var mat := PropLibrary.material("leaf_clover")
	for i in count:
		var p := random_in_circle(center, radius * 0.85)
		var pad := MeshInstance3D.new()
		pad.mesh = mesh
		pad.material_override = mat
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pad)
		pad.global_position = Vector3(p.x, level + 0.03, p.y)
		pad.scale = Vector3.ONE * rng.randf_range(0.6, 1.3)
		pad.rotation.y = rng.randf() * TAU
