class_name Player
extends CharacterBody3D
## The little hover robot. Camera-relative movement with acceleration, smooth turning,
## a gentle hover hop, boost, contextual interaction and the scanner.

signal scanned(origin: Vector3)
signal interacted_with(target: Interactable)
signal respawned
## Presentation-only events (effects, camera, HUD); they don't affect gameplay.
signal hopped
signal landed(strength: float)
signal bonked(contact: Vector3)

@export_group("Movement")
@export var walk_speed := 4.3
@export var boost_speed := 7.6
@export var acceleration := 18.0
@export var deceleration := 24.0
@export var air_control := 0.55
@export var turn_speed := 11.0
@export_group("Hover hop")
@export var hop_velocity := 6.0
@export var rise_gravity := 15.0
@export var fall_gravity := 10.5
@export var max_fall_speed := 9.0
@export var coyote_time := 0.14
@export var hop_buffer_time := 0.14
@export_group("Scanner")
@export var scan_cooldown := 2.2
@export var scan_radius := 26.0
@export var scan_speed := 22.0

var input_enabled := false
## Multiplies hop gravity (1 = normal). Set by low-gravity zones in the quantum lab.
var gravity_scale := 1.0
## Below this height the robot has fallen out (used where there is no terrain).
var fall_limit := -80.0
## If set, called instead of the default "back to the last safe spot" after a fall.
var fall_respawn: Callable
var camera_rig: CameraRig
var last_safe_position := Vector3.ZERO
var scan_ready_ratio := 1.0

@onready var visual: RobotVisual = $Visual
@onready var interactor: Interactor = $Visual/Interactor
@onready var hover_audio: AudioStreamPlayer3D = $HoverAudio

var _facing_yaw := 0.0
var _turn_rate := 0.0
var _coyote := 0.0
var _hop_buffer := 0.0
var _scan_timer := 0.0
var _safe_timer := 0.0
var _bonk_cooldown := 0.0
var _idle_time := 0.0
var _prev_velocity := Vector3.ZERO
var _boosting := false
var _was_moving := false
var _was_on_floor := true
var _action_lock := 0.0


func _ready() -> void:
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_stop_on_slope = true
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 7)
	last_safe_position = global_position
	_facing_yaw = visual.rotation.y
	interactor.target_changed.connect(_on_target_changed)
	hover_audio.stream = Audio.get_loop(&"hover_loop")
	if hover_audio.stream:
		hover_audio.play()
	var fx := PlayerFx.new()
	fx.name = "Fx"
	add_child(fx)
	visual.enable_character_lighting()
	GameState.fragment_collected.connect(_on_fragment_collected)


