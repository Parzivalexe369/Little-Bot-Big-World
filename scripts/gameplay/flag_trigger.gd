class_name FlagTrigger
extends Area3D
## Sets a progression flag (once) when the robot enters. Optionally grants a discovery
## or shows a toast, e.g. "saw the bridge" or reaching a scenic overlook.

@export var flag: StringName = &""
@export var discovery_id: StringName = &""
@export var message := ""
@export var size := Vector3(8, 6, 8)
@export var snap_to_ground := true


func _ready() -> void:
	collision_layer = 1 << 4
	collision_mask = 1 << 1
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5 - 1.0
	add_child(shape)
	if snap_to_ground:
		WorldTerrain.snap_node(self)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player) or not GameState.in_gameplay:
		return
	if flag != &"" and not GameState.has_flag(flag):
		GameState.set_flag(flag, true)
		if message != "":
			Events.toast(message, "info")
		SaveSystem.request_save()
	if discovery_id != &"" and GameState.add_discovery(discovery_id):
		Events.discovery_shown.emit(discovery_id)
		Audio.play_sfx(&"discovery", -3.0)
		(body as Player).visual.play_action(&"Victory")
		SaveSystem.request_save()
