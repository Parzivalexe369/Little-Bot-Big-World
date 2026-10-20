class_name GatewayLift
extends Node3D
## The research lift beside the Crystal Heart: the way down to the three sci-fi areas.
## It stays buried until the garden is restored, then rises with a beacon of light.
## Added to the world scene as its own node; the garden level itself is unchanged.

const LIFT_DEPTH := 3.4

var _lift: Node3D
var _beacon: MeshInstance3D
var _interactable: Interactable
var _checkpoint: Checkpoint
var _raised := false


func _ready() -> void:
	WorldTerrain.snap_node(self, 0.0)
	_lift = ScifiKit.place(self, "sf_lift", Vector3.ZERO, 90.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.6
	cyl.height = 60.0
	cyl.radial_segments = 24
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beacon = ScifiKit.energy_mesh(self, cyl, Vector3(0, 30.3, 0), Color(0.35, 0.9, 1.0), Color(0.85, 1.0, 1.0), 0.9)
	(_beacon.material_override as ShaderMaterial).set_shader_parameter("flow", Vector2(0.0, -0.4))
	_interactable = Interactable.new()
	_interactable.prompt = "Ride the lift down"
	_interactable.radius = 2.4
	_interactable.focus_offset = Vector3(0, 0.9, 0)
	_interactable.robot_action = &""
	add_child(_interactable)
	_interactable.position = Vector3(0, 0.35, 0)
	_interactable.interacted.connect(_on_ride)
	_checkpoint = Checkpoint.new()
	_checkpoint.checkpoint_id = &"garden_lift"
	_checkpoint.radius = 3.0
	_checkpoint.announce = false
	_checkpoint.snap_to_ground = false
	add_child(_checkpoint)
	_checkpoint.position = Vector3(3.6, 0.1, 0)
	_checkpoint.rotation_degrees.y = 90.0
	GameState.flag_changed.connect(_on_flag_changed)
	_set_raised(GameState.has_flag(&"garden_restored"), false)


func _on_flag_changed(flag: StringName, value: Variant) -> void:
	if flag == &"garden_restored" and value and not _raised:
		# Let the finale play first, then the lift rises.
		await get_tree().create_timer(24.0).timeout
		_set_raised(true, true)


func _set_raised(on: bool, animate: bool) -> void:
	_raised = on
	visible = on
	_interactable.enabled = on
	_checkpoint.monitoring = on
	for body: StaticBody3D in _lift.find_children("*", "StaticBody3D", true, false):
		body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		_clear_scatter()
	if not animate:
		_lift.position.y = 0.0
		return
	_lift.position.y = -LIFT_DEPTH
	(_beacon.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.0)
	Audio.play_sfx_3d(&"door_rumble", global_position, 0.0)
	var tween := create_tween()
	tween.tween_property(_lift, "position:y", 0.0, 4.0).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_method(func(v: float) -> void:
		(_beacon.material_override as ShaderMaterial).set_shader_parameter("intensity", v), 0.0, 0.9, 5.0)
	await tween.finished
	Events.toast("A lift has risen beside the Crystal Heart.", "discovery")


## Hides any small garden scatter instances that would poke through the lift deck.
func _clear_scatter() -> void:
	var c := Vector2(global_position.x, global_position.z)
	for mmi: MultiMeshInstance3D in get_tree().current_scene.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := mmi.multimesh
		if mm == null:
			continue
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var p := mmi.global_transform * xf.origin
			if Vector2(p.x, p.z).distance_to(c) < 2.3:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), xf.origin))


func _on_ride(_player: Node) -> void:
	Audio.play_sfx(&"lift_move", -2.0)
	SceneRouter.travel_to(&"lab")
