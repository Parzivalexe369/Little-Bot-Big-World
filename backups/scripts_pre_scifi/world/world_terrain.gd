@tool
class_name WorldTerrain
extends Node3D
## Generates the world's ground from WorldLayout: a 1 m height grid shaped by the path,
## area basins, the shrine plateau, ponds, the ravine and boundary hills.
## Builds chunked render meshes (with per-vertex area/path data for the terrain shader)
## and a single HeightMapShape3D for collision. Static height queries are available to
## every system once generated.

const CELL := 1.0
const CHUNK := 64
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const NOISE_TEX := preload("res://materials/noise_tex.tres")
## Photoscanned surface layers, built by tools/build_texture_arrays.gd (layer order in that file).
const LAYER_ALBEDO := preload("res://assets/textures/terrain/terrain_diff.png")
const LAYER_NORMAL := preload("res://assets/textures/terrain/terrain_nor.png")
const LAYER_ARM := preload("res://assets/textures/terrain/terrain_arm.png")
const CACHE_PATH := "res://resources/terrain_cache.bin"
## Bump when the height function changes so stale caches are regenerated.
const TERRAIN_VERSION := 5

static var _heights: PackedFloat32Array = []
static var _data_a: PackedColorArray = []   # path, wet, forest, garden
static var _data_b: PackedVector2Array = [] # shrine, hill
static var _width := 0
static var _depth := 0
static var _generated := false
static var _noise_low: FastNoiseLite
static var _noise_detail: FastNoiseLite
static var _noise_hill: FastNoiseLite
static var _noise_edge: FastNoiseLite
static var _buckets: Dictionary = {}
static var _pond_levels: Dictionary = {}
static var _zone_heights: Dictionary = {}

@export var regenerate := false:
	set(value):
		if value and is_inside_tree():
			_generated = false
			build()

var material: ShaderMaterial


func _ready() -> void:
	build()


static func is_ready() -> bool:
	return _generated


