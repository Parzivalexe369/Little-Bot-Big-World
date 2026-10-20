class_name CameraRig
extends Node3D
## Third-person follow camera: smoothed follow, mouse/stick orbit with limits, scroll zoom,
## sphere-cast collision that pulls in fast and eases back out, gentle auto-follow,
## and a cinematic override for scripted moments.

@export var target_path: NodePath
@export var follow_responsiveness := 12.0
@export var height_offset := 0.62
@export var default_distance := 3.6
@export var min_distance := 1.6
@export var max_distance := 7.5
@export var zoom_step := 0.45
@export var pitch_min_deg := -62.0
@export var pitch_max_deg := 32.0
@export var mouse_sensitivity := 0.0024
@export var stick_sensitivity := 2.6
@export var collision_radius := 0.22
@export var collision_mask := 1 | (1 << 5)
## Presentation: hops are followed more softly than horizontal motion, the camera leads a
## little in the direction of travel, and speed adds a slight FOV / distance kick.
@export var vertical_responsiveness := 6.0
@export var look_ahead := 0.11
@export var max_look_ahead := 0.9
@export var speed_fov_kick := 7.0
@export var speed_distance_kick := 0.55

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(-14.0)
var input_enabled := true
var desired_distance := 3.6

var camera: Camera3D
var _pivot: Node3D
var _current_distance := 3.6
var _follow_pos := Vector3.ZERO
var _idle_input_time := 10.0
var _shake := 0.0
var _shake_time := 0.0
var _cinematic := false
var _cine_tween: Tween
var _exclude: Array[RID] = []
var _cast_params: PhysicsShapeQueryParameters3D
var _lead := Vector3.ZERO
var _speed_t := 0.0
var _dip := 0.0
var _dip_vel := 0.0


func _ready() -> void:
	top_level = true
	# The rig is driven in _process from the interpolated target, so it must not be
	# interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.05
	camera.far = 1200.0
	_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pivot.add_child(camera)
	camera.make_current()
	desired_distance = default_distance
	_current_distance = default_distance
	if target_path:
		set_target(get_node(target_path) as Node3D)
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func set_target(node: Node3D) -> void:
	target = node
	_exclude.clear()
	if target is CollisionObject3D:
		_exclude.append((target as CollisionObject3D).get_rid())
	if target:
		snap_to_target()


func snap_to_target() -> void:
	if target == null:
		return
	_follow_pos = _target_position() + Vector3.UP * height_offset
	global_position = _follow_pos
	_update_transform(1.0, true)


## Point the camera behind a given facing yaw (radians, Godot convention).
func set_yaw_behind(facing_yaw: float, new_pitch_deg: float = -14.0) -> void:
	yaw = facing_yaw
	pitch = deg_to_rad(new_pitch_deg)


## Follow the robot's interpolated position so the camera stays smooth at any frame rate.
func _target_position() -> Vector3:
	return target.get_global_transform_interpolated().origin if target.is_inside_tree() else target.global_position


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


## A soft downward bob (landings), settled by a damped spring.
func add_dip(amount: float) -> void:
	_dip_vel -= amount * 1.6


