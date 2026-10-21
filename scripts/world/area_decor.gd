class_name AreaDecor
extends Node3D
## Base for an area scene's decoration: hand-placed landmark props plus rule-based scatter
## that respects the path, water, slopes and gameplay objects. Scatter output is batched
## into spatially chunked MultiMeshes (cheap to draw, culled by distance), with shared
## static colliders where props should block the robot.

const CHUNK := 32.0
## Browsers batch scatter in 64 m patches (a quarter as many WebGL draw calls for the same
## view); desktop keeps the finer 32 m patches.
static var chunk_size := 64.0 if OS.has_feature("web") else CHUNK

@export var area_id: StringName = &"meadow"
@export var scatter_seed := 1

## Ground clutter per area: prop -> [count, spacing, scale min, scale max, view range].
## Uses its own random stream so the rest of the scatter keeps its placement.
const CLUTTER := {
	&"meadow": {"pebble_cluster": [70, 3.0, 0.8, 1.4, 70.0], "twig_small": [30, 4.0, 0.8, 1.3, 60.0],
		"leaf_litter": [14, 6.0, 0.5, 0.8, 60.0]},
	&"forest": {"leaf_litter": [150, 2.6, 0.55, 1.0, 75.0], "twig_small": [70, 3.0, 0.8, 1.4, 60.0],
		"pebble_cluster": [40, 4.0, 0.8, 1.3, 60.0]},
	&"shrine": {"pebble_cluster": [60, 3.0, 0.8, 1.5, 70.0], "leaf_litter": [30, 5.0, 0.5, 0.8, 60.0]},
	&"garden": {"pebble_cluster": [60, 3.0, 0.8, 1.4, 70.0], "twig_small": [20, 5.0, 0.8, 1.2, 60.0]},
}

var rng := RandomNumberGenerator.new()
## Circles (x, z, radius) that scatter must avoid.
var exclusions: Array[Vector3] = []
## Circles covered by solid props; the grass field keeps them clear so blades never poke through.
var solid_footprints: Array[Vector3] = []
var _spacing_hash: Dictionary = {}
var _batches: Dictionary = {}  # key -> {mesh, transforms[], range}
var _collision_body: StaticBody3D
var _density := 1.0


## Browsers: areas still building (each builds in a frame of its own; see _ready).
static var building := 0
static var _turn := 0


func _ready() -> void:
	add_to_group(&"area_decor")
	rng.seed = scatter_seed
	_density = Settings.quality_params()["grass_density"]
	_collision_body = StaticBody3D.new()
	_collision_body.name = "DecorCollision"
	_collision_body.collision_layer = 1
	add_child(_collision_body)
	if OS.has_feature("web"):
		# Browsers: the four areas together took ~8 s of one frame (Chrome calls a page
		# unresponsive after 15 s without a break), so each builds in its own frame. The
		# loading screen waits for them (SceneRouter), and so does the grass.
		building += 1
		_turn += 1
		for i in _turn:
			await get_tree().process_frame
	_collect_gameplay_exclusions()
	build_landmarks()
	build_scatter()
	build_clutter()
	_flush_batches()
	if OS.has_feature("web"):
		building -= 1
		if building == 0:
			_turn = 0


## Override: hand-placed props.
func build_landmarks() -> void:
	pass


## Override: scatter rules.
func build_scatter() -> void:
	pass


func _collect_gameplay_exclusions() -> void:
	for child in get_children():
		if child is Node3D and child != _collision_body:
			var p := (child as Node3D).global_position
			var r := 2.5
			if child is Device:
				r = 6.0
			elif child is EnergyFragment:
				r = 1.6
			elif child is FlagTrigger or child is Checkpoint:
				continue
			exclusions.append(Vector3(p.x, p.z, r))
			if child is Device or child is OldRobot or child is DiscoverySpot:
				solid_footprints.append(Vector3(p.x, p.z, 4.0))


func exclude(x: float, z: float, radius: float) -> void:
	exclusions.append(Vector3(x, z, radius))


