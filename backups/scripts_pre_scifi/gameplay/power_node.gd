class_name PowerNode
extends Device
## One of the shrine's four power nodes. Depending on its mode it is woken by collected
## energy, by direct touch, or by a puzzle (a light beam or the conduit tiles).
## When awake its crystal rises and a ribbon of light reaches toward the shrine core.

enum Mode { ENERGY, DIRECT, EXTERNAL }

@export var mode := Mode.DIRECT
@export var set_flag_name: StringName = &"shrine_nodes"
@export var required_energy := GameData.SHRINE_NODE_ENERGY
@export var core_position := Vector3.ZERO
@export var external_hint := "Dormant. Something must power it."

var _prop: Node3D
var _crystal: Node3D
var _light: OmniLight3D
var _beam: MeshInstance3D
var _on := false
var _spin := 0.0


func _build() -> void:
	_prop = PropLibrary.place(self, "power_node", Vector3.ZERO, 0.0, 1.0, false)
	PropLibrary.add_collision(_prop, "power_node", true)
	_crystal = _prop.get_node_or_null("node_crystal") as Node3D
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 2.4, 0)
	_light.light_color = Color(0.45, 0.9, 1.0)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	add_child(_light)
	if mode != Mode.EXTERNAL:
		interactable = make_interactable("Wake the node", 1.8, Vector3(0, 1.6, 0))
		interactable.interacted.connect(func(_p: Node) -> void: activate(true))
		GameState.fragment_collected.connect(func(_id: StringName, _t: int) -> void: _refresh_prompt())
	else:
		interactable = make_interactable("Inspect", 1.8, Vector3(0, 1.6, 0))
		interactable.locked = true
		interactable.locked_prompt = external_hint
	_build_beam()
	add_to_group(&"scannable")


func _build_beam() -> void:
	if core_position == Vector3.ZERO:
		return
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 1.0
	cyl.radial_segments = 8
	_beam.mesh = cyl
	_beam.material_override = BeamSegments.beam_material(Color(0.45, 0.95, 1.0))
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	add_child(_beam)
	_beam.visible = false


func _restore_state() -> void:
	_on = GameState.set_has(set_flag_name, device_id)
	_apply(false)
	_refresh_prompt()


func is_on() -> bool:
	return _on


func _refresh_prompt() -> void:
	if _on:
		interactable.enabled = false
		return
	if mode == Mode.ENERGY:
		interactable.locked = GameState.energy() < required_energy
		interactable.locked_prompt = energy_text(required_energy)


func activate(animate: bool = true) -> void:
	if _on:
		return
	if mode == Mode.ENERGY and GameState.energy() < required_energy:
		return
	_on = true
	interactable.enabled = false
	var count := GameState.add_to_set(set_flag_name, device_id)
	_apply(animate)
	if animate:
		Audio.play_sfx_3d(&"power_up", global_position + Vector3.UP * 2.0, 0.0)
		Events.toast("Power node awake  (%d/%d)" % [count, GameData.SHRINE_NODE_COUNT], "energy")
		SaveSystem.request_save(0.5)


func on_scanned(_origin: Vector3) -> void:
	ScanHighlight.flash_node(_prop)


func _apply(animate: bool) -> void:
	if not _on:
		PropLibrary.set_power(_prop, 0.0)
		if _crystal:
			_crystal.set_instance_shader_parameter(&"power", 0.05)
			for g in _crystal.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).set_instance_shader_parameter(&"power", 0.05)
			_crystal.position.y = 1.85
		return
	if not animate:
		PropLibrary.set_power(_prop, 1.0)
		if _crystal:
			_crystal.position.y = 2.35
		_light.light_energy = 1.4
		_show_beam(1.0)
		return
	tween_power(_prop, 0.05, 1.0, 1.2)
	var tween := create_tween().set_parallel(true)
	if _crystal:
		tween.tween_property(_crystal, "position:y", 2.35, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_light, "light_energy", 1.4, 1.2)
	tween.chain().tween_method(_show_beam, 0.0, 1.0, 1.0)
	var fx := FxFactory.fountain(Color(0.45, 0.95, 1.0), 40, 4.0, 0.7)
	fx.one_shot = true
	fx.emitting = true
	fx.position = Vector3(0, 1.5, 0)
	add_child(fx)


func _show_beam(t: float) -> void:
	if _beam == null:
		return
	var from := global_position + Vector3(0, 2.35, 0)
	var to := from.lerp(core_position, t)
	_beam.visible = t > 0.01
	BeamSegments.place_segment(_beam, from, to)


func _process(delta: float) -> void:
	if _on and _crystal:
		_spin += delta
		_crystal.rotation.y = _spin * 0.8
		_crystal.position.y = 2.35 + sin(_spin * 1.6) * 0.06
