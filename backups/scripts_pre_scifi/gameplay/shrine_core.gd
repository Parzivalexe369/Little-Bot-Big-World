class_name ShrineCore
extends Device
## The dormant heart of the shrine. Four lamps around its base show how many power nodes
## are awake; with all four, the robot can awaken it. The restoration itself (camera,
## music, world changes) is run by the WorldDirector via Events.restoration_requested.

@export var node_set: StringName = &"shrine_nodes"
@export var required_nodes := GameData.SHRINE_NODE_COUNT

var _prop: Node3D
var _rings: Array[Node3D] = []
var _orb: Node3D
var _lamps: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _spin_speed := 0.0
var _awake := false
var _time := 0.0


func _build() -> void:
	_prop = PropLibrary.place(self, "shrine_core", Vector3.ZERO, 0.0, 1.0, false)
	PropLibrary.add_collision(_prop, "shrine_core", true)
	for ring_name in ["core_ring_outer", "core_ring_mid", "core_ring_inner"]:
		var ring := _prop.get_node_or_null(ring_name) as Node3D
		if ring:
			_rings.append(ring)
	_orb = _prop.get_node_or_null("core_orb") as Node3D
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.22
	lamp_mesh.height = 0.44
	for i in required_nodes:
		var lamp := MeshInstance3D.new()
		lamp.mesh = lamp_mesh
		lamp.material_override = PropLibrary.material("energy")
		var a := TAU * i / required_nodes + PI * 0.25
		lamp.position = Vector3(cos(a) * 3.15, 1.45, sin(a) * 3.15)
		add_child(lamp)
		_lamps.append(lamp)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 3.6, 0)
	_light.light_color = Color(0.5, 0.92, 1.0)
	_light.omni_range = 16.0
	_light.light_energy = 0.0
	_light.shadow_enabled = true
	add_child(_light)
	interactable = make_interactable("Awaken the core", 3.6, Vector3(0, 1.6, 0))
	interactable.interacted.connect(_on_used)
	GameState.flag_changed.connect(func(_f: StringName, _v: Variant) -> void: _refresh())


func _restore_state() -> void:
	_awake = GameState.has_flag(&"shrine_restored")
	if _awake:
		set_awake_visuals(1.0)
		_spin_speed = 1.0
	else:
		PropLibrary.set_power(_prop, 0.0)
	_refresh()


func _refresh() -> void:
	var count := GameState.set_count(node_set)
	for i in _lamps.size():
		_lamps[i].set_instance_shader_parameter(&"power", 1.0 if i < count or _awake else 0.0)
	if _awake:
		interactable.enabled = false
		return
	interactable.locked = count < required_nodes
	interactable.locked_prompt = "The core sleeps  (%d/%d nodes awake)" % [count, required_nodes]


func _on_used(_player: Node) -> void:
	if _awake or GameState.set_count(node_set) < required_nodes:
		return
	_awake = true
	interactable.enabled = false
	GameState.set_flag(&"shrine_core_awake", true)
	Events.restoration_requested.emit(&"shrine", self)


## Called by the director during the awakening sequence (t: 0..1).
func set_awake_visuals(t: float) -> void:
	PropLibrary.set_power(_prop, t)
	_light.light_energy = 2.2 * t
	_spin_speed = t
	if t > 0.5:
		start_hum(&"machine_hum", -10.0)
	if _orb:
		_orb.position.y = 3.6 + t * 1.2


func focus_point() -> Vector3:
	return global_position + Vector3(0, 4.0, 0)


func _process(delta: float) -> void:
	if _spin_speed <= 0.0:
		return
	_time += delta
	for i in _rings.size():
		var ring := _rings[i]
		var speed := (0.4 + i * 0.35) * _spin_speed
		match i:
			0: ring.rotation = Vector3(sin(_time * 0.3) * 0.5, ring.rotation.y + speed * delta, 0.0)
			1: ring.rotation = Vector3(0.0, -_time * speed, cos(_time * 0.4) * 0.7)
			_: ring.rotation = Vector3(_time * speed, 0.0, _time * speed * 0.6)
	if _orb:
		_orb.rotation.y += delta * 0.6 * _spin_speed