## Hand-placed prop snapped to the ground. y_offset lifts/sinks it.
func place(prop: String, x: float, z: float, yaw: float = 0.0, scale: float = 1.0, collision: bool = true, y_offset: float = 0.0, exclusion_radius: float = -1.0) -> Node3D:
	var pos := WorldTerrain.point_on_ground(x, z, y_offset)
	var node := PropLibrary.place(self, prop, Vector3.ZERO, yaw, scale, collision)
	node.global_position = pos
	var r := exclusion_radius if exclusion_radius >= 0.0 else _default_radius(prop) * scale
	if r > 0.0:
		exclusions.append(Vector3(x, z, r))
	if collision:
		solid_footprints.append(Vector3(x, z, _footprint_radius(prop) * scale))
	return node


## Rough ground footprint of solid props (for keeping grass out of them).
func _footprint_radius(prop: String) -> float:
	match prop:
		"watering_can": return 6.5
		"log_hollow": return 7.5
		"twig_a": return 6.0
		"root_gate": return 6.0
		"stairs": return 3.4
		"wall_full", "wall_broken": return 2.8
		"arch": return 4.0
		"tree_trunk_a": return 5.5
		"tree_trunk_b": return 4.0
		"rock_c", "rock_moss_b": return 3.0
		"crystal_spire": return 7.0
		"pipe_segment": return 3.2
	return _default_radius(prop) * 0.7


func _default_radius(prop: String) -> float:
	if prop.begins_with("tree_trunk"):
		return 9.0
	if prop.begins_with("mushroom_red") or prop.begins_with("mushroom_tan"):
		return 3.5
	if prop.begins_with("rock_c") or prop.begins_with("rock_moss_b"):
		return 3.5
	if prop.begins_with("crystal_spire"):
		return 9.0
	return 2.0


## Small stones, twigs and fallen leaves that break up open ground.
func build_clutter() -> void:
	var recipe: Dictionary = CLUTTER.get(area_id, {})
	if recipe.is_empty() or not WorldLayout.AREAS.has(area_id):
		return
	var crng := RandomNumberGenerator.new()
	crng.seed = scatter_seed * 7919 + 17
	var center: Vector2 = WorldLayout.AREAS[area_id]["center"]
	var radius: float = WorldLayout.AREAS[area_id]["radius"]
	for prop: String in recipe:
		var r: Array = recipe[prop]
		for i in int(float(r[0]) * _density):
			var a := crng.randf() * TAU
			var p := center + Vector2(cos(a), sin(a)) * sqrt(crng.randf()) * radius
			if point_ok(p.x, p.y, 2.6) and claim_spacing("clutter_" + prop, p.x, p.y, r[1]):
				add_instance(prop, p.x, p.y, crng.randf() * 360.0, crng.randf_range(r[2], r[3]), -0.02, r[4])


# --- Placement rules ------------------------------------------------------------

## True if a scatter point is acceptable. min_path/max_path in meters from the path center.
func point_ok(x: float, z: float, min_path: float = 3.2, max_path: float = 9999.0, max_slope: float = 0.75, clearance: float = 0.0) -> bool:
	var p := Vector2(x, z)
	if x < WorldLayout.MIN_X + 2.0 or x > WorldLayout.MAX_X - 2.0 or z < WorldLayout.MIN_Z + 2.0 or z > WorldLayout.MAX_Z - 2.0:
		return false
	var path := WorldTerrain.path_query_fast(p)
	if path.x < min_path or path.x > max_path:
		return false
	for pond: Dictionary in WorldLayout.PONDS:
		if p.distance_to(pond["center"]) < float(pond["radius"]) + 1.0 + clearance:
			return false
	if WorldLayout.distance_to_polyline(p, WorldLayout.RAVINE_POINTS) < WorldLayout.RAVINE_HALF_WIDTH + 2.0 + clearance:
		return false
	if WorldTerrain.normal_at_world(x, z).y < max_slope:
		return false
	for e in exclusions:
		if p.distance_to(Vector2(e.x, e.y)) < e.z + clearance:
			return false
	for lane: Array in WorldLayout.BEAM_LANES:
		var pts: Array[Vector2] = []
		pts.assign(lane)
		if WorldLayout.distance_to_polyline(p, pts) < 2.6 + clearance:
			return false
	return true


