class_name WorldLayout
extends RefCounted
## Hand-designed macro layout of the world: the main path, the four areas and landmark
## features. Terrain, scatter and atmosphere all read from here so they stay consistent.
## Coordinates are world XZ in meters; the robot is about 0.7 m tall, so a 6 m flower
## towers over it like a tree.

## The winding main path from the charging dock to the Crystal Heart.
const PATH_POINTS: Array[Vector2] = [
	Vector2(0, 58), Vector2(2, 48), Vector2(7, 36), Vector2(2, 24), Vector2(-7, 14),
	Vector2(-6, 2), Vector2(4, -10), Vector2(9, -22), Vector2(5, -36), Vector2(1, -48),
	Vector2(-6, -62), Vector2(-18, -78), Vector2(-30, -94), Vector2(-40, -110),
	Vector2(-42, -126), Vector2(-34, -142), Vector2(-24, -158), Vector2(-14, -172),
	Vector2(-6, -186), Vector2(0, -198), Vector2(4, -212), Vector2(10, -224),
	Vector2(18, -236), Vector2(26, -248), Vector2(30, -262), Vector2(30, -278),
	Vector2(28, -292), Vector2(22, -306), Vector2(14, -322), Vector2(4, -338),
	Vector2(-4, -354), Vector2(-8, -372), Vector2(-8, -390), Vector2(-6, -404),
]

## Height of the path surface at each control point (blended along the path).
const PATH_HEIGHTS: Array[float] = [
	0.6, 0.5, 0.4, 0.2, 0.1, 0.0, 0.0, 0.2, 0.5, 0.8,
	0.5, 0.0, -0.5, -0.8, -1.0, -1.0, -1.0, -1.0,
	-1.0, -1.0, -1.0, -0.6, 1.5, 4.0, 7.0, 7.0,
	7.0, 6.6, 5.2, 3.0, 1.0, -0.8, -2.2, -3.0,
]

const PATH_HALF_WIDTH := 2.4

## Area blobs: center, radius, base height, ground character.
const AREAS := {
	&"meadow": {"center": Vector2(0, 14), "radius": 64.0, "height": 0.0},
	&"forest": {"center": Vector2(-30, -124), "radius": 62.0, "height": -1.0},
	&"shrine": {"center": Vector2(30, -266), "radius": 38.0, "height": 7.0},
	&"garden": {"center": Vector2(-6, -398), "radius": 66.0, "height": -3.0},
}

## The ravine between forest and shrine. Polyline crossing the path near z = -205.
const RAVINE_POINTS: Array[Vector2] = [
	Vector2(-70, -214), Vector2(-40, -208), Vector2(-15, -204), Vector2(2, -205),
	Vector2(20, -209), Vector2(45, -214), Vector2(75, -222),
]
const RAVINE_HALF_WIDTH := 5.0
const RAVINE_DEPTH := 6.5
## Bridge deck spans the ravine along the path here.
const BRIDGE_START := Vector2(1.0, -197.5)
const BRIDGE_END := Vector2(3.6, -211.5)

const SHRINE_CENTER := Vector2(30, -266)
const SHRINE_PLATEAU_RADIUS := 31.0
const SHRINE_PLAZA_CENTER := Vector2(30, -269)
const SHRINE_PLAZA_RADIUS := 13.0
const SHRINE_PLATEAU_HEIGHT := 7.0

## Ponds: center, radius, water surface height (relative to world).
const PONDS := [
	{"id": "meadow_pond", "center": Vector2(-30, 30), "radius": 9.0, "depth": 1.4},
	{"id": "forest_pool", "center": Vector2(-8, -118), "radius": 9.5, "depth": 1.2},
	{"id": "shrine_pool", "center": Vector2(47, -275), "radius": 6.5, "depth": 1.0},
	{"id": "garden_pool_a", "center": Vector2(-30, -392), "radius": 11.0, "depth": 1.0},
	{"id": "garden_pool_b", "center": Vector2(20, -414), "radius": 8.0, "depth": 1.0},
]

## Ground flattened for puzzles that need level floors (light beams) and key set pieces.
const FLAT_ZONES := [
	{"center": Vector2(26, -379), "radius": 15.0},
	{"center": Vector2(-26, -428), "radius": 10.0},
	{"center": Vector2(-6, -410), "radius": 9.0},
]

