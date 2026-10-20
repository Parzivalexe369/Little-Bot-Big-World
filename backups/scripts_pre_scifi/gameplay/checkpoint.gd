class_name Checkpoint
extends Area3D
## Respawn point + autosave trigger. The node's position/yaw is where the robot reappears.

@export var checkpoint_id: StringName = &"station"
@export var radius := 4.0
@export var announce := true
@export var snap_to_ground := true


func _ready() -> void:
	add_to_group(&"checkpoints")
	collision_layer = 1 << 4
	collision_mask = 1 << 1
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)
	if snap_to_ground:
		WorldTerrain.snap_node(self, 0.05)
	body_entered.connect(_on_body_entered)


func spawn_transform() -> Transform3D:
	return global_transform


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player) or not GameState.in_gameplay:
		return
	if GameState.set_checkpoint(checkpoint_id):
		SaveSystem.save_game()
		if announce:
			Events.toast("Progress saved", "save")


static func find(tree: SceneTree, id: StringName) -> Checkpoint:
	for node in tree.get_nodes_in_group(&"checkpoints"):
		var cp := node as Checkpoint
		if cp and cp.checkpoint_id == id:
			return cp
	return null
