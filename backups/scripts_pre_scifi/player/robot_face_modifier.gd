class_name RobotFaceModifier
extends SkeletonModifier3D
## Procedural personality layered on top of the authored animations:
## eye display drifts toward points of interest (and glances around when idle), occasional
## blinks, expressions (happy, squint, wide, focus, hurt) made by reshaping the LED eyes,
## and springy antennas that lag behind sudden movement and react to impacts.

## World-space point the eyes should drift toward (null-like when far away).
var look_target := Vector3.ZERO
var has_look_target := false
## Acceleration in the robot's local space, fed by the player controller.
var local_acceleration := Vector3.ZERO
var blink_enabled := true
## Held expression (e.g. &"focus" while boosting); timed ones from express() override it.
var base_expression: StringName = &""
## Allow idle glances when nothing interesting is nearby.
var glances_enabled := true

const EXPRESSIONS := {
	# eye scale (width, height) and vertical offset. (Tilting the dotted LED bars shears
	# them, so expressions use size, position, motion and brightness instead.)
	&"": [Vector2(1.0, 1.0), 0.0],
	&"happy": [Vector2(1.12, 0.45), 0.011],
	&"squint": [Vector2(1.06, 0.55), -0.002],
	&"wide": [Vector2(1.12, 1.14), 0.003],
	&"focus": [Vector2(1.0, 0.74), -0.003],
	&"hurt": [Vector2(0.9, 0.62), -0.006],
}

var _eye_bones: PackedInt32Array = []
var _antenna_bones: PackedInt32Array = []
var _eye_offset := Vector3.ZERO
var _blink := 1.0
var _blink_timer := 2.5
var _blink_phase := -1.0
var _antenna_angle := Vector2.ZERO
var _antenna_velocity := Vector2.ZERO
var _expression: StringName = &""
var _expression_time := 0.0
var _eye_scale := Vector2.ONE
var _eye_raise := 0.0
var _glance := Vector3.ZERO
var _glance_timer := 2.0
var _hurt_time := 0.0


## Shows an expression for a while, then returns to the base expression.
func express(kind: StringName, duration: float = 0.6) -> void:
	if not EXPRESSIONS.has(kind):
		return
	_expression = kind
	_expression_time = duration
	if kind == &"hurt":
		_hurt_time = duration


## Pushes the antennas (x: forward/back, y: sideways), e.g. on landing or a bump.
func kick_antennas(impulse: Vector2) -> void:
	_antenna_velocity += impulse


func _validate_bone_names() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_eye_bones.clear()
	_antenna_bones.clear()
	for bone_name in ["eye.L", "eye.R"]:
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			_eye_bones.append(idx)
	for bone_name in ["antenna_01.L", "antenna_01.R"]:
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			_antenna_bones.append(idx)


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _eye_bones.is_empty() and _antenna_bones.is_empty():
		_validate_bone_names()
	_update_expression(delta)
	_update_eyes(skel, delta)
	_update_antennas(skel, delta)


func _update_expression(delta: float) -> void:
	if _expression_time > 0.0:
		_expression_time -= delta
		if _expression_time <= 0.0:
			_expression = &""
	_hurt_time = maxf(_hurt_time - delta, 0.0)
	var kind := _expression if _expression != &"" else base_expression
	var target: Array = EXPRESSIONS.get(kind, EXPRESSIONS[&""])
	var k := 1.0 - exp(-delta * 16.0)
	_eye_scale = _eye_scale.lerp(target[0], k)
	_eye_raise = lerpf(_eye_raise, target[1], k)


func _update_eyes(skel: Skeleton3D, delta: float) -> void:
	var desired := Vector3.ZERO
	# Idle glances: every few seconds the eyes drift somewhere new, then settle back.
	if glances_enabled and not has_look_target:
		_glance_timer -= delta
		if _glance_timer <= 0.0:
			_glance_timer = randf_range(1.8, 4.5)
			_glance = Vector3(randf_range(-0.017, 0.017), randf_range(-0.006, 0.01), 0.0) if randf() < 0.7 else Vector3.ZERO
		desired = _glance
	if has_look_target and not _eye_bones.is_empty():
		var local_target := skel.global_transform.affine_inverse() * look_target
		var eye_center := skel.get_bone_global_pose(_eye_bones[0]).origin
		var dir := (local_target - eye_center).normalized()
		# Model faces +Z inside the skeleton; slide the display across X/Y only.
		desired = Vector3(clampf(dir.x, -0.7, 0.7) * 0.022, clampf(dir.y, -0.6, 0.6) * 0.016, 0.0)
	_eye_offset = _eye_offset.lerp(desired, 1.0 - exp(-delta * 6.0))

	if blink_enabled:
		_blink_timer -= delta
		if _blink_timer <= 0.0 and _blink_phase < 0.0:
			_blink_phase = 0.0
			_blink_timer = randf_range(2.2, 5.5)
		if _blink_phase >= 0.0:
			_blink_phase += delta / 0.16
			_blink = 1.0 - sin(clampf(_blink_phase, 0.0, 1.0) * PI) * 0.88
			if _blink_phase >= 1.0:
				_blink_phase = -1.0
				_blink = 1.0
	var jitter := Vector3.ZERO
	if _hurt_time > 0.0:
		jitter = Vector3(sin(Time.get_ticks_msec() * 0.09), cos(Time.get_ticks_msec() * 0.11), 0.0) * 0.004
	for bone in _eye_bones:
		var pose := skel.get_bone_global_pose(bone)
		pose.origin += _eye_offset + Vector3(0.0, _eye_raise, 0.0) + jitter
		# Scale in the eye bone's own frame (X across the LED bar, Z up it, Y out of the
		# visor), so both eyes keep clean, symmetric shapes on the curved face.
		pose.basis = pose.basis * Basis.from_scale(Vector3(_eye_scale.x, 1.0, _blink * _eye_scale.y))
		skel.set_bone_global_pose(bone, pose)


func _update_antennas(skel: Skeleton3D, delta: float) -> void:
	# Damped spring driven by acceleration: antennas sway opposite to the push.
	var push := Vector2(-local_acceleration.z, local_acceleration.x) * 0.012
	var stiffness := 90.0
	var damping := 9.0
	var accel := -_antenna_angle * stiffness - _antenna_velocity * damping + push * stiffness
	_antenna_velocity += accel * delta
	_antenna_angle += _antenna_velocity * delta
	_antenna_angle = _antenna_angle.limit_length(0.45)
	for bone in _antenna_bones:
		var pose := skel.get_bone_global_pose(bone)
		var tilt := Basis(Vector3.RIGHT, _antenna_angle.x) * Basis(Vector3.FORWARD, _antenna_angle.y)
		pose.basis = tilt * pose.basis
		skel.set_bone_global_pose(bone, pose)
