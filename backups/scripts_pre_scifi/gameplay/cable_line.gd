class_name CableLine
extends MeshInstance3D
## An old power cable snaking over the ground between two machines. Dark when unpowered,
## a flowing glow when powered. Points are world XZ; the cable hugs the terrain.

@export var points: PackedVector2Array = []
@export var radius := 0.09
@export var lift := 0.06
@export var sag := 0.0
@export var start_powered := false

var power := 0.0
var _tween: Tween


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if points.size() >= 2:
		build()
	set_power(1.0 if start_powered else 0.0, false)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func build() -> void:
	var path := PackedVector3Array()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 0.8))
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			path.append(Vector3(p.x, WorldTerrain.height_at_world(p.x, p.y) + lift + radius, p.y))
	var last := points[points.size() - 1]
	path.append(Vector3(last.x, WorldTerrain.height_at_world(last.x, last.y) + lift + radius, last.y))
	mesh = _tube(path, radius, 6)
	material_override = PropLibrary.material("conduit_line")


func set_power(value: float, animate: bool = true, duration: float = 1.6) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if not animate:
		power = value
		set_instance_shader_parameter(&"power", value)
		return
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		power = v
		set_instance_shader_parameter(&"power", v), power, value, duration)


static func _tube(path: PackedVector3Array, r: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var prev_n := Vector3.UP
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var n := (prev_n - t * prev_n.dot(t)).normalized()
		if n.length() < 0.1:
			n = t.cross(Vector3.RIGHT).normalized()
		prev_n = n
		var bn := t.cross(n).normalized()
		var ring := PackedVector3Array()
		var nr := PackedVector3Array()
		for s in segs:
			var a := TAU * s / segs
			var dir := n * cos(a) + bn * sin(a)
			ring.append(path[i] + dir * r)
			nr.append(dir)
		rings.append(ring)
		normals.append(nr)
	for i in path.size() - 1:
		for s in segs:
			var s2 := (s + 1) % segs
			var quad := [[i, s], [i + 1, s2], [i, s2], [i, s], [i + 1, s], [i + 1, s2]]
			for q: Array in quad:
				st.set_normal(normals[q[0]][q[1]])
				st.set_uv(Vector2(float(q[1]) / segs, float(q[0])))
				st.add_vertex(rings[q[0]][q[1]])
	return st.commit()