## Bilinear height of the ground at a world position.
static func height_at_world(x: float, z: float) -> float:
	if not _generated:
		return compute_height(x, z)
	var gx := clampf((x - WorldLayout.MIN_X) / CELL, 0.0, _width - 1.001)
	var gz := clampf((z - WorldLayout.MIN_Z) / CELL, 0.0, _depth - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * _width + ix
	var h00 := _heights[i]
	var h10 := _heights[i + 1]
	var h01 := _heights[i + _width]
	var h11 := _heights[i + _width + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


static func normal_at_world(x: float, z: float) -> Vector3:
	var e := 0.6
	var hl := height_at_world(x - e, z)
	var hr := height_at_world(x + e, z)
	var hd := height_at_world(x, z - e)
	var hu := height_at_world(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


static func point_on_ground(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, height_at_world(x, z) + lift, z)


## Moves a node so it sits on the ground (plus offset). Works before and after generation.
static func snap_node(node: Node3D, offset: float = 0.0) -> void:
	var p := node.global_position
	node.global_position = Vector3(p.x, height_at_world(p.x, p.z) + offset, p.z)


static func pond_level(pond_id: String) -> float:
	_ensure_noise()
	if not _pond_levels.has(pond_id):
		for pond: Dictionary in WorldLayout.PONDS:
			if pond["id"] == pond_id:
				var c: Vector2 = pond["center"]
				_pond_levels[pond_id] = _height_without_water(c.x, c.y) - 0.35
	return _pond_levels.get(pond_id, 0.0)


func build() -> void:
	var t0 := Time.get_ticks_msec()
	if not _generated and not _load_cache():
		_generate_grid()
		_save_cache()
	for child in get_children():
		child.queue_free()
	material = ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("noise_tex", NOISE_TEX)
	material.set_shader_parameter("layer_albedo", LAYER_ALBEDO)
	material.set_shader_parameter("layer_normal", LAYER_NORMAL)
	material.set_shader_parameter("layer_arm", LAYER_ARM)
	_build_meshes()
	if not Engine.is_editor_hint():
		_build_collision()
	print("[WorldTerrain] built in %d ms (%dx%d)" % [Time.get_ticks_msec() - t0, _width, _depth])


# --- Height function ------------------------------------------------------------

static func _ensure_noise() -> void:
	if _noise_low != null:
		return
	_noise_low = FastNoiseLite.new()
	_noise_low.seed = 1337
	_noise_low.frequency = 0.011
	_noise_low.fractal_octaves = 3
	_noise_detail = FastNoiseLite.new()
	_noise_detail.seed = 77
	_noise_detail.frequency = 0.07
	_noise_detail.fractal_octaves = 2
	_noise_hill = FastNoiseLite.new()
	_noise_hill.seed = 4242
	_noise_hill.frequency = 0.018
	_noise_hill.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_hill.fractal_octaves = 3
	_noise_edge = FastNoiseLite.new()
	_noise_edge.seed = 9001
	_noise_edge.frequency = 0.035
	_build_buckets()


## Spatial buckets of path segments so distance queries only test nearby segments.
static func _build_buckets() -> void:
	_buckets.clear()
	var samples := WorldLayout.path_samples()
	var reach := 42.0
	for i in samples.size() - 1:
		var a := samples[i]
		var b := samples[i + 1]
		var min_b := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
		var max_b := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
		for bx in range(floori(min_b.x / 16.0), floori(max_b.x / 16.0) + 1):
			for bz in range(floori(min_b.y / 16.0), floori(max_b.y / 16.0) + 1):
				var key := Vector2i(bx, bz)
				if not _buckets.has(key):
					_buckets[key] = PackedInt32Array()
				var arr: PackedInt32Array = _buckets[key]
				arr.append(i)
				_buckets[key] = arr


## Fast nearest-path query: (distance, path height, distance along). Far points report 999.
static func path_query_fast(p: Vector2) -> Vector3:
	var key := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	if not _buckets.has(key):
		return Vector3(999.0, 0.0, 0.0)
	var samples := WorldLayout.path_samples()
	var heights := WorldLayout._path_heights
	var lengths := WorldLayout._path_lengths
	var best := INF
	var best_h := 0.0
	var best_s := 0.0
	for i: int in _buckets[key]:
		var a := samples[i]
		var ab := samples[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			best_h = lerpf(heights[i], heights[i + 1], t)
			best_s = lerpf(lengths[i], lengths[i + 1], t)
	return Vector3(sqrt(best), best_h, best_s)


static func compute_height(x: float, z: float) -> float:
	var h := _height_without_water(x, z)
	var p := Vector2(x, z)
	# Ponds: smooth bowls below the local water level.
	for pond: Dictionary in WorldLayout.PONDS:
		var c: Vector2 = pond["center"]
		var r: float = pond["radius"]
		var d := p.distance_to(c)
		if d < r + 4.0:
			var level := pond_level(pond["id"])
			var floor_h: float = level - float(pond["depth"])
			var k := smoothstep(r * 0.35, r + 1.5, d)
			h = minf(h, lerpf(floor_h, maxf(h, level + 0.2), k))
	# The ravine cuts through everything with steep walls.
	var dr := WorldLayout.distance_to_polyline(p, WorldLayout.RAVINE_POINTS)
	var half := WorldLayout.RAVINE_HALF_WIDTH
	if dr < half + 3.0:
		var bottom := -1.0 - WorldLayout.RAVINE_DEPTH + _noise_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.25
		var carve := 1.0 - smoothstep(half - 2.2, half + 0.6, dr)
		h = lerpf(h, minf(h, bottom), carve)
	return h


static func _height_without_water(x: float, z: float) -> float:
	var h := _base_height(x, z)
	var p := Vector2(x, z)
	for i in WorldLayout.FLAT_ZONES.size():
		var zone: Dictionary = WorldLayout.FLAT_ZONES[i]
		var c: Vector2 = zone["center"]
		var r: float = zone["radius"]
		var d := p.distance_to(c)
		if d < r:
			if not _zone_heights.has(i):
				_zone_heights[i] = _base_height(c.x, c.y)
			h = lerpf(_zone_heights[i], h, smoothstep(r - 4.0, r, d))
	return h


static func _base_height(x: float, z: float) -> float:
	_ensure_noise()
	var p := Vector2(x, z)
	var path := path_query_fast(p)
	var noise := _noise_low.get_noise_2d(x, z) * 1.7 + _noise_detail.get_noise_2d(x, z) * 0.3

	# Area basins blended with the path height in the corridors between areas.
	var area_sum := 0.0
	var area_h := 0.0
	var influence := 0.0
	for id: StringName in WorldLayout.AREAS:
		var area: Dictionary = WorldLayout.AREAS[id]
		var r: float = area["radius"]
		var d: float = p.distance_to(area["center"])
		var w := 1.0 - smoothstep(r * 0.55, r * 1.08, d)
		var ah: float = area["height"]
		if id == &"shrine":
			ah = -1.0
		area_h += ah * w
		area_sum += w
		influence = maxf(influence, w)
	var base := area_h / area_sum if area_sum > 0.001 else 0.0
	var corridor_h := lerpf(path.y, base, smoothstep(18.0, 38.0, path.x)) if path.x < 900.0 else base
	base = lerpf(corridor_h, base, clampf(influence, 0.0, 1.0))
	var h := base + noise

	# Shrine plateau with cliff edges.
	var ds := p.distance_to(WorldLayout.SHRINE_CENTER)
	var plateau := 1.0 - smoothstep(WorldLayout.SHRINE_PLATEAU_RADIUS - 2.5, WorldLayout.SHRINE_PLATEAU_RADIUS + 3.5, ds + _noise_edge.get_noise_2d(x, z) * 3.0)
	# Inner plateau is nearly level (beam puzzles need it) and the plaza is perfectly flat.
	var inner := 1.0 - smoothstep(18.0, 27.0, ds)
	var plateau_h := WorldLayout.SHRINE_PLATEAU_HEIGHT + noise * lerpf(0.35, 0.08, inner)
	var plaza := 1.0 - smoothstep(WorldLayout.SHRINE_PLAZA_RADIUS, WorldLayout.SHRINE_PLAZA_RADIUS + 3.0, p.distance_to(WorldLayout.SHRINE_PLAZA_CENTER))
	plateau_h = lerpf(plateau_h, WorldLayout.SHRINE_PLATEAU_HEIGHT, plaza)
	h = lerpf(h, plateau_h, plateau)

	# Boundary hills outside the playable region.
	var sdf := _playable_sdf_fast(p, path.x) + _noise_edge.get_noise_2d(x * 1.3, z * 1.3) * 5.0
	if sdf > 0.0:
		var hill := 0.5 + 0.5 * _noise_hill.get_noise_2d(x, z)
		h += smoothstep(0.0, 15.0, sdf) * (13.0 + hill * 17.0) + maxf(sdf - 15.0, 0.0) * 0.45

	# Flatten and slightly sink the walkable path (but never across the ravine).
	var dr := WorldLayout.distance_to_polyline(p, WorldLayout.RAVINE_POINTS)
	var path_w := 1.0 - smoothstep(WorldLayout.PATH_HALF_WIDTH + 0.8, WorldLayout.PATH_HALF_WIDTH + 7.5, path.x)
	path_w *= smoothstep(WorldLayout.RAVINE_HALF_WIDTH, WorldLayout.RAVINE_HALF_WIDTH + 3.0, dr)
	path_w *= smoothstep(WorldLayout.SHRINE_PLAZA_RADIUS - 2.0, WorldLayout.SHRINE_PLAZA_RADIUS + 2.0, p.distance_to(WorldLayout.SHRINE_PLAZA_CENTER))
	if path_w > 0.0:
		var sink := 0.12 * (1.0 - smoothstep(0.0, WorldLayout.PATH_HALF_WIDTH, path.x))
		var path_h := path.y + _noise_low.get_noise_2d(x, z) * 0.25 - sink
		h = lerpf(h, path_h, path_w)
	return h


static func _playable_sdf_fast(p: Vector2, path_distance: float) -> float:
	var d := path_distance - 10.0
	for id: StringName in WorldLayout.AREAS:
		var area: Dictionary = WorldLayout.AREAS[id]
		d = minf(d, p.distance_to(area["center"]) - float(area["radius"]))
	return d


# --- Grid & meshes --------------------------------------------------------------

func _generate_grid() -> void:
	_ensure_noise()
	_width = int((WorldLayout.MAX_X - WorldLayout.MIN_X) / CELL) + 1
	_depth = int((WorldLayout.MAX_Z - WorldLayout.MIN_Z) / CELL) + 1
	_heights.resize(_width * _depth)
	_data_a.resize(_width * _depth)
	_data_b.resize(_width * _depth)
	for iz in _depth:
		var z := WorldLayout.MIN_Z + iz * CELL
		for ix in _width:
			var x := WorldLayout.MIN_X + ix * CELL
			var i := iz * _width + ix
			_heights[i] = compute_height(x, z)
			var p := Vector2(x, z)
			var path := path_query_fast(p)
			var path_mask := 1.0 - smoothstep(WorldLayout.PATH_HALF_WIDTH - 0.6, WorldLayout.PATH_HALF_WIDTH + 1.4, path.x + _noise_detail.get_noise_2d(x * 3.0, z * 3.0) * 0.9)
			var wet := 0.0
			for pond: Dictionary in WorldLayout.PONDS:
				var c: Vector2 = pond["center"]
				wet = maxf(wet, 1.0 - smoothstep(float(pond["radius"]) - 1.0, float(pond["radius"]) + 3.0, p.distance_to(c)))
			var dr := WorldLayout.distance_to_polyline(p, WorldLayout.RAVINE_POINTS)
			wet = maxf(wet, 1.0 - smoothstep(WorldLayout.RAVINE_HALF_WIDTH - 2.0, WorldLayout.RAVINE_HALF_WIDTH + 1.0, dr))
			var weights := WorldLayout.area_weights(p)
			var hill := clampf(_playable_sdf_fast(p, path.x) / 12.0, 0.0, 1.0)
			_data_a[i] = Color(path_mask, wet, weights[&"forest"], weights[&"garden"])
			_data_b[i] = Vector2(weights[&"shrine"], hill)
	_generated = true


static func _layout_hash() -> int:
	var text := "%d|%s|%s|%s|%s|%s|%s|%f|%f" % [TERRAIN_VERSION, WorldLayout.PATH_POINTS, WorldLayout.PATH_HEIGHTS,
		WorldLayout.AREAS, WorldLayout.RAVINE_POINTS, WorldLayout.PONDS, WorldLayout.SHRINE_CENTER,
		WorldLayout.SHRINE_PLATEAU_RADIUS, WorldLayout.RAVINE_DEPTH + WorldLayout.SHRINE_PLAZA_RADIUS + WorldLayout.FLAT_ZONES.size() * 1000]
	return text.hash()


func _load_cache() -> bool:
	if not FileAccess.file_exists(CACHE_PATH):
		return false
	var file := FileAccess.open_compressed(CACHE_PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return false
	var header: Variant = file.get_var()
	if not (header is Dictionary) or header.get("hash", 0) != _layout_hash():
		return false
	_width = header["width"]
	_depth = header["depth"]
	_heights = file.get_var()
	_data_a = file.get_var()
	_data_b = file.get_var()
	if _heights.size() != _width * _depth or _data_a.size() != _heights.size():
		return false
	_ensure_noise()
	_generated = true
	return true


func _save_cache() -> void:
	if OS.has_feature("template"):
		return
	var file := FileAccess.open_compressed(CACHE_PATH, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return
	file.store_var({"hash": _layout_hash(), "width": _width, "depth": _depth})
	file.store_var(_heights)
	file.store_var(_data_a)
	file.store_var(_data_b)
	file.close()


func _build_meshes() -> void:
	var chunks_x := ceili(float(_width - 1) / CHUNK)
	var chunks_z := ceili(float(_depth - 1) / CHUNK)
	for cz in chunks_z:
		for cx in chunks_x:
			var mesh := _build_chunk(cx * CHUNK, cz * CHUNK, mini(CHUNK, _width - 1 - cx * CHUNK), mini(CHUNK, _depth - 1 - cz * CHUNK))
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = mesh
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)


func _build_chunk(x0: int, z0: int, nx: int, nz: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize((nx + 1) * (nz + 1))
	normals.resize(verts.size())
	colors.resize(verts.size())
	uv2.resize(verts.size())
	var k := 0
	for iz in range(z0, z0 + nz + 1):
		for ix in range(x0, x0 + nx + 1):
			var i := iz * _width + ix
			verts[k] = Vector3(WorldLayout.MIN_X + ix * CELL, _heights[i], WorldLayout.MIN_Z + iz * CELL)
			normals[k] = _grid_normal(ix, iz)
			colors[k] = _data_a[i]
			uv2[k] = _data_b[i]
			k += 1
	var row := nx + 1
	for iz in nz:
		for ix in nx:
			var a := iz * row + ix
			var b := a + 1
			var c := a + row
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _grid_normal(ix: int, iz: int) -> Vector3:
	var l := _heights[iz * _width + maxi(ix - 1, 0)]
	var r := _heights[iz * _width + mini(ix + 1, _width - 1)]
	var d := _heights[maxi(iz - 1, 0) * _width + ix]
	var u := _heights[mini(iz + 1, _depth - 1) * _width + ix]
	return Vector3(l - r, 2.0 * CELL, d - u).normalized()


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = _width
	shape.map_depth = _depth
	shape.map_data = _heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3((WorldLayout.MIN_X + WorldLayout.MAX_X) * 0.5, 0.0, (WorldLayout.MIN_Z + WorldLayout.MAX_Z) * 0.5)
	body.add_child(cs)
