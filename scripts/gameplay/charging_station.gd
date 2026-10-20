class_name ChargingStation
extends Device
## The abandoned dock where the robot wakes up. Its pad and lamp come back on once the
## robot is awake; it doubles as the first checkpoint.

var _prop: Node3D
var _lamp: OmniLight3D


func _build() -> void:
	_prop = PropLibrary.place(self, "charging_station", Vector3.ZERO, 180.0, 1.0, false)
	# Simple colliders: a low pad the robot rests on and the pillar behind it.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var pad := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.82
	cyl.height = 0.12
	pad.shape = cyl
	pad.position = Vector3(0, 0.06, 0)
	body.add_child(pad)
	var pillar := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.36, 1.5, 0.3)
	pillar.shape = box
	pillar.position = Vector3(0, 0.75, 0.72)
	body.add_child(pillar)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, 1.55, -0.22)
	_lamp.light_color = Color(1.0, 0.82, 0.55)
	_lamp.light_energy = 0.0
	_lamp.omni_range = 4.5
	_lamp.shadow_enabled = true
	add_child(_lamp)
	GameState.flag_changed.connect(_on_flag)


func _restore_state() -> void:
	var on := GameState.has_flag(&"robot_awake")
	PropLibrary.set_power(_prop, 1.0 if on else 0.0)
	_lamp.light_energy = 1.2 if on else 0.0


func dock_transform() -> Transform3D:
	return global_transform


func _on_flag(flag: StringName, value: Variant) -> void:
	if flag == &"robot_awake" and value:
		tween_power(_prop, 0.0, 1.0, 1.5)
		var tween := create_tween()
		tween.tween_property(_lamp, "light_energy", 1.2, 1.5)
