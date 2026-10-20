class_name RobotVisual
extends Node3D
## The player's robot model: the original rigged + animated asset with an AnimationTree
## on top of its baked actions, an eye-glow channel (driven by the Blender "eye_glow"
## curves), and light procedural personality.

signal action_finished(action: StringName)
signal boot_finished

const MODEL_SCENE := preload("res://assets/characters/pink_robot/pink_robot.glb")
const EYE_GLOW_FILE := "res://assets/characters/pink_robot/eye_glow.json"
const EYE_GLOW_TRACK := NodePath("..:eye_glow")

## Animations used as one-shot actions. Speeds tune long authored clips to gameplay pacing.
enum BootMode { AWAKE, ASLEEP, BOOTING, SHUTTING_DOWN }

const ACTIONS := {
	&"Attack": 1.35,       # used as the "poke / activate" gesture
	&"Boost": 1.6,         # eyes brighten: used for scanning
	&"Hover_Jump": 1.75,
	&"Victory": 1.0,
	&"Take_Damage": 1.3,   # bump into something while boosting
	&"Dodge_Left": 0.7,    # idle fidgets
	&"Dodge_Right": 0.7,
}

@export var cast_shadows := true
## Animated by the eye_glow tracks (1.0 = normal brightness).
var eye_glow := 1.0
## Overall power (0 = off). Multiplies eye glow; used for sleep/boot.
var power := 1.0
var bob_enabled := true

var model: Node3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var skeleton: Skeleton3D
var face: RobotFaceModifier

var _eye_materials: Array[StandardMaterial3D] = []
var _glow: Dictionary = {}
var _candy_meshes: Array[MeshInstance3D] = []
# Squash and stretch: a volume-preserving spring on the model's vertical scale (model only,
# physics and collision never change). >0 stretches tall, <0 squashes.
var _squash := 0.0
var _squash_vel := 0.0
var _air_stretch := 0.0
var _boost := 0.0
var _boost_target := 0.0
var _eye_flash := 0.0
var _jolt := 0.0
var _rim_light: OmniLight3D
var _eye_light: OmniLight3D
var _loco_target := Vector2.ZERO
var _loco := Vector2.ZERO
var _loco_speed := 1.0
var _current_action: StringName = &""
var _time := 0.0
var _tilt := Vector3.ZERO
var _boot_mode := BootMode.AWAKE


func _ready() -> void:
	model = MODEL_SCENE.instantiate() as Node3D
	model.name = "Model"
	# The asset faces +Z; Godot's forward is -Z.
	model.rotation.y = PI
	add_child(model)
	anim_player = model.get_node("AnimationPlayer") as AnimationPlayer
	skeleton = model.get_node("RIG_PinkRobot/Skeleton3D") as Skeleton3D
	_eye_materials = RobotMaterials.apply(model, _glow)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			if src and src.resource_name == "M_CandyPink":
				_candy_meshes.append(mi)
				break
	if not cast_shadows:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif OS.has_feature("web"):
		# Browsers: bolts and trims inside the body's outline cast no shadow (the same shadow
		# shape, ~90 fewer draw calls in every shadow cascade).
		WebDrawDistance.no_tiny_shadows(model, 0.2)
	_install_eye_glow_tracks()
	_build_animation_tree()
	face = RobotFaceModifier.new()
	face.name = "Face"
	skeleton.add_child(face)
	anim_player.animation_finished.connect(_on_player_animation_finished)


