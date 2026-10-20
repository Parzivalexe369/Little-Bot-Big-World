class_name WaterHazard
extends Area3D
## Deep water the robot shouldn't be in (the ravine). Short power-cycle, then it reappears
## at the last safe spot. Never a fail state, just a gentle bump.

@export var size := Vector3(10, 4, 10)

var _busy := false


func _ready() -> void:
	collision_layer = 1 << 4
	collision_mask = 1 << 1
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null or _busy:
		return
	_busy = true
	Audio.play_sfx(&"splash", -2.0)
	player.input_enabled = false
	await SceneRouter.fade_through(func() -> void:
		player.respawn_at(player.last_safe_position)
		player.visual.power_cycle(), 0.4)
	player.input_enabled = GameState.in_gameplay
	_busy = false
