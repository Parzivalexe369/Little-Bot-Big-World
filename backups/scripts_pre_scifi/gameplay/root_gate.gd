class_name RootGate
extends Device
## The old meadow gate. A pylon beside it needs enough collected energy; powering it sends
## light down a cable, raises the lattice shutter and wakes the meadow.

@export var required_energy := GameData.GATE_ENERGY
@export var pylon_offset := Vector3(5.4, 0, -3.6)
@export var side_wall_length := 16.0
@export var open_flag: StringName = &"meadow_gate_open"
@export var restore_area: StringName = &"meadow"

var _gate: Node3D
var _shutter: Node3D
var _pylon: Node3D
var _blocker: CollisionShape3D
var _cable: CableLine
var _open := false


func _build() -> void:
	_gate = PropLibrary.instance("root_gate")
	add_child(_gate)
	PropLibrary.add_collision(_gate, "root_gate", true)
	_shutter = _gate.get_node_or_null("root_gate_shutter") as Node3D
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	_blocker = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.8, 6.0, 0.6)
	_blocker.shape = box
	_blocker.position = Vector3(0, 3.0, 0)
	body.add_child(_blocker)

	_build_side_walls(body)
	var pylon_root := Node3D.new()
	pylon_root.name = "Pylon"
	add_child(pylon_root)
	pylon_root.position = pylon_offset
	WorldTerrain.snap_node(pylon_root)
	_pylon = PropLibrary.place(pylon_root, "power_pylon", Vector3.ZERO, 0.0, 1.0, true)
	interactable = make_interactable("Power the gate", 1.7, Vector3(0, 1.2, 0), pylon_root)
	interactable.interacted.connect(_on_pylon_used)

	_cable = CableLine.new()
	var a := pylon_root.global_position
	var g := global_position
	var right := global_basis.x
	_cable.points = PackedVector2Array([
		Vector2(a.x, a.z),
		Vector2(a.x, a.z).lerp(Vector2(g.x, g.z) + Vector2(right.x, right.z) * 4.2, 0.5) + Vector2(0.8, 0.6),
		Vector2(g.x, g.z) + Vector2(right.x, right.z) * 4.2,
	])
	add_child(_cable)
	GameState.fragment_collected.connect(func(_id: StringName, _t: int) -> void: _refresh_prompt())
	_refresh_prompt()


func _build_side_walls(body: StaticBody3D) -> void:
	# The gate sits in a pass; walls + boulders stop the robot walking around it.
	for side in [-1.0, 1.0]:
		var wall := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(side_wall_length, 9.0, 3.0)
		wall.shape = box
		wall.position = Vector3(side * (5.4 + side_wall_length * 0.5), 4.0, 0.0)
		body.add_child(wall)
		for k in 3:
			var x: float = side * (6.4 + k * 3.0)
			var rock := PropLibrary.place(self, "rock_moss_b" if k % 2 == 0 else "rock_c", Vector3(x, -0.6, randf_range(-0.8, 0.8)), randf() * 360.0, 0.9 + k * 0.15, false)
			rock.name = "Boulder"


func _restore_state() -> void:
	_open = GameState.has_flag(open_flag)
	if _open:
		_apply_open(false)
	else:
		PropLibrary.set_power(_gate, 0.0)
		PropLibrary.set_power(_pylon, 0.0)


func _refresh_prompt() -> void:
	if _open:
		interactable.enabled = false
		return
	interactable.locked = GameState.energy() < required_energy
	interactable.locked_prompt = energy_text(required_energy)
	interactable.prompt = "Power the gate"


func _on_pylon_used(_player: Node) -> void:
	if _open or GameState.energy() < required_energy:
		return
	_open = true
	interactable.enabled = false
	GameState.set_flag(open_flag, true)
	Audio.play_sfx_3d(&"power_up", _pylon.global_position, 0.0)
	tween_power(_pylon, 0.0, 1.0, 0.8)
	_cable.set_power(1.0, true, 1.4)
	Events.look_at_requested.emit(global_position + Vector3(0, 3.0, 0), 4.2)
	await get_tree().create_timer(1.4).timeout
	_apply_open(true)
	Events.restoration_requested.emit(restore_area, self)


func _apply_open(animate: bool) -> void:
	_blocker.set_deferred("disabled", true)
	_cable.set_power(1.0, false)
	if not animate:
		PropLibrary.set_power(_gate, 1.0)
		PropLibrary.set_power(_pylon, 1.0)
		if _shutter:
			_shutter.position.y = 5.4
		return
	tween_power(_gate, 0.0, 1.0, 1.0)
	Audio.play_sfx_3d(&"gate_open", global_position + Vector3.UP * 2.0, 0.0)
	if _shutter:
		var tween := create_tween()
		tween.tween_property(_shutter, "position:y", 5.4, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var dust := FxFactory.burst(Color(0.85, 0.78, 0.6), 40, 2.5, 0.35)
	dust.position = Vector3(0, 0.3, 0)
	add_child(dust)
