class_name Interactor
extends Area3D
## Finds the best Interactable near the robot: close, roughly in front, and not behind a wall.

signal target_changed(target: Interactable)

@export var reach := 2.6
@export var eye_height := 0.45

var current: Interactable
var _exclude: Array[RID] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 2
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = reach
	shape.shape = sphere
	add_child(shape)
	var body := get_parent() as CollisionObject3D
	if body:
		_exclude.append(body.get_rid())


func _physics_process(_delta: float) -> void:
	var best: Interactable = null
	var best_score := INF
	var origin := global_position + Vector3.UP * eye_height
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for area in get_overlapping_areas():
		var target := area as Interactable
		if target == null or not target.is_available():
			continue
		var point := target.get_focus_point()
		var to_target := point - origin
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		var distance := flat.length()
		if distance > reach + target.radius:
			continue
		var facing := forward.dot(flat.normalized()) if distance > 0.05 else 1.0
		if facing < -0.35 and distance > 0.9:
			continue
		if not _has_line_of_sight(origin, point, target):
			continue
		var score := distance - facing * 0.9
		if score < best_score:
			best_score = score
			best = target
	if best != current:
		if is_instance_valid(current):
			current.set_focused(false)
		current = best
		if current:
			current.set_focused(true)
		target_changed.emit(current)


func _has_line_of_sight(from: Vector3, to: Vector3, target: Interactable) -> bool:
	# Stop just short of the target so grazing the ground right at it doesn't count as a wall.
	var end := to - (to - from).normalized() * 0.25
	var query := PhysicsRayQueryParameters3D.create(from, end, 1)
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	# Hitting the device's own collision is fine; anything else blocks the prompt.
	var collider := hit["collider"] as Node
	var device := target.get_parent()
	return collider != null and device != null and (collider == device or device.is_ancestor_of(collider))
