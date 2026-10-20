class_name ValveSwitch
extends Device
## An old valve hidden under moss. A cable leads from it to the bridge machine; the scanner
## uncovers it, turning it lights the cable and adds to the bridge's power.

@export var set_flag_name: StringName = &"forest_switches"
@export var hidden_until_scanned := true
## Cable route in world XZ from this switch to the machine (first point is added automatically).
@export var cable_points: PackedVector2Array = []

var _valve: Node3D
var _wheel: Node3D
var _mound: Node3D
var _cable: CableLine
var _revealed := false
var _on := false


func _build() -> void:
	_valve = PropLibrary.place(self, "valve_switch", Vector3.ZERO, 0.0, 1.0, false)
	PropLibrary.add_collision(_valve, "valve_switch", true)
	_wheel = _valve.get_node_or_null("valve_wheel") as Node3D
	_mound = PropLibrary.place(self, "rock_moss_a", Vector3(0, -0.5, 0), randf() * 360.0, 0.42, false)
	interactable = make_interactable("Turn the valve", 1.5, Vector3(0, 0.8, 0))
	interactable.interacted.connect(_on_used)
	if not cable_points.is_empty():
		_cable = CableLine.new()
		var pts := PackedVector2Array([Vector2(global_position.x, global_position.z)])
		pts.append_array(cable_points)
		_cable.points = pts
		add_child(_cable)
	add_to_group(&"scannable")


func _restore_state() -> void:
	_on = GameState.set_has(set_flag_name, device_id)
	_revealed = _on or not hidden_until_scanned or GameState.is_revealed(device_id)
	_apply_revealed(false)
	PropLibrary.set_power(_valve, 1.0 if _on else 0.0)
	if _cable:
		_cable.set_power(1.0 if _on else 0.0, false)
	interactable.enabled = _revealed and not _on


func is_hidden_unrevealed() -> bool:
	return not _revealed


func on_scanned(_origin: Vector3) -> void:
	if not _revealed:
		_revealed = true
		GameState.mark_revealed(device_id)
		_apply_revealed(true)
		interactable.enabled = not _on
		Audio.play_sfx_3d(&"reveal", global_position, 0.0)
		Events.toast("Something stirs beneath the moss.", "info")
	ScanHighlight.flash_node(_valve)
	if _cable and not _on:
		ScanHighlight.flash(_cable)


func _apply_revealed(animate: bool) -> void:
	if not animate:
		_valve.position.y = 0.0 if _revealed else -1.1
		_valve.visible = _revealed
		_mound.visible = not _revealed
		return
	_valve.visible = true
	_valve.position.y = -1.1
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_valve, "position:y", 0.0, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_mound, "scale", Vector3.ONE * 0.01, 0.9)
	tween.chain().tween_callback(func() -> void: _mound.visible = false)
	add_child(FxFactory.burst(Color(0.45, 0.7, 0.3), 30, 2.0, 0.25))


func _on_used(_player: Node) -> void:
	if _on or not _revealed:
		return
	_on = true
	interactable.enabled = false
	var count := GameState.add_to_set(set_flag_name, device_id)
	Audio.play_sfx_3d(&"valve", global_position, 0.0)
	if _wheel:
		var tween := create_tween()
		tween.tween_property(_wheel, "rotation:y", _wheel.rotation.y + TAU * 1.5, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.9).timeout
	tween_power(_valve, 0.0, 1.0, 0.6)
	Audio.play_sfx_3d(&"switch_on", global_position, -2.0)
	if _cable:
		_cable.set_power(1.0, true, 2.2)
	Events.toast("Old switch restored  (%d/%d)" % [count, GameData.FOREST_SWITCH_COUNT], "energy")
	SaveSystem.request_save(0.5)
