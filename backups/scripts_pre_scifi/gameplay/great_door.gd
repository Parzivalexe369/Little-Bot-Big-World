class_name GreatDoor
extends Device
## Massive stone doors that swing open when a flag is set (the shrine's restoration).

@export var open_flag: StringName = &"shrine_restored"

var _left: Node3D
var _right: Node3D
var _blocker: CollisionShape3D
var _open := false


func _build() -> void:
	var prop := PropLibrary.place(self, "great_door", Vector3.ZERO, 0.0, 1.0, false)
	PropLibrary.add_collision(prop, "great_door", true)
	_left = prop.get_node_or_null("great_door_left") as Node3D
	_right = prop.get_node_or_null("great_door_right") as Node3D
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	_blocker = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.6, 10.0, 0.8)
	_blocker.shape = box
	_blocker.position = Vector3(0, 5.0, 0)
	body.add_child(_blocker)
	for side in [-1.0, 1.0]:
		var wall := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(16.0, 12.0, 3.0)
		wall.shape = wall_box
		wall.position = Vector3(side * 15.0, 5.0, 0.0)
		body.add_child(wall)
		for k in 2:
			PropLibrary.place(self, "wall_full" if k == 0 else "pillar_broken", Vector3(side * (9.5 + k * 4.5), 0, 0.4), 0.0 if k == 0 else randf() * 360.0, 1.0, false)
	GameState.flag_changed.connect(_on_flag)


func _restore_state() -> void:
	_open = GameState.has_flag(open_flag)
	if _open:
		_apply(false)
	else:
		PropLibrary.set_power(self, 0.0)


func _on_flag(flag: StringName, value: Variant) -> void:
	if flag == open_flag and value and not _open:
		_open = true
		_apply(true)


func open_now() -> void:
	if not _open:
		_open = true
		_apply(true)


func _apply(animate: bool) -> void:
	_blocker.set_deferred("disabled", true)
	var angle := deg_to_rad(100.0)
	if not animate:
		if _left:
			_left.rotation.y = angle
		if _right:
			_right.rotation.y = -angle
		PropLibrary.set_power(self, 1.0)
		return
	tween_power(self, 0.0, 1.0, 1.5)
	Audio.play_sfx_3d(&"door_rumble", global_position + Vector3.UP * 3.0, 2.0)
	var tween := create_tween().set_parallel(true)
	if _left:
		tween.tween_property(_left, "rotation:y", angle, 4.5).set_delay(1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _right:
		tween.tween_property(_right, "rotation:y", -angle, 4.5).set_delay(1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
