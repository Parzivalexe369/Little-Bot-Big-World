class_name WorldBoundary
extends StaticBody3D
## Invisible wall that follows the foot of the boundary hills (a contour of the same noisy
## "playable" distance field the terrain uses). Built with marching squares into one
## concave collision mesh on the player-only layer, so the robot can't climb out of the
## world or around a gate, while the camera passes through freely.

const STEP := 2.0
const CONTOUR := 5.0
const WALL_HEIGHT := 40.0


func _ready() -> void:
	collision_layer = 1 << 7
	collision_mask = 0
	var t0 := Time.get_ticks_msec()
	var segments := _contour_segments()
	var faces := PackedVector3Array()
	for seg in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ya := WorldTerrain.height_at_world(a.x, a.y) - 6.0
		var yb := WorldTerrain.height_at_world(b.x, b.y) - 6.0
		var a0 := Vector3(a.x, ya, a.y)
		var b0 := Vector3(b.x, yb, b.y)
		var a1 := Vector3(a.x, ya + WALL_HEIGHT, a.y)
		var b1 := Vector3(b.x, yb + WALL_HEIGHT, b.y)
		faces.append_array([a0, b0, b1, a0, b1, a1])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	print("[WorldBoundary] %d wall segments in %d ms" % [segments.size(), Time.get_ticks_msec() - t0])


static func field(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var sdf := WorldTerrain._playable_sdf_fast(p, WorldTerrain.path_query_fast(p).x)
	return sdf + WorldTerrain._noise_edge.get_noise_2d(x * 1.3, z * 1.3) * 5.0 - CONTOUR


func _contour_segments() -> Array:
	WorldTerrain._ensure_noise()
	var nx := int((WorldLayout.MAX_X - WorldLayout.MIN_X) / STEP) + 1
	var nz := int((WorldLayout.MAX_Z - WorldLayout.MIN_Z) / STEP) + 1
	var values := PackedFloat32Array()
	values.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			values[iz * nx + ix] = field(WorldLayout.MIN_X + ix * STEP, WorldLayout.MIN_Z + iz * STEP)
	var out := []
	for iz in nz - 1:
		for ix in nx - 1:
			var v0 := values[iz * nx + ix]
			var v1 := values[iz * nx + ix + 1]
			var v2 := values[(iz + 1) * nx + ix + 1]
			var v3 := values[(iz + 1) * nx + ix]
			var idx := (1 if v0 > 0 else 0) | (2 if v1 > 0 else 0) | (4 if v2 > 0 else 0) | (8 if v3 > 0 else 0)
			if idx == 0 or idx == 15:
				continue
			var x0 := WorldLayout.MIN_X + ix * STEP
			var z0 := WorldLayout.MIN_Z + iz * STEP
			var p0 := Vector2(x0, z0)
			var p1 := Vector2(x0 + STEP, z0)
			var p2 := Vector2(x0 + STEP, z0 + STEP)
			var p3 := Vector2(x0, z0 + STEP)
			var e := [
				_lerp_edge(p0, p1, v0, v1), _lerp_edge(p1, p2, v1, v2),
				_lerp_edge(p2, p3, v2, v3), _lerp_edge(p3, p0, v3, v0),
			]
			for pair: Array in _CASES[idx]:
				out.append([e[pair[0]], e[pair[1]]])
	return out


static func _lerp_edge(a: Vector2, b: Vector2, va: float, vb: float) -> Vector2:
	var t := 0.5 if is_equal_approx(va, vb) else clampf(va / (va - vb), 0.0, 1.0)
	return a.lerp(b, t)


## Marching squares: which cell edges (0 bottom, 1 right, 2 top, 3 left) to connect.
const _CASES := {
	1: [[3, 0]], 2: [[0, 1]], 3: [[3, 1]], 4: [[1, 2]], 5: [[3, 0], [1, 2]], 6: [[0, 2]], 7: [[3, 2]],
	8: [[2, 3]], 9: [[2, 0]], 10: [[0, 1], [2, 3]], 11: [[2, 1]], 12: [[1, 3]], 13: [[1, 0]], 14: [[0, 3]],
}
