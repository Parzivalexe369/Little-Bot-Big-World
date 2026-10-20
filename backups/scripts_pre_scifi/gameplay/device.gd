class_name Device
extends Node3D
## Base for ancient machines: ground snapping, prop building, an optional interactable,
## power tweening and state restoration from GameState on load.

@export var device_id: StringName = &""
@export var snap_to_ground := true
@export var ground_offset := 0.0

var interactable: Interactable
var hum: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(&"devices")
	if snap_to_ground:
		WorldTerrain.snap_node(self, ground_offset)
	_build()
	_restore_state()


## Override: create props, colliders, interactables.
func _build() -> void:
	pass


## Override: apply saved state instantly (no animation).
func _restore_state() -> void:
	pass


func make_interactable(prompt: String, radius: float = 1.6, focus := Vector3(0, 0.8, 0), parent: Node3D = null) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt
	it.radius = radius
	it.focus_offset = focus
	(parent if parent else self).add_child(it)
	it.position = Vector3.ZERO
	return it


func tween_power(target: Node, from: float, to: float, duration: float) -> Tween:
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: PropLibrary.set_power(target, v), from, to, duration)
	return tween


func start_hum(sound: StringName = &"machine_hum", volume_db: float = -14.0) -> void:
	if hum == null:
		hum = Audio.make_loop_3d(self, sound, volume_db, 4.0, 30.0)


func energy_text(required: int) -> String:
	return "Needs %d energy  (%d/%d)" % [required, mini(GameState.energy(), required), required]


func flag_name(suffix: String = "on") -> StringName:
	return StringName("%s_%s" % [device_id, suffix])
