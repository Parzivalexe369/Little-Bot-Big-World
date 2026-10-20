class_name BeamMirror
extends Device
## A rotatable mirror on a pedestal. Each use turns it 45 degrees. Its rotation is saved.

@export var start_step := 0
@export var crystal_style := false

var _head: Node3D
var _step := 0
var _turning := false


func _build() -> void:
	var prop := PropLibrary.place(self, "mirror_pedestal", Vector3.ZERO, 0.0, 1.0, false)
	PropLibrary.add_collision(prop, "mirror_pedestal", true)
	_head = prop.get_node_or_null("mirror_head") as Node3D
	if crystal_style and _head:
		for mi in _head.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				if m.mesh.surface_get_material(s) == PropLibrary.material("metal_gold"):
					m.set_surface_override_material(s, PropLibrary.material("crystal_teal"))
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 6
	body.collision_mask = 0
	_head.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 2.0, 0.14)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	body.add_child(shape)
	interactable = make_interactable("Turn the mirror", 1.7, Vector3(0, 1.4, 0))
	interactable.robot_action = &"Attack"
	interactable.interacted.connect(_on_used)
	add_to_group(&"scannable")


func _restore_state() -> void:
	_step = int(GameState.get_puzzle_state(device_id, start_step))
	_head.rotation.y = _step * PI * 0.25


## Reflective face normal (the mirror side faces the head's -Z).
func mirror_normal() -> Vector3:
	var n := -_head.global_basis.z
	n.y = 0.0
	return n.normalized()


func on_scanned(_origin: Vector3) -> void:
	ScanHighlight.flash_node(_head)


func _on_used(_player: Node) -> void:
	if _turning:
		return
	_turning = true
	_step = (_step + 1) % 8
	GameState.set_puzzle_state(device_id, _step)
	Audio.play_sfx_3d(&"mirror_turn", global_position + Vector3.UP, -2.0)
	var tween := create_tween()
	var target := _head.rotation.y + PI * 0.25
	tween.tween_property(_head, "rotation:y", target, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		_head.rotation.y = wrapf(target, 0.0, TAU)
		_turning = false)
	SaveSystem.request_save(3.0)
