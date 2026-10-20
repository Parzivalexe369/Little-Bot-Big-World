class_name ScanPulse
extends Node3D
## The scanner wave: an expanding translucent shell plus a global shader ring that sweeps
## across terrain and props. Objects in the "scannable" group receive `on_scanned(origin)`
## exactly when the wavefront reaches them, so reveals ripple outward naturally.

const SHELL_SHADER := preload("res://shaders/scan_shell.gdshader")

var radius := 26.0
var speed := 22.0
var _origin := Vector3.ZERO
var _time := 0.0
var _pending: Array = []
var _shell: MeshInstance3D
var _material: ShaderMaterial


static func emit_pulse(tree: SceneTree, origin: Vector3, pulse_radius: float, pulse_speed: float) -> ScanPulse:
	var pulse := ScanPulse.new()
	pulse.radius = pulse_radius
	pulse.speed = pulse_speed
	pulse._origin = origin
	var parent := tree.current_scene if tree.current_scene else tree.root
	parent.add_child(pulse)
	pulse.global_position = origin
	return pulse


func _ready() -> void:
	RenderingServer.global_shader_parameter_set(&"scan_origin", _origin)
	RenderingServer.global_shader_parameter_set(&"scan_time", 0.0)
	_material = ShaderMaterial.new()
	_material.shader = SHELL_SHADER
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_shell = MeshInstance3D.new()
	_shell.mesh = sphere
	_shell.material_override = _material
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)
	for node in get_tree().get_nodes_in_group(&"scannable"):
		var n3 := node as Node3D
		if n3 == null or not n3.has_method("on_scanned"):
			continue
		var d := n3.global_position.distance_to(_origin)
		if d <= radius:
			_pending.append([d, n3])
	_pending.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _process(delta: float) -> void:
	_time += delta
	RenderingServer.global_shader_parameter_set(&"scan_time", _time)
	var front := _time * speed
	_shell.scale = Vector3.ONE * maxf(front, 0.01)
	_material.set_shader_parameter("fade", 1.0 - clampf(front / radius, 0.0, 1.0))
	while not _pending.is_empty() and _pending[0][0] <= front:
		var entry: Array = _pending.pop_front()
		# The object may have been freed since the pulse started (e.g. a collected fragment).
		if is_instance_valid(entry[1]) and entry[1].has_method("on_scanned"):
			entry[1].call("on_scanned", _origin)
	if front > radius + 4.0:
		queue_free()
