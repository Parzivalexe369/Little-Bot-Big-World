class_name GrassField
extends Node3D
## Oversized grass over the whole world, in 20 m chunks of MultiMeshes that fade out with
## distance. Density follows the area (sparser on the forest floor), thins along the path,
## skips water and steep slopes, and gets tall and dense on the boundary hills so the edges
## of the world read as walls of grass.

const CHUNK := 20.0

@export var view_distance := 70.0

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _footprints: Dictionary = {}  # Vector2i cell -> Array[Vector3]


func _ready() -> void:
	_noise.seed = 31
	_noise.frequency = 0.045
	# Build after the area scenes so their solid props can be kept free of grass.
	if OS.has_feature("web"):
		# Browsers build the areas over several frames (AreaDecor), then the grass in its own.
		await get_tree().process_frame
		while AreaDecor.building > 0:
			await get_tree().process_frame
		await get_tree().process_frame
		build()
		return
	build.call_deferred()


func _gather_footprints() -> void:
	_footprints.clear()
	for node in get_tree().get_nodes_in_group(&"area_decor"):
		for fp: Vector3 in (node as AreaDecor).solid_footprints:
			var r := fp.z
			for cx in range(floori((fp.x - r) / 8.0), floori((fp.x + r) / 8.0) + 1):
				for cz in range(floori((fp.y - r) / 8.0), floori((fp.y + r) / 8.0) + 1):
					var key := Vector2i(cx, cz)
					if not _footprints.has(key):
						_footprints[key] = []
					(_footprints[key] as Array).append(fp)


func _in_footprint(p: Vector2) -> bool:
	var list: Variant = _footprints.get(Vector2i(floori(p.x / 8.0), floori(p.y / 8.0)))
	if list == null:
		return false
	for fp: Vector3 in list:
		if p.distance_squared_to(Vector2(fp.x, fp.y)) < fp.z * fp.z:
			return true
	return false


func build() -> void:
	var t0 := Time.get_ticks_msec()
	for child in get_children():
		child.queue_free()
	_gather_footprints()
	var density := float(Settings.quality_params()["grass_density"])
	var short_mesh := PropLibrary.mesh("grass_a")
	var mid_mesh := PropLibrary.mesh("grass_b")
	var tall_mesh := PropLibrary.mesh("grass_tall")
	var clover_mesh := PropLibrary.mesh("clover_a")
	var grass_mat := PropLibrary.material("grass")
	var tall_mat := PropLibrary.material("grass_tall")
	var total := 0
	var cx0 := floori(WorldLayout.MIN_X / CHUNK)
	var cx1 := floori(WorldLayout.MAX_X / CHUNK)
	var cz0 := floori(WorldLayout.MIN_Z / CHUNK)
	var cz1 := floori(WorldLayout.MAX_Z / CHUNK)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var center := Vector2((cx + 0.5) * CHUNK, (cz + 0.5) * CHUNK)
			var sdf := WorldTerrain._playable_sdf_fast(center, WorldTerrain.path_query_fast(center).x)
			if sdf > 40.0:
				continue
			_rng.seed = hash(Vector2i(cx, cz))
			var lists := {"short": [], "mid": [], "tall": [], "clover": []}
			var base_y := WorldTerrain.height_at_world(center.x, center.y)
			# Clumps are full (8-11 thin blades), so fewer of them cover the ground.
			var count := int(CHUNK * CHUNK * 0.8 * density)
			for i in count:
				var x := center.x + (_rng.randf() - 0.5) * CHUNK
				var z := center.y + (_rng.randf() - 0.5) * CHUNK
				var kind := _choose(x, z)
				if kind == "":
					continue
				var y := WorldTerrain.height_at_world(x, z)
				var s := _rng.randf_range(0.75, 1.35)
				if kind == "tall":
					s *= _rng.randf_range(0.9, 1.6)
				else:
					# Shorter grass close to the path keeps the way readable.
					var pd := WorldTerrain.path_query_fast(Vector2(x, z)).x
					s *= lerpf(0.6, 1.0, smoothstep(WorldLayout.PATH_HALF_WIDTH, WorldLayout.PATH_HALF_WIDTH + 7.0, pd))
				var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
				(lists[kind] as Array).append(Transform3D(basis, Vector3(x - center.x, y - base_y - 0.05, z - center.y)))
			var origin := Vector3(center.x, base_y, center.y)
			total += _emit(lists["short"], short_mesh, grass_mat, origin, view_distance)
			total += _emit(lists["mid"], mid_mesh, grass_mat, origin, view_distance)
			total += _emit(lists["tall"], tall_mesh, tall_mat, origin, view_distance * 1.6)
			total += _emit(lists["clover"], clover_mesh, null, origin, view_distance * 0.8)
	print("[GrassField] %d instances in %d ms" % [total, Time.get_ticks_msec() - t0])


func _choose(x: float, z: float) -> String:
	var p := Vector2(x, z)
	var path := WorldTerrain.path_query_fast(p)
	var edge := WorldLayout.PATH_HALF_WIDTH
	if path.x < edge + 0.3:
		return ""
	if path.x < edge + 2.0 and _rng.randf() < 0.6:
		return ""
	for pond: Dictionary in WorldLayout.PONDS:
		var d := p.distance_to(pond["center"])
		if d < float(pond["radius"]) + 0.6:
			return ""
		if d < float(pond["radius"]) + 3.0 and _rng.randf() < 0.35:
			return "tall"
	if WorldLayout.distance_to_polyline(p, WorldLayout.RAVINE_POINTS) < WorldLayout.RAVINE_HALF_WIDTH + 1.0:
		return ""
	if p.distance_to(WorldLayout.SHRINE_PLAZA_CENTER) < WorldLayout.SHRINE_PLAZA_RADIUS + 0.5:
		return ""
	if _in_footprint(p):
		return ""
	var n := WorldTerrain.normal_at_world(x, z)
	if n.y < 0.72:
		return ""
	var sdf := WorldTerrain._playable_sdf_fast(p, path.x)
	var weights := WorldLayout.area_weights(p)
	var patch := _noise.get_noise_2d(x, z)
	var keep := 0.75 + patch * 0.6
	keep *= lerpf(1.0, 0.3, weights[&"forest"])
	keep *= lerpf(1.0, 0.65, weights[&"shrine"])
	if sdf > 2.0:
		keep = 1.0
	if _rng.randf() > keep:
		return ""
	if sdf > 3.0:
		return "tall" if _rng.randf() < 0.55 else "mid"
	if weights[&"meadow"] > 0.5 and patch > 0.35 and _rng.randf() < 0.18:
		return "clover"
	if patch < -0.3 and _rng.randf() < 0.25 and weights[&"forest"] < 0.4:
		return "tall"
	return "mid" if _rng.randf() < 0.4 else "short"


func _emit(xforms: Array, mesh: Mesh, material: Material, origin: Vector3, view_range: float) -> int:
	if xforms.is_empty() or mesh == null:
		return 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = origin
	if material:
		mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = view_range
	mmi.visibility_range_end_margin = 12.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return xforms.size()
