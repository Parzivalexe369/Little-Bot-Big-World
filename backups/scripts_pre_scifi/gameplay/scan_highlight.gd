class_name ScanHighlight
extends RefCounted
## Brief glowing outline/fresnel overlay on objects the scanner touched.

const SHADER := preload("res://shaders/scan_highlight.gdshader")
const DURATION := 3.2


static func flash_node(root: Node, color: Color = Color(0.4, 0.95, 1.0)) -> void:
	if root == null:
		return
	var targets: Array = []
	if root is GeometryInstance3D:
		targets.append(root)
	targets.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for g in targets:
		if g is MeshInstance3D:
			flash(g as MeshInstance3D, color)


static func flash(geometry: GeometryInstance3D, color: Color = Color(0.4, 0.95, 1.0)) -> void:
	if geometry == null or not geometry.is_inside_tree():
		return
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter("strength", 1.0)
	geometry.material_overlay = m
	var tween := geometry.create_tween()
	tween.tween_method(func(v: float) -> void: m.set_shader_parameter("strength", v), 1.0, 0.0, DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if is_instance_valid(geometry) and geometry.material_overlay == m:
			geometry.material_overlay = null)
