@tool
class_name EnergyFragment
extends Area3D
## A collectible spark of energy. Collected by touching it. Hidden fragments stay invisible
## (with only a faint shimmer in the air) until the scanner reveals them.

@export var fragment_id: StringName = &"":
	set(value):
		fragment_id = value
		update_configuration_warnings()
@export var hidden_until_scanned := false
@export var ground_offset := 0.9
@export var snap_to_ground := true

var _visual: Node3D
var _mesh: MeshInstance3D
var _light: OmniLight3D
var _sparkles: GPUParticles3D
var _collected := false
var _revealed := true
var _time := 0.0
var _base_y := 0.0


func _get_configuration_warnings() -> PackedStringArray:
	if fragment_id == &"":
		return ["Give this fragment a unique fragment_id like 'meadow_1'."]
	return []


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_visual()
		return
	add_to_group(&"fragments")
	collision_layer = 1 << 3
	collision_mask = 1 << 1
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.75
	shape.shape = sphere
	add_child(shape)
	if snap_to_ground:
		WorldTerrain.snap_node(self, ground_offset)
	if GameState.has_fragment(fragment_id):
		queue_free()
		return
	_build_visual()
	_base_y = _visual.position.y
	_time = randf() * TAU
	body_entered.connect(_on_body_entered)
	if hidden_until_scanned and not GameState.is_revealed(fragment_id):
		_revealed = false
		add_to_group(&"scannable")
		_visual.visible = false
		_light.visible = false
		monitoring = false
		_sparkles.amount_ratio = 0.25
	else:
		add_to_group(&"scannable")


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = PropLibrary.mesh("energy_fragment")
	_mesh.scale = Vector3.ONE * 1.4
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.set_instance_shader_parameter(&"power", 1.0)
	_visual.add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.95, 1.0)
	_light.light_energy = 0.9
	_light.omni_range = 3.2
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 35.0
	_light.distance_fade_length = 10.0
	add_child(_light)
	_sparkles = FxFactory.sparkles(Color(0.5, 0.95, 1.0), 10, 0.7)
	add_child(_sparkles)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _collected or _visual == null:
		return
	_time += delta
	_visual.rotation.y += delta * 1.4
	_visual.position.y = _base_y + sin(_time * 2.0) * 0.12


func is_hidden_unrevealed() -> bool:
	return not _revealed and not _collected


func on_scanned(_origin: Vector3) -> void:
	if _collected:
		return
	if not _revealed:
		reveal(true)
	else:
		ScanHighlight.flash(_mesh)


func reveal(animate: bool) -> void:
	_revealed = true
	monitoring = true
	_visual.visible = true
	_light.visible = true
	_sparkles.amount_ratio = 1.0
	GameState.mark_revealed(fragment_id)
	if animate:
		_visual.scale = Vector3.ONE * 0.01
		var tween := create_tween()
		tween.tween_property(_visual, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Audio.play_sfx_3d(&"reveal", global_position, -2.0)
		ScanHighlight.flash(_mesh)


func _on_body_entered(body: Node3D) -> void:
	if _collected or not (body is Player):
		return
	if not GameState.collect_fragment(fragment_id):
		queue_free()
		return
	_collected = true
	set_deferred("monitoring", false)
	var total := GameState.energy()
	Audio.play_sfx(&"collect", -2.0, 1.0 + minf(total, 30) * 0.01)
	add_child(FxFactory.burst(Color(0.5, 0.95, 1.0), 24))
	SaveSystem.request_save(2.0)
	var tween := create_tween().set_parallel(true)
	var target := (body as Node3D).global_position + Vector3.UP * 0.4
	tween.tween_property(_visual, "global_position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.1, 0.35)
	tween.tween_property(_light, "light_energy", 0.0, 0.35)
	tween.chain().tween_interval(0.8)
	tween.chain().tween_callback(queue_free)
