class_name BeamReceiver
extends Node3D
## A crystal lens that wakes something when a light beam rests on it for a moment.
## Emits `activated` once; the activation is remembered through `solved_flag`.

signal activated

@export var solved_flag: StringName = &""
@export var target_path: NodePath
@export var hold_time := 0.6
@export var size := Vector3(1.2, 2.0, 1.2)
## Height of the lens above the ground (matches emitter lens height).
@export var ground_offset := 1.55

var _charge := 0.0
var _hit_this_frame := false
var _solved := false
var _gem: MeshInstance3D


func _ready() -> void:
	WorldTerrain.snap_node(self, ground_offset)
	_build_post()
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 6
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_gem = MeshInstance3D.new()
	_gem.mesh = PropLibrary.mesh("energy_fragment")
	_gem.scale = Vector3.ONE * 2.2
	_gem.position = Vector3(0, -0.3, 0)
	_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gem)
	_solved = solved_flag != &"" and GameState.has_flag(solved_flag)
	_gem.set_instance_shader_parameter(&"power", 1.0 if _solved else 0.1)


func _build_post() -> void:
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.22
	cyl.height = ground_offset - 0.35
	post.mesh = cyl
	post.material_override = PropLibrary.material("stone_dark")
	post.position = Vector3(0, -ground_offset + cyl.height * 0.5, 0)
	add_child(post)


func receive_beam(_delta: float) -> void:
	_hit_this_frame = true


func _physics_process(delta: float) -> void:
	if _solved:
		_gem.rotation.y += delta * 1.5
		return
	if _hit_this_frame:
		_charge += delta
	else:
		_charge = maxf(_charge - delta * 2.0, 0.0)
	_hit_this_frame = false
	_gem.set_instance_shader_parameter(&"power", 0.1 + 0.9 * clampf(_charge / hold_time, 0.0, 1.0))
	if _charge >= hold_time:
		_solved = true
		if solved_flag != &"":
			GameState.set_flag(solved_flag, true)
		Audio.play_sfx_3d(&"puzzle_solved", global_position, 0.0)
		add_child(FxFactory.burst(Color(1.0, 0.9, 0.6), 30))
		var target := get_node_or_null(target_path)
		if target and target.has_method("activate"):
			target.call("activate", true)
		activated.emit()
