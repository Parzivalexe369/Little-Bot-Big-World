class_name ScifiDetail
extends RefCounted
## Batches purely visual architectural detail (structural ribs, frames, beams, braces, pipes,
## bolts, cable runs, distant megastructure) into one mesh per material, so hundreds of
## pieces cost a handful of draw calls. Nothing here has collision: routes and puzzles keep
## exactly the collision they had.

var _parent: Node3D
var _tools: Dictionary = {}      # material key -> SurfaceTool
var _materials: Dictionary = {}  # material key -> Material
var shadows := true


func _init(parent: Node3D) -> void:
	_parent = parent


## Material for a key: "style:<name>" (architecture), "glow:<rrggbb>:<energy>", or a prop
## material name ("sf_metal", "sf_dark", ...).
func _material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var m: Material
	if key.begins_with("style:"):
		m = ScifiKit.style(StringName(key.substr(6)))
	elif key.begins_with("glow:"):
		var parts := key.split(":")
		m = ScifiKit.glow(Color(parts[1]), float(parts[2]))
	else:
		m = ScifiKit.material(key)
	_materials[key] = m
	return m


func _tool(key: String) -> SurfaceTool:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
	return _tools[key]


static func glow_key(color: Color, energy: float) -> String:
	return "glow:%s:%.2f" % [color.to_html(false), energy]


## A chamfered box (size in its local frame) placed by `xform`.
func box(key: String, size: Vector3, xform: Transform3D, chamfer := 0.02) -> void:
	var st := _tool(key)
	var mesh := ScifiKit.bevel_box(size, chamfer)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var basis := xform.basis
	var nb := basis.inverse().transposed()
	if indices.is_empty():
		for i in verts.size():
			st.set_color(colors[i] if not colors.is_empty() else Color.BLACK)
			st.set_normal((nb * normals[i]).normalized())
			st.add_vertex(xform * verts[i])
	else:
		for i in indices:
			st.set_color(colors[i] if not colors.is_empty() else Color.BLACK)
			st.set_normal((nb * normals[i]).normalized())
			st.add_vertex(xform * verts[i])


## Axis-aligned chamfered box by center and size.
func box_at(key: String, size: Vector3, center: Vector3, chamfer := 0.02) -> void:
	box(key, size, Transform3D(Basis.IDENTITY, center), chamfer)


## A cylinder from a to b (pipes, cables, rods, bolts).
func cylinder(key: String, a: Vector3, b: Vector3, radius: float, segments := 10, caps := true) -> void:
	var st := _tool(key)
	var axis := b - a
	var length := axis.length()
	if length < 0.001:
		return
	var up := axis / length
	var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var n0 := side * cos(a0) + fwd * sin(a0)
		var n1 := side * cos(a1) + fwd * sin(a1)
		_vert(st, a + n0 * radius, n0)
		_vert(st, b + n1 * radius, n1)
		_vert(st, b + n0 * radius, n0)
		_vert(st, a + n0 * radius, n0)
		_vert(st, a + n1 * radius, n1)
		_vert(st, b + n1 * radius, n1)
		if caps:
			_vert(st, b, up)
			_vert(st, b + n0 * radius, up)
			_vert(st, b + n1 * radius, up)
			_vert(st, a, -up)
			_vert(st, a + n1 * radius, -up)
			_vert(st, a + n0 * radius, -up)


## A pipe run through points with flanged joints.
func pipe(key: String, points: Array, radius: float, flange_key := "", segments := 10) -> void:
	for i in points.size() - 1:
		cylinder(key, points[i], points[i + 1], radius, segments, false)
	if flange_key != "":
		for i in points.size():
			var p: Vector3 = points[i]
			var dir: Vector3 = ((points[mini(i + 1, points.size() - 1)] as Vector3) - (points[maxi(i - 1, 0)] as Vector3)).normalized()
			cylinder(flange_key, p - dir * 0.04, p + dir * 0.04, radius * 1.45, segments)


## A sagging cable between two points.
func cable(key: String, a: Vector3, b: Vector3, sag: float, radius: float, steps := 10) -> void:
	var prev := a
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		cylinder(key, prev, p, radius, 6, false)
		prev = p


func _vert(st: SurfaceTool, p: Vector3, n: Vector3) -> void:
	st.set_color(Color.BLACK)
	st.set_normal(n)
	st.add_vertex(p)


## Builds the meshes. Call once after adding everything.
func commit() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for key: String in _tools:
		var st: SurfaceTool = _tools[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _material(key)
		mi.name = "Detail_" + key.replace(":", "_")
		if key.begins_with("glow:") or not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parent.add_child(mi)
		out.append(mi)
	_tools.clear()
	return out
