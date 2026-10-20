class_name OldRobot
extends Node3D
## One of the other robots from the source .blend, slumped and asleep. Its eye lights
## flicker when the robot visits, and it wakes properly once the whole world is restored.

@export_enum("the_ball", "the_ball_v2") var model := "the_ball"
@export var slump_degrees := 14.0
@export var wake_flag: StringName = &"garden_restored"
@export var snap_to_ground := true
@export var discovery_id: StringName = &""

var _model: Node3D
var _eye_materials: Array[StandardMaterial3D] = []
var _awake := false
var _time := 0.0
var _flicker := 0.0


func _ready() -> void:
	if snap_to_ground:
		WorldTerrain.snap_node(self)
	var path := "res://assets/characters/old_robots/%s.glb" % model
	_model = (load(path) as PackedScene).instantiate() as Node3D
	_model.rotation.y = PI
	add_child(_model)
	RobotMaterials.apply(_model)
	_collect_eyes()
	if OS.has_feature("web"):
		# Browsers: one draw call per material instead of one per part (190 parts).
		WebDrawDistance.merge_static(_model)
	_model.rotation.x = deg_to_rad(slump_degrees)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.38
	shape.shape = sphere
	shape.position = Vector3(0, 0.38, 0)
	body.add_child(shape)
	_awake = GameState.has_flag(wake_flag)
	_set_eyes(1.0 if _awake else 0.0)
	if _awake:
		_model.rotation.x = 0.0
	GameState.flag_changed.connect(_on_flag)
	if discovery_id != &"":
		var it := Interactable.new()
		it.prompt = "Say hello"
		it.radius = 1.6
		it.focus_offset = Vector3(0, 0.45, 0)
		it.robot_action = &""
		add_child(it)
		it.interacted.connect(_on_hello)


func _on_hello(player: Node) -> void:
	flicker()
	Audio.play_sfx_3d(&"robot_chirp", global_position + Vector3.UP * 0.4, -2.0)
	if GameState.add_discovery(discovery_id):
		Events.discovery_shown.emit(discovery_id)
		Audio.play_sfx(&"discovery", -3.0)
		if player is Player:
			(player as Player).visual.play_action(&"Victory")
		SaveSystem.request_save()
	else:
		Events.discovery_shown.emit(discovery_id)


func _collect_eyes() -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(s)
			if source == null:
				continue
			var n := source.resource_name
			if n in ["BALL_LED_Green", "BALL_Sensor_Lime", "TB2_EyeOrange", "TB2_OrangeLight"]:
				var m := StandardMaterial3D.new()
				var c := Color(0.5, 1.0, 0.45) if n.begins_with("BALL") else Color(1.0, 0.55, 0.2)
				m.albedo_color = c * 0.3
				m.emission_enabled = true
				m.emission = c
				mi.set_surface_override_material(s, m)
				_eye_materials.append(m)


func _set_eyes(level: float) -> void:
	for m in _eye_materials:
		m.emission_energy_multiplier = level * 3.0


## A brief flicker of life when the player says hello.
func flicker() -> void:
	_flicker = 1.6


func _on_flag(flag: StringName, value: Variant) -> void:
	if flag == wake_flag and value and not _awake:
		_awake = true
		var tween := create_tween()
		tween.tween_interval(randf_range(1.0, 3.0))
		tween.tween_method(_set_eyes, 0.0, 1.0, 1.5)
		tween.parallel().tween_property(_model, "rotation:x", 0.0, 2.0).set_trans(Tween.TRANS_BACK)


func _process(delta: float) -> void:
	_time += delta
	if _awake:
		_model.position.y = sin(_time * 2.0) * 0.03 + 0.05
		return
	if _flicker > 0.0:
		_flicker -= delta
		_set_eyes(0.6 if fmod(_time, 0.24) < 0.12 else 0.0)
		if _flicker <= 0.0:
			_set_eyes(0.0)