func _process(delta: float) -> void:
	_time += delta
	_loco = _loco.lerp(_loco_target, 1.0 - exp(-delta * 8.0))
	if anim_tree.active:
		anim_tree.set("parameters/loco/blend_position", _loco)
		anim_tree.set("parameters/loco_speed/scale", _loco_speed)
		if _current_action != &"" and not bool(anim_tree.get("parameters/action/active")):
			var finished := _current_action
			_current_action = &""
			action_finished.emit(finished)
	_boost = lerpf(_boost, _boost_target, 1.0 - exp(-delta * 6.0))
	_eye_flash = maxf(_eye_flash - delta * 2.5, 0.0)
	var glow := eye_glow * power * (1.0 + _boost * 0.25 + _eye_flash * 0.8)
	# A bump makes the display stutter like a brief power glitch.
	if _jolt > 0.0:
		glow *= 1.0 - _jolt * 0.65 * (1.0 if fposmod(_time * 14.0, 1.0) > 0.5 else 0.0)
	for m in _eye_materials:
		m.emission_energy_multiplier = 4.6 * glow
		m.albedo_color = Color(0.12, 0.62, 0.14) * clampf(0.2 + glow, 0.2, 1.0)
	if _glow.has("vent"):
		(_glow["vent"] as StandardMaterial3D).emission_energy_multiplier = (0.25 + _boost * 2.6) * power
	if _glow.has("lime"):
		(_glow["lime"] as StandardMaterial3D).emission_energy_multiplier = RobotMaterials.LIME_GLOW * power * (1.0 + _boost * 1.2 + _eye_flash)
	for mi in _candy_meshes:
		mi.set_instance_shader_parameter("energy_boost", _boost)
	_update_squash(delta)
	# Gentle extra hover bob + body tilt from acceleration, applied to the model only so
	# physics never jitters. The bob settles while moving fast and "breathes" at rest.
	var bob := (sin(_time * 2.1) * 0.025 + sin(_time * 3.7) * 0.008) * lerpf(1.0, 0.45, _loco.y) if bob_enabled else 0.0
	_jolt = maxf(_jolt - delta * 3.0, 0.0)
	var shake := Vector3(sin(_time * 61.0), 0.0, cos(_time * 53.0)) * _jolt * _jolt * 0.035
	model.position = Vector3(shake.x, bob * power, shake.z)
	model.rotation = Vector3(_tilt.x, PI, _tilt.z)
	if face:
		face.glances_enabled = power > 0.5
	_update_light_rig()


func _update_squash(delta: float) -> void:
	var breathe := sin(_time * 1.7) * 0.01 * (1.0 - _loco.y) * power if bob_enabled else 0.0
	var target := _air_stretch + breathe
	# Slightly underdamped spring: a quick wobble that settles, never a lingering jelly.
	var accel := (target - _squash) * 190.0 - _squash_vel * 13.0
	_squash_vel += accel * delta
	_squash += _squash_vel * delta
	_squash = clampf(_squash, -0.22, 0.18)
	var sy := 1.0 + _squash
	var sxz := 1.0 / sqrt(sy)
	model.scale = Vector3(sxz, sy, sxz)


## Squash/stretch impulse: negative squashes (landing), positive stretches (take-off).
func add_squash(amount: float) -> void:
	_squash_vel += amount * 4.0


## Instantly sets the squash (for one-frame anticipation before an impulse).
func set_squash(value: float) -> void:
	_squash = value
	_squash_vel = 0.0


## Stretch slightly along fast vertical motion while airborne.
func set_air_velocity(vertical_speed: float, grounded: bool) -> void:
	_air_stretch = 0.0 if grounded else clampf(absf(vertical_speed) * 0.009, 0.0, 0.07)


func set_boosting(on: bool) -> void:
	_boost_target = 1.0 if on else 0.0
	if face:
		face.base_expression = &"focus" if on else &""


func express(kind: StringName, duration: float = 0.6) -> void:
	if face:
		face.express(kind, duration)


func kick_antennas(impulse: Vector2) -> void:
	if face:
		face.kick_antennas(impulse)


func flash_eyes(amount: float = 1.0) -> void:
	_eye_flash = maxf(_eye_flash, amount)


## Short positional shudder (bumps).
func jolt(amount: float = 1.0) -> void:
	_jolt = maxf(_jolt, amount)


