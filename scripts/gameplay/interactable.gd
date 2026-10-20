@tool
class_name Interactable
extends Area3D
## Something the robot can use with the interact button. Add as a child of a device and
## connect `interacted`. The Interactor on the player decides which one is in focus.

signal interacted(player: Node)
signal focus_changed(focused: bool)

@export var prompt := "Interact"
## Shown (dimmed) instead of the prompt while `locked` is true, e.g. "Needs 3 energy".
@export var locked_prompt := ""
@export var locked := false
@export var enabled := true
## Point used for line-of-sight checks and the robot's gaze, relative to this node.
@export var focus_offset := Vector3(0, 0.4, 0)
@export var radius := 1.4:
	set(value):
		radius = value
		_update_shape()
## Animation the robot plays when using this (empty = none).
@export var robot_action: StringName = &"Attack"

var _focused := false


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	_update_shape()


func _update_shape() -> void:
	if not is_inside_tree():
		return
	var shape_node := get_node_or_null("Shape") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "Shape"
		add_child(shape_node)
	var sphere := shape_node.shape as SphereShape3D
	if sphere == null:
		sphere = SphereShape3D.new()
		shape_node.shape = sphere
	sphere.radius = radius


func is_available() -> bool:
	return enabled and is_visible_in_tree()


func get_prompt() -> String:
	return locked_prompt if locked and locked_prompt != "" else prompt


func get_focus_point() -> Vector3:
	return global_transform * focus_offset


func set_focused(value: bool) -> void:
	if value == _focused:
		return
	_focused = value
	focus_changed.emit(value)


func interact(player: Node) -> void:
	if not is_available():
		return
	interacted.emit(player)
