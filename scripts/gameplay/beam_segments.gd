class_name BeamSegments
extends RefCounted
## Helpers for glowing light beams drawn as stretched cylinders.

static var _materials: Dictionary = {}


static func beam_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/light_beam.gdshader")
	m.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_materials[key] = m
	return m


## Positions a unit-height cylinder mesh instance so it spans from -> to.
static func place_segment(segment: Node3D, from: Vector3, to: Vector3, width: float = 1.0) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.01:
		segment.visible = false
		return
	var up := dir / length
	var side := up.cross(Vector3.UP)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var forward := side.cross(up).normalized()
	var basis := Basis(side * width, up * length, forward * width)
	segment.global_transform = Transform3D(basis, (from + to) * 0.5)