## Player-only: puts the model on its own render layer and adds a small light rig: a rim
## light that only touches the robot (keeps its silhouette readable in shade) and a soft
## green spill from the eyes onto the ground in front.
func enable_character_lighting() -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = RobotMaterials.ROBOT_LAYER
	_rim_light = OmniLight3D.new()
	_rim_light.light_cull_mask = RobotMaterials.ROBOT_LAYER
	_rim_light.light_color = Color(1.0, 0.94, 0.9)
	_rim_light.light_energy = 0.9
	_rim_light.light_specular = 0.6
	_rim_light.omni_range = 2.2
	_rim_light.omni_attenuation = 1.4
	_rim_light.shadow_enabled = false
	_rim_light.top_level = true
	add_child(_rim_light)
	_eye_light = OmniLight3D.new()
	_eye_light.light_cull_mask = 0xFFFFF & ~RobotMaterials.ROBOT_LAYER
	_eye_light.light_color = Color(0.45, 1.0, 0.45)
	_eye_light.light_energy = 0.0
	_eye_light.light_specular = 0.2
	_eye_light.omni_range = 1.1
	_eye_light.omni_attenuation = 2.0
	_eye_light.shadow_enabled = false
	_eye_light.position = Vector3(0, 0.32, -0.42)
	add_child(_eye_light)


func _update_light_rig() -> void:
	if _rim_light == null:
		return
	var center := global_position + Vector3.UP * 0.36
	var cam := get_viewport().get_camera_3d()
	var away := Vector3.BACK
	if cam:
		away = center - cam.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	_rim_light.global_position = center + away * 0.75 + Vector3.UP * 0.55
	_rim_light.light_energy = 0.9 * maxf(power, 0.15)
	_eye_light.light_energy = 0.14 * eye_glow * power * (1.0 + _boost * 0.3 + _eye_flash)


## Locomotion blend: speed01 0..1 (idle -> forward), turn -1..1 (lean left/right).
func set_locomotion(speed01: float, turn: float, anim_speed: float = 1.0) -> void:
	_loco_target = Vector2(clampf(turn, -1.0, 1.0), clampf(speed01, 0.0, 1.0))
	_loco_speed = anim_speed


## Body lean in radians: pitch forward when accelerating, roll into turns.
func set_tilt(pitch: float, roll: float, delta: float) -> void:
	var target := Vector3(clampf(pitch, -0.3, 0.3), 0.0, clampf(roll, -0.35, 0.35))
	_tilt = _tilt.lerp(target, 1.0 - exp(-delta * 7.0))


func set_acceleration(local_accel: Vector3) -> void:
	if face:
		# Visual space faces -Z, the model is turned 180 degrees.
		face.local_acceleration = Vector3(-local_accel.x, local_accel.y, -local_accel.z)


func look_at_point(world_point: Variant) -> void:
	if face == null:
		return
	if world_point is Vector3:
		face.look_target = world_point
		face.has_look_target = true
	else:
		face.has_look_target = false


func play_action(action: StringName, speed: float = -1.0) -> bool:
	if _boot_mode != BootMode.AWAKE or not ACTIONS.has(action):
		return false
	var scale: float = ACTIONS[action] if speed <= 0.0 else speed
	anim_tree.set("parameters/action_select/transition_request", String(action))
	anim_tree.set("parameters/action_speed/scale", scale)
	anim_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_current_action = action
	return true


func stop_action() -> void:
	anim_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func is_action_playing() -> bool:
	return _current_action != &""


func current_action() -> StringName:
	return _current_action


## Powered-down pose: the last frame of the authored Shutdown animation.
func sleep() -> void:
	_boot_mode = BootMode.ASLEEP
	anim_tree.active = false
	anim_player.play(&"Shutdown")
	anim_player.seek(anim_player.current_animation_length, true)
	anim_player.pause()
	power = 0.0
	face.blink_enabled = false


## Wakes up by playing Shutdown in reverse (the eye_glow curve flickers back to life).
func boot_up(speed: float = 1.0) -> void:
	_boot_mode = BootMode.BOOTING
	anim_tree.active = false
	power = 1.0
	anim_player.play_backwards(&"Shutdown")
	anim_player.speed_scale = speed


## Plays the authored Shutdown quickly, then reboots (used after a dunk in water).
func power_cycle() -> void:
	_boot_mode = BootMode.SHUTTING_DOWN
	anim_tree.active = false
	anim_player.speed_scale = 2.5
	anim_player.play(&"Shutdown")


## Skips the boot sequence (tools and tests): fully powered and awake immediately.
func wake_instantly() -> void:
	power = 1.0
	if is_sleeping():
		_finish_boot()


func is_sleeping() -> bool:
	return _boot_mode != BootMode.AWAKE