func _physics_process(delta: float) -> void:
	_scan_timer = maxf(_scan_timer - delta, 0.0)
	scan_ready_ratio = 1.0 - _scan_timer / scan_cooldown
	_bonk_cooldown = maxf(_bonk_cooldown - delta, 0.0)
	_action_lock = maxf(_action_lock - delta, 0.0)

	var input_vec := Vector2.ZERO
	var wants_boost := false
	if input_enabled and not visual.is_sleeping():
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wants_boost = Input.is_action_pressed("boost")
		if Input.is_action_just_pressed("hop"):
			_hop_buffer = hop_buffer_time
	_hop_buffer = maxf(_hop_buffer - delta, 0.0)

	var move_dir := _camera_relative(input_vec)
	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)

	# Horizontal movement with acceleration / deceleration.
	_boosting = wants_boost and input_vec.length() > 0.3
	var max_speed := boost_speed if _boosting else walk_speed
	if _action_lock > 0.0:
		max_speed *= 0.35
	var target_vel := move_dir * max_speed * minf(input_vec.length(), 1.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target_vel.length() > horizontal.length() * 0.5 else deceleration
	if not on_floor:
		rate *= air_control
	horizontal = horizontal.move_toward(target_vel, rate * delta)

	# Gravity and hop.
	var vertical := velocity.y
	if _hop_buffer > 0.0 and _coyote > 0.0:
		vertical = hop_velocity
		_hop_buffer = 0.0
		_coyote = 0.0
		visual.play_action(&"Hover_Jump")
		Audio.play_sfx_3d(&"hop", global_position, -4.0)
		# Anticipation then release: a one-frame crouch springing into a stretch.
		visual.set_squash(-0.1)
		visual.add_squash(0.9)
		visual.kick_antennas(Vector2(-2.5, 0.0))
		hopped.emit()
	elif not on_floor:
		var g := (rise_gravity if vertical > 0.0 else fall_gravity) * gravity_scale
		if vertical > 0.0 and not Input.is_action_pressed("hop"):
			g *= 1.6
		vertical = maxf(vertical - g * delta, -max_fall_speed * clampf(gravity_scale * 1.5, 0.35, 1.0))
	else:
		vertical = minf(vertical, 0.0)

	velocity = Vector3(horizontal.x, vertical, horizontal.z)
	var pre_speed := horizontal.length()
	move_and_slide()

	if on_floor and not _was_on_floor and _prev_velocity.y < -4.0:
		Audio.play_sfx_3d(&"land", global_position, -6.0)
		var strength := clampf((-_prev_velocity.y - 4.0) / 8.0, 0.0, 1.0)
		if camera_rig:
			camera_rig.add_shake(0.15)
			camera_rig.add_dip(0.25 + strength * 0.5)
		visual.add_squash(-(0.55 + strength * 1.3))
		visual.kick_antennas(Vector2(3.0 + strength * 4.0, 0.0))
		if strength > 0.45:
			visual.express(&"squint", 0.3)
		landed.emit(strength)
	_was_on_floor = is_on_floor()

	_check_bonk(pre_speed)
	_update_facing(delta, move_dir, input_vec.length())
	_update_visual(delta)
	_update_safe_position(delta)
	_check_out_of_bounds()

	if input_enabled and not visual.is_sleeping():
		if Input.is_action_just_pressed("interact"):
			_try_interact()
		if Input.is_action_just_pressed("scan"):
			try_scan()
	_prev_velocity = velocity
	_update_hover_audio()


func _camera_relative(input_vec: Vector2) -> Vector3:
	if input_vec == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := camera_rig.yaw if camera_rig else 0.0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := right * input_vec.x - forward * input_vec.y
	return dir.normalized() if dir.length() > 1.0 else dir


func _update_facing(delta: float, move_dir: Vector3, input_strength: float) -> void:
	var previous := _facing_yaw
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if move_dir.length() > 0.05 and input_strength > 0.1:
		var desired := atan2(-move_dir.x, -move_dir.z)
		_facing_yaw = lerp_angle(_facing_yaw, desired, 1.0 - exp(-delta * turn_speed))
	elif horizontal.length() > 1.0:
		var desired_v := atan2(-horizontal.x, -horizontal.z)
		_facing_yaw = lerp_angle(_facing_yaw, desired_v, 1.0 - exp(-delta * turn_speed * 0.5))
	visual.rotation.y = _facing_yaw
	var raw_rate := wrapf(_facing_yaw - previous, -PI, PI) / maxf(delta, 0.0001)
	_turn_rate = lerpf(_turn_rate, raw_rate, 1.0 - exp(-delta * 10.0))


func _update_visual(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var speed01 := clampf(speed / walk_speed, 0.0, 1.0)
	var turn := clampf(-_turn_rate / 4.0, -1.0, 1.0) * speed01
	var anim_speed := lerpf(1.0, 1.55, clampf((speed - walk_speed) / (boost_speed - walk_speed), 0.0, 1.0))
	visual.set_locomotion(speed01, turn, anim_speed)
	visual.set_air_velocity(velocity.y, is_on_floor())
	visual.set_boosting(_boosting and speed > 3.0)
	# Starting off: a small crouch-and-lean; stopping hard: antennas swing forward.
	var moving := speed > 0.6
	if moving and not _was_moving and is_on_floor():
		visual.add_squash(-0.3)
		visual.kick_antennas(Vector2(-1.8, 0.0))
	elif not moving and _was_moving and _prev_velocity.length() > 4.0:
		visual.kick_antennas(Vector2(2.2, 0.0))
		visual.add_squash(-0.2)
	_was_moving = moving

	var accel_world := (velocity - _prev_velocity) / maxf(delta, 0.0001)
	var local_accel := visual.global_basis.inverse() * accel_world
	visual.set_acceleration(local_accel)
	var pitch := clampf(local_accel.z * 0.012, -0.22, 0.22) - speed01 * 0.06
	var roll := clampf(_turn_rate * speed01 * 0.035, -0.18, 0.18)
	visual.set_tilt(pitch, roll, delta)

	# Gaze toward whatever is interactable nearby.
	if is_instance_valid(interactor.current):
		visual.look_at_point(interactor.current.get_focus_point())
	else:
		visual.look_at_point(null)

	# Idle fidgets keep the robot feeling alive when the player stops to look around.
	if speed < 0.1 and is_on_floor() and not visual.is_action_playing() and not visual.is_sleeping():
		_idle_time += delta
		if _idle_time > 11.0:
			_idle_time = randf_range(-6.0, 0.0)
			visual.play_action(&"Dodge_Left" if randf() < 0.5 else &"Dodge_Right")
	else:
		_idle_time = 0.0


func _check_bonk(pre_speed: float) -> void:
	if _bonk_cooldown > 0.0 or pre_speed < boost_speed * 0.8:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) < 0.4 and Vector3(_prev_velocity.x, 0, _prev_velocity.z).normalized().dot(-n) > 0.75:
			_bonk_cooldown = 1.2
			velocity += n * 3.0
			visual.play_action(&"Take_Damage")
			Audio.play_sfx_3d(&"bonk", global_position, -3.0)
			if camera_rig:
				camera_rig.add_shake(0.45)
			visual.express(&"hurt", 0.7)
			visual.jolt(1.0)
			visual.add_squash(-0.6)
			visual.kick_antennas(Vector2(-5.0, randf_range(-2.0, 2.0)))
			bonked.emit(col.get_position())
			return


func _update_safe_position(delta: float) -> void:
	_safe_timer -= delta
	if _safe_timer > 0.0 or not is_on_floor():
		return
	_safe_timer = 0.4
	# Moving platforms are not safe spots (they will have moved on by the time we respawn).
	if get_floor_normal().y > 0.8 and get_platform_velocity().length() < 0.05:
		last_safe_position = global_position


func _check_out_of_bounds() -> void:
	if not WorldTerrain.is_ready():
		if global_position.y < fall_limit:
			if fall_respawn.is_valid():
				fall_respawn.call()
			else:
				respawn_at(last_safe_position)
		return
	var ground: float = WorldTerrain.height_at_world(global_position.x, global_position.z)
	if global_position.y < ground - 6.0 or global_position.y < -80.0:
		respawn_at(last_safe_position)


func respawn_at(pos: Vector3, yaw: float = NAN) -> void:
	global_position = pos + Vector3.UP * 0.3
	velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	if not is_nan(yaw):
		_facing_yaw = yaw
		visual.rotation.y = yaw
	reset_physics_interpolation()
	if camera_rig:
		camera_rig.snap_to_target()
	respawned.emit()


func facing_yaw() -> float:
	return _facing_yaw


func face_toward(point: Vector3) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.05:
		_facing_yaw = atan2(-to.x, -to.z)
		visual.rotation.y = _facing_yaw


func _try_interact() -> void:
	var target := interactor.current
	if target == null:
		return
	if target.locked:
		Audio.play_sfx(&"denied", -6.0)
		visual.express(&"squint", 0.45)
		visual.play_action(&"Dodge_Left", 1.4)
		return
	face_toward(target.get_focus_point())
	if target.robot_action != &"":
		visual.play_action(target.robot_action)
		_action_lock = 0.45
	Audio.play_sfx(&"interact", -4.0)
	visual.express(&"wide", 0.35)
	target.interact(self)
	interacted_with.emit(target)


func try_scan() -> bool:
	if _scan_timer > 0.0:
		return false
	_scan_timer = scan_cooldown
	visual.play_action(&"Boost")
	Audio.play_sfx(&"scan", -3.0)
	visual.express(&"wide", 0.6)
	visual.flash_eyes(0.7)
	var origin := global_position + Vector3.UP * 0.35
	ScanPulse.emit_pulse(get_tree(), origin, scan_radius, scan_speed)
	scanned.emit(origin)
	return true


func _on_target_changed(_target: Interactable) -> void:
	pass


func _update_hover_audio() -> void:
	if hover_audio == null or hover_audio.stream == null:
		return
	var speed := Vector3(velocity.x, 0, velocity.z).length()
	var awake := 0.0 if visual.is_sleeping() else 1.0
	hover_audio.pitch_scale = lerpf(0.9, 1.35, clampf(speed / boost_speed, 0.0, 1.0))
	hover_audio.volume_db = lerpf(-60.0, lerpf(-22.0, -14.0, clampf(speed / boost_speed, 0.0, 1.0)), awake)


## Snapshot used by the save system (position is only a convenience; checkpoints are canonical).
func snapshot() -> Dictionary:
	return {"x": global_position.x, "y": global_position.y, "z": global_position.z, "yaw": _facing_yaw}


func is_boosting() -> bool:
	return _boosting


func _on_fragment_collected(_id: StringName, _total: int) -> void:
	visual.express(&"happy", 0.85)
	visual.flash_eyes(1.0)
	visual.add_squash(0.6)
	visual.kick_antennas(Vector2(-2.0, 0.0))
