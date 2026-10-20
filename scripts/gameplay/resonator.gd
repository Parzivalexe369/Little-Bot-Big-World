class_name Resonator
extends Device
## A crystal resonator in the garden. Woken by a puzzle (beam or melody) or, if hidden,
## by being found with the scanner and touched. Awake resonators sing a beam of light
## toward the Crystal Heart.

enum Mode { EXTERNAL, HIDDEN, DIRECT }

@export var mode := Mode.EXTERNAL
@export var set_flag_name: StringName = &"resonators"
@export var heart_position := Vector3.ZERO
@export var beam_color := Color(0.85, 0.6, 1.0)

var _prop: Node3D
var _crystal: Node3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _on := false
var _revealed := true
var _time := 0.0


func _build() -> void:
	_prop = PropLibrary.place(self, "resonator", Vector3.ZERO, 0.0, 1.0, false)
	PropLibrary.add_collision(_prop, "resonator", true)
	_crystal = _prop.get_node_or_null("resonator_crystal") as Node3D
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 2.2, 0)
	_light.light_color = beam_color
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	add_child(_light)
	interactable = make_interactable("Wake the resonator", 2.0, Vector3(0, 1.4, 0))
	interactable.interacted.connect(func(_p: Node) -> void: activate(true))
	if mode == Mode.EXTERNAL:
		interactable.locked = true
		interactable.locked_prompt = "It hums, waiting for something."
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = 1.0
	cyl.radial_segments = 8
	_beam.mesh = cyl
	_beam.material_override = BeamSegments.beam_material(beam_color)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)
	add_to_group(&"scannable")


func _restore_state() -> void:
	_on = GameState.set_has(set_flag_name, device_id)
	_revealed = mode != Mode.HIDDEN or _on or GameState.is_revealed(device_id)
	_prop.visible = _revealed
	_prop.position.y = 0.0 if _revealed else -3.5
	_prop.process_mode = Node.PROCESS_MODE_INHERIT if _revealed else Node.PROCESS_MODE_DISABLED
	interactable.enabled = _revealed and not _on
	_apply(false)


func is_hidden_unrevealed() -> bool:
	return not _revealed


func on_scanned(_origin: Vector3) -> void:
	if not _revealed:
		_revealed = true
		GameState.mark_revealed(device_id)
		_prop.visible = true
		_prop.process_mode = Node.PROCESS_MODE_INHERIT
		var tween := create_tween()
		tween.tween_property(_prop, "position:y", 0.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func() -> void: interactable.enabled = not _on)
		add_child(FxFactory.burst(Color(0.8, 0.7, 1.0), 40, 3.0, 0.2))
		Audio.play_sfx_3d(&"reveal", global_position, 2.0)
		Events.toast("A resonator rises from the crystals.", "info")
	ScanHighlight.flash_node(_prop, Color(0.85, 0.65, 1.0))


func activate(animate: bool = true) -> void:
	if _on or not _revealed:
		return
	_on = true
	interactable.enabled = false
	var count := GameState.add_to_set(set_flag_name, device_id)
	_apply(animate)
	if animate:
		Audio.play_sfx_3d(&"resonator", global_position + Vector3.UP * 2.0, 0.0)
		Events.toast("Resonator singing  (%d/%d)" % [count, GameData.RESONATOR_COUNT], "energy")
		SaveSystem.request_save(0.5)


func _apply(animate: bool) -> void:
	var level := 1.0 if _on else 0.08
	if _on:
		start_hum(&"machine_hum", -18.0)
	if not animate or not _on:
		PropLibrary.set_power(_prop, level)
		_light.light_energy = 1.5 if _on else 0.0
		_show_beam(1.0 if _on else 0.0)
		return
	tween_power(_prop, 0.08, 1.0, 1.4)
	var tween := create_tween()
	tween.tween_property(_light, "light_energy", 1.5, 1.2)
	tween.tween_method(_show_beam, 0.0, 1.0, 1.4)
	var fx := FxFactory.fountain(beam_color, 50, 5.0, 0.9)
	fx.one_shot = true
	fx.emitting = true
	fx.position = Vector3(0, 0.5, 0)
	add_child(fx)


func _show_beam(t: float) -> void:
	if heart_position == Vector3.ZERO or t <= 0.001:
		_beam.visible = false
		return
	var from := global_position + Vector3(0, 2.6, 0)
	var to := from.lerp(heart_position, t)
	_beam.visible = true
	BeamSegments.place_segment(_beam, from, to)


func _process(delta: float) -> void:
	if _crystal == null:
		return
	_time += delta
	var speed := 1.0 if _on else 0.15
	_crystal.rotation.y += delta * speed
	_crystal.position.y = 2.1 + (sin(_time * 1.4) * 0.08 + 0.25 if _on else 0.0)