func _apply_settings() -> void:
	if camera:
		camera.fov = Settings.fov + speed_fov_kick * _speed_t


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _cinematic:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).screen_relative
		var sens := mouse_sensitivity * Settings.mouse_sensitivity
		yaw -= motion.x * sens * (-1.0 if Settings.invert_x else 1.0)
		pitch -= motion.y * sens * (-1.0 if Settings.invert_y else 1.0)
		_idle_input_time = 0.0
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			desired_distance = clampf(desired_distance - zoom_step, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			desired_distance = clampf(desired_distance + zoom_step, min_distance, max_distance)


func _process(delta: float) -> void:
	if _cinematic:
		_apply_shake(delta)
		return
	if input_enabled:
		var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if stick.length() > 0.0:
			var sens := stick_sensitivity * Settings.mouse_sensitivity
			yaw -= stick.x * sens * delta * (-1.0 if Settings.invert_x else 1.0)
			pitch -= stick.y * sens * 0.7 * delta * (-1.0 if Settings.invert_y else 1.0)
			_idle_input_time = 0.0
		if Input.is_action_pressed("zoom_in"):
			desired_distance = clampf(desired_distance - zoom_step * 4.0 * delta, min_distance, max_distance)
		if Input.is_action_pressed("zoom_out"):
			desired_distance = clampf(desired_distance + zoom_step * 4.0 * delta, min_distance, max_distance)
	_idle_input_time += delta
	pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	if target:
		var body := target as CharacterBody3D
		var planar := Vector3(body.velocity.x, 0.0, body.velocity.z) if body else Vector3.ZERO
		_lead = _lead.lerp((planar * look_ahead).limit_length(max_look_ahead), 1.0 - exp(-delta * 2.5))
		var speed_goal := clampf((planar.length() - 4.5) / 3.5, 0.0, 1.0)
		_speed_t = lerpf(_speed_t, speed_goal, 1.0 - exp(-delta * 2.2))
		camera.fov = Settings.fov + speed_fov_kick * _speed_t
		var goal := _target_position() + Vector3.UP * height_offset + _lead
		var kh := 1.0 - exp(-delta * follow_responsiveness)
		var kv := 1.0 - exp(-delta * vertical_responsiveness)
		_follow_pos = Vector3(lerpf(_follow_pos.x, goal.x, kh), lerpf(_follow_pos.y, goal.y, kv), lerpf(_follow_pos.z, goal.z, kh))
		# Never lag so far that the robot leaves the frame.
		if _follow_pos.distance_to(goal) > 2.5:
			_follow_pos = goal + (_follow_pos - goal).normalized() * 2.5
		global_position = _follow_pos
		_auto_follow(delta)
	_update_transform(delta, false)
	_apply_shake(delta)


## When the robot moves and the player isn't steering the camera, drift behind it slowly.
func _auto_follow(delta: float) -> void:
	if not Settings.camera_assist or _idle_input_time < 1.6:
		return
	var body := target as CharacterBody3D
	if body == null:
		return
	var vel := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if vel.length() < 2.0:
		return
	var travel_yaw := atan2(-vel.x, -vel.z)
	var diff := wrapf(travel_yaw - yaw, -PI, PI)
	# Only assist for gentle angles; running toward the camera shouldn't spin it around.
	if absf(diff) > deg_to_rad(110.0):
		return
	yaw += diff * (1.0 - exp(-delta * 0.9)) * clampf(vel.length() / 6.0, 0.0, 1.0)


func _update_transform(delta: float, instant: bool) -> void:
	_pivot.rotation = Vector3(pitch, yaw, 0.0)
	var origin := global_position
	var back := _pivot.global_basis.z
	var wanted := desired_distance + speed_distance_kick * _speed_t
	var allowed := _collision_distance(origin, back, wanted)
	if instant:
		_current_distance = allowed
	elif allowed < _current_distance:
		_current_distance = lerpf(_current_distance, allowed, 1.0 - exp(-delta * 30.0))
	else:
		_current_distance = lerpf(_current_distance, allowed, 1.0 - exp(-delta * 3.5))
	camera.position = Vector3(0.0, 0.0, _current_distance)
	# Keep the camera above the ground even when pitched low.
	var cam_global := camera.global_position
	var ground: float = WorldTerrain.height_at_world(cam_global.x, cam_global.z) if WorldTerrain.is_ready() else -INF
	if cam_global.y < ground + 0.35:
		camera.global_position = Vector3(cam_global.x, ground + 0.35, cam_global.z)
		camera.look_at(origin)
	else:
		camera.rotation = Vector3.ZERO


func _collision_distance(origin: Vector3, back: Vector3, wanted: float) -> float:
	var space := get_world_3d().direct_space_state
	if _cast_params == null:
		var shape := SphereShape3D.new()
		shape.radius = collision_radius
		_cast_params = PhysicsShapeQueryParameters3D.new()
		_cast_params.shape = shape
	_cast_params.transform = Transform3D(Basis.IDENTITY, origin)
	_cast_params.motion = back * wanted
	_cast_params.collision_mask = collision_mask
	_cast_params.exclude = _exclude
	var result := space.cast_motion(_cast_params)
	if result.is_empty():
		return wanted
	var safe: float = result[0]
	return maxf(wanted * safe - 0.05, 0.35)


func _apply_shake(delta: float) -> void:
	# Damped spring for the landing dip.
	_dip_vel += (-_dip * 90.0 - _dip_vel * 13.0) * delta
	_dip += _dip_vel * delta
	if absf(_dip) < 0.0005 and absf(_dip_vel) < 0.001:
		_dip = 0.0
		_dip_vel = 0.0
	if _shake <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = _dip
		return
	_shake_time += delta * 30.0
	var amount := _shake * _shake * 0.12
	camera.h_offset = sin(_shake_time * 1.3) * amount
	camera.v_offset = cos(_shake_time * 1.7) * amount + _dip
	_shake = maxf(_shake - delta * 1.6, 0.0)


# --- Cinematics ---------------------------------------------------------------

func is_cinematic() -> bool:
	return _cinematic


## Moves the camera along a list of {position, look, time} shots. Awaitable.
func play_shots(shots: Array, ease_back: bool = true) -> void:
	_cinematic = true
	var start := camera.global_transform
	camera.top_level = true
	camera.global_transform = start
	for shot: Dictionary in shots:
		var dest := Transform3D(Basis.IDENTITY, shot["position"])
		dest = dest.looking_at(shot["look"], Vector3.UP)
		var duration: float = shot.get("time", 2.0)
		_cine_tween = create_tween()
		_cine_tween.tween_method(_blend_camera.bind(camera.global_transform, dest), 0.0, 1.0, duration)
		await _cine_tween.finished
		var hold: float = shot.get("hold", 0.0)
		if hold > 0.0:
			await get_tree().create_timer(hold).timeout
	if ease_back:
		await end_cinematic()


func end_cinematic(duration: float = 1.2) -> void:
	if not _cinematic:
		return
	_update_transform(1.0, true)
	camera.top_level = false
	var local_target := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, _current_distance))
	var from := _pivot.global_transform.affine_inverse() * camera.global_transform
	camera.transform = from
	_cine_tween = create_tween()
	_cine_tween.tween_method(func(t: float) -> void:
		camera.transform = from.interpolate_with(local_target, t), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _cine_tween.finished
	_cinematic = false


func _blend_camera(t: float, from: Transform3D, to: Transform3D) -> void:
	var s := t * t * (3.0 - 2.0 * t)
	camera.global_transform = from.interpolate_with(to, s)
