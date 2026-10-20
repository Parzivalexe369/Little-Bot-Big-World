class_name CrystalHeart
extends Device
## The great crystal at the end of the garden. Needs all three resonators singing and enough
## gathered energy. Restoring it wakes the whole world (run by the WorldDirector).

@export var resonator_set: StringName = &"resonators"
@export var required_resonators := GameData.RESONATOR_COUNT
@export var required_energy := GameData.HEART_ENERGY

var _prop: Node3D
var _gem: Node3D
var _light: OmniLight3D
var _awake := false
var _time := 0.0
var _glow := 0.15


func _build() -> void:
	_prop = PropLibrary.place(self, "crystal_heart", Vector3.ZERO, 0.0, 1.0, false)
	PropLibrary.add_collision(_prop, "crystal_heart", true)
	_gem = _prop.get_node_or_null("heart_gem") as Node3D
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 4.6, 0)
	_light.light_color = Color(1.0, 0.7, 0.95)
	_light.omni_range = 22.0
	_light.light_energy = 0.3
	_light.shadow_enabled = true
	add_child(_light)
	interactable = make_interactable("Restore the Crystal Heart", 5.4, Vector3(0, 2.0, 0))
	interactable.interacted.connect(_on_used)
	GameState.flag_changed.connect(func(_f: StringName, _v: Variant) -> void: _refresh())
	GameState.fragment_collected.connect(func(_id: StringName, _t: int) -> void: _refresh())


func _restore_state() -> void:
	_awake = GameState.has_flag(&"garden_restored")
	set_glow(1.0 if _awake else 0.15)
	_refresh()


func _refresh() -> void:
	if _awake:
		interactable.enabled = false
		return
	var res := GameState.set_count(resonator_set)
	var energy := GameState.energy()
	interactable.locked = res < required_resonators or energy < required_energy
	if res < required_resonators:
		interactable.locked_prompt = "Silent  (%d/%d resonators singing)" % [res, required_resonators]
	else:
		interactable.locked_prompt = energy_text(required_energy)
	if not _awake:
		set_glow(0.15 + 0.25 * float(res) / required_resonators)


func _on_used(_player: Node) -> void:
	if _awake or interactable.locked:
		return
	_awake = true
	interactable.enabled = false
	GameState.set_flag(&"heart_awake", true)
	Events.restoration_requested.emit(&"garden", self)


func set_glow(level: float) -> void:
	_glow = level
	PropLibrary.set_power(_prop, clampf(level, 0.0, 1.0))
	_light.light_energy = 0.2 + level * 3.0


func focus_point() -> Vector3:
	return global_position + Vector3(0, 4.4, 0)


func _process(delta: float) -> void:
	if _gem == null:
		return
	_time += delta
	_gem.rotation.y += delta * (0.15 + _glow * 0.5)
	_gem.position.y = 4.4 + sin(_time * 1.1) * 0.12 * _glow