func _on_player_animation_finished(anim_name: StringName) -> void:
	if anim_name != &"Shutdown":
		return
	match _boot_mode:
		BootMode.BOOTING:
			_finish_boot()
		BootMode.SHUTTING_DOWN:
			boot_up(2.0)


func _finish_boot() -> void:
	anim_player.stop()
	anim_player.speed_scale = 1.0
	_boot_mode = BootMode.AWAKE
	face.blink_enabled = true
	anim_tree.active = true
	boot_finished.emit()


func _install_eye_glow_tracks() -> void:
	var text := FileAccess.get_file_as_string(EYE_GLOW_FILE)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("Eye glow curves missing; eyes will keep a constant glow.")
		return
	var fps := float(parsed.get("fps", 24))
	var curves: Dictionary = parsed.get("actions", {})
	for anim_name: StringName in anim_player.get_animation_list():
		var anim := anim_player.get_animation(anim_name)
		if anim.find_track(EYE_GLOW_TRACK, Animation.TYPE_VALUE) >= 0:
			continue
		var key := String(anim_name)
		var values: Array = curves.get(key, curves.get(key + "_loop", []))
		if values.is_empty():
			continue
		var track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track, EYE_GLOW_TRACK)
		anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		for i in values.size():
			var t := i / fps
			if t <= anim.length + 0.001:
				anim.track_insert_key(track, t, float(values[i]))


func _build_animation_tree() -> void:
	var blend := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-1.0, 0.0)
	loco.max_space = Vector2(1.0, 1.0)
	loco.add_blend_point(_clip(&"Idle_Hover"), Vector2(0.0, 0.0), -1, &"idle")
	loco.add_blend_point(_clip(&"Hover_Move_Forward"), Vector2(0.0, 1.0), -1, &"forward")
	loco.add_blend_point(_clip(&"Hover_Move_Left"), Vector2(-1.0, 0.75), -1, &"lean_left")
	loco.add_blend_point(_clip(&"Hover_Move_Right"), Vector2(1.0, 0.75), -1, &"lean_right")
	loco.add_blend_point(_clip(&"Hover_Move_Left"), Vector2(-1.0, 0.0), -1, &"turn_left")
	loco.add_blend_point(_clip(&"Hover_Move_Right"), Vector2(1.0, 0.0), -1, &"turn_right")
	blend.add_node(&"loco", loco, Vector2(0, 0))

	var loco_speed := AnimationNodeTimeScale.new()
	blend.add_node(&"loco_speed", loco_speed, Vector2(200, 0))
	blend.connect_node(&"loco_speed", 0, &"loco")

	var select := AnimationNodeTransition.new()
	# A short cross-fade when one action interrupts another (no pops).
	select.xfade_time = 0.12
	select.allow_transition_to_self = true
	var i := 0
	for action: StringName in ACTIONS:
		select.add_input(String(action))
		var clip := _clip(action)
		blend.add_node(StringName("clip_%s" % action), clip, Vector2(0, 150 + i * 60))
		i += 1
	blend.add_node(&"action_select", select, Vector2(200, 200))
	i = 0
	for action: StringName in ACTIONS:
		blend.connect_node(&"action_select", i, StringName("clip_%s" % action))
		i += 1

	var action_speed := AnimationNodeTimeScale.new()
	blend.add_node(&"action_speed", action_speed, Vector2(400, 200))
	blend.connect_node(&"action_speed", 0, &"action_select")

	var oneshot := AnimationNodeOneShot.new()
	oneshot.fadein_time = 0.18
	oneshot.fadeout_time = 0.35
	blend.add_node(&"action", oneshot, Vector2(600, 0))
	blend.connect_node(&"action", 0, &"loco_speed")
	blend.connect_node(&"action", 1, &"action_speed")
	blend.connect_node(&"output", 0, &"action")

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	model.add_child(anim_tree)
	anim_tree.root_node = NodePath("..")
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.tree_root = blend
	anim_tree.active = true
	anim_tree.set("parameters/loco_speed/scale", 1.0)
	anim_tree.set("parameters/action_speed/scale", 1.0)


func _clip(anim_name: StringName) -> AnimationNodeAnimation:
	var clip := AnimationNodeAnimation.new()
	clip.animation = anim_name
	return clip