## Light-beam routes (world XZ polylines) that scatter must keep clear.
const BEAM_LANES := [
	[Vector2(46, -246), Vector2(46, -256), Vector2(36, -256), Vector2(36, -261.5)],
	[Vector2(34, -372), Vector2(18, -372), Vector2(18, -386), Vector2(24.5, -386)],
]

## World bounds of the generated terrain.
const MIN_X := -160.0
const MAX_X := 160.0
const MIN_Z := -500.0
const MAX_Z := 100.0


static var _path_samples: PackedVector2Array = []
static var _path_heights: PackedFloat32Array = []
static var _path_lengths: PackedFloat32Array = []


static func path_samples() -> PackedVector2Array:
	_ensure_path()
	return _path_samples


## Distance to the path, the path height there and the path parameter (meters along).
static func path_query(p: Vector2) -> Vector3:
	_ensure_path()
	var best := INF
	var best_h := 0.0
	var best_s := 0.0
	for i in _path_samples.size() - 1:
		var a := _path_samples[i]
		var b := _path_samples[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			best_h = lerpf(_path_heights[i], _path_heights[i + 1], t)
			best_s = lerpf(_path_lengths[i], _path_lengths[i + 1], t)
	return Vector3(sqrt(best), best_h, best_s)


static func path_point_at(distance_along: float) -> Vector2:
	_ensure_path()
	for i in _path_samples.size() - 1:
		if _path_lengths[i + 1] >= distance_along:
			var t := inverse_lerp(_path_lengths[i], _path_lengths[i + 1], distance_along)
			return _path_samples[i].lerp(_path_samples[i + 1], t)
	return _path_samples[_path_samples.size() - 1]


static func path_length() -> float:
	_ensure_path()
	return _path_lengths[_path_lengths.size() - 1]


static func distance_to_polyline(p: Vector2, points: Array[Vector2]) -> float:
	var best := INF
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Which area a world position belongs to (nearest blob, measured relative to radius).
static func area_at(p: Vector2) -> StringName:
	var best: StringName = &"meadow"
	var best_score := INF
	for id: StringName in AREAS:
		var area: Dictionary = AREAS[id]
		var score: float = p.distance_to(area["center"]) / float(area["radius"])
		if score < best_score:
			best_score = score
			best = id
	return best


## Soft weights (0..1) of each area at p, summing to 1. Used for ground colors and fog.
static func area_weights(p: Vector2) -> Dictionary:
	var weights := {}
	var total := 0.0
	for id: StringName in AREAS:
		var area: Dictionary = AREAS[id]
		var d: float = p.distance_to(area["center"]) / float(area["radius"])
		var w := exp(-d * d * 3.0)
		weights[id] = w
		total += w
	for id: StringName in weights:
		weights[id] = weights[id] / maxf(total, 0.00001)
	return weights


## Signed distance to the playable region (negative inside).
static func playable_sdf(p: Vector2) -> float:
	var d := INF
	for id: StringName in AREAS:
		var area: Dictionary = AREAS[id]
		d = minf(d, p.distance_to(area["center"]) - float(area["radius"]))
	var path := path_query(p)
	d = minf(d, path.x - 10.0)
	return d


static func _ensure_path() -> void:
	if not _path_samples.is_empty():
		return
	# Catmull-Rom through the control points for a natural winding path.
	var pts := PATH_POINTS
	var hs := PATH_HEIGHTS
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		var h1 := hs[i]
		var h2 := hs[i + 1]
		var steps := 8
		for s in steps:
			var t := float(s) / steps
			_path_samples.append(_catmull(p0, p1, p2, p3, t))
			var ht := t * t * (3.0 - 2.0 * t)
			_path_heights.append(lerpf(h1, h2, ht))
	_path_samples.append(pts[pts.size() - 1])
	_path_heights.append(hs[hs.size() - 1])
	var acc := 0.0
	_path_lengths.append(0.0)
	for i in range(1, _path_samples.size()):
		acc += _path_samples[i].distance_to(_path_samples[i - 1])
		_path_lengths.append(acc)


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