## Keeps scatter of a given layer from bunching up: returns false if too close to others.
func claim_spacing(layer: String, x: float, z: float, spacing: float) -> bool:
	var cell := Vector2i(floori(x / spacing), floori(z / spacing))
	var key := "%s|%d|%d" % [layer, cell.x, cell.y]
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := "%s|%d|%d" % [layer, cell.x + dx, cell.y + dz]
			if _spacing_hash.has(k):
				var q: Vector2 = _spacing_hash[k]
				if q.distance_to(Vector2(x, z)) < spacing:
					return false
	_spacing_hash[key] = Vector2(x, z)
	return true


## Random point inside a circle.
func random_in_circle(center: Vector2, radius: float) -> Vector2:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	return center + Vector2(cos(a), sin(a)) * r


## Random point beside the path between two distances along it.
func random_near_path(from_s: float, to_s: float, min_off: float, max_off: float) -> Vector2:
	var s := rng.randf_range(from_s, to_s)
	var p := WorldLayout.path_point_at(s)
	var ahead := WorldLayout.path_point_at(s + 1.0)
	var dir := (ahead - p).normalized()
	var side := Vector2(-dir.y, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	return p + side * rng.randf_range(min_off, max_off)


# --- Batching ---------------------------------------------------------------------

## Adds one instance of a single-mesh prop to the batched MultiMesh output.
func add_instance(prop: String, x: float, z: float, yaw: float, scale: float, y_offset: float = 0.0, view_range: float = 180.0, collide: String = "", tilt: float = 0.0) -> void:
	var y := WorldTerrain.height_at_world(x, z) + y_offset
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	if tilt > 0.0:
		basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), deg_to_rad(rng.randf_range(0, tilt))) * basis
	basis = basis.scaled(Vector3.ONE * scale)
	var xf := Transform3D(basis, Vector3(x, y, z))
	var chunk := Vector2i(floori(x / chunk_size), floori(z / chunk_size))
	var key := "%s|%d|%d" % [prop, chunk.x, chunk.y]
	if not _batches.has(key):
		_batches[key] = {"prop": prop, "chunk": chunk, "xforms": [], "range": view_range}
	(_batches[key]["xforms"] as Array).append(xf)
	if collide != "":
		_add_collider(prop, xf, collide)
		if collide != "stem":
			solid_footprints.append(Vector3(x, z, _footprint_radius(prop) * scale * 0.8))


func _add_collider(prop: String, xf: Transform3D, kind: String) -> void:
	var cs := CollisionShape3D.new()
	match kind:
		"stem":
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.15
			cyl.height = 3.0
			cs.shape = cyl
			cs.transform = Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * 1.5)
		"convex":
			var mesh := PropLibrary.mesh(prop)
			var key := "scatter:%s" % prop
			var shape: Shape3D = PropLibrary._shapes.get(key)
			if shape == null:
				shape = mesh.create_convex_shape(true, true)
				PropLibrary._shapes[key] = shape
			cs.shape = shape
			cs.transform = xf
		"trimesh":
			var mesh2 := PropLibrary.mesh(prop)
			var key2 := "scatter_tri:%s" % prop
			var shape2: Shape3D = PropLibrary._shapes.get(key2)
			if shape2 == null:
				shape2 = mesh2.create_trimesh_shape()
				PropLibrary._shapes[key2] = shape2
			cs.shape = shape2
			cs.transform = xf
	_collision_body.add_child(cs)


func _flush_batches() -> void:
	for key: String in _batches:
		var batch: Dictionary = _batches[key]
		var mesh := PropLibrary.mesh(batch["prop"])
		if mesh == null:
			continue
		var xforms: Array = batch["xforms"]
		var chunk: Vector2i = batch["chunk"]
		var center := Vector3((chunk.x + 0.5) * chunk_size, 0.0, (chunk.y + 0.5) * chunk_size)
		var avg_y := 0.0
		for xf: Transform3D in xforms:
			avg_y += xf.origin.y
		center.y = avg_y / xforms.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var xf: Transform3D = xforms[i]
			mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - center))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Batch_" + key.replace("|", "_")
		mmi.multimesh = mm
		mmi.position = center
		var view_range: float = batch["range"]
		if view_range > 0.0:
			mmi.visibility_range_end = view_range
			mmi.visibility_range_end_margin = view_range * 0.15
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if OS.has_feature("web") and mesh.get_aabb().size.length() < 2.5:
			# Browsers: pebbles, twigs, leaves and small flowers cast no shadows (too small to
			# see, but each shadow cascade would redraw them).
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_batches.clear()
