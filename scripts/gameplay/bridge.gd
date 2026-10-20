class_name OldBridge
extends Device
## The bridge over the ravine and the machine that raises it. Also owns the ravine's safety:
## invisible rails along both edges, end blockers until the bridge is up, and a water volume.

@export var switch_set: StringName = &"forest_switches"
@export var required_switches := GameData.FOREST_SWITCH_COUNT
@export var machine_offset := Vector3(-4.5, 0, 2.0)
@export var corridor_min_x := -16.0
@export var corridor_max_x := 24.0

var _machine: Node3D
var _gear: Node3D
var _lever: Node3D
var _planks: Array[Node3D] = []
var _deck_body: StaticBody3D
var _end_blockers: Array[CollisionShape3D] = []
var _rails: Array[Node3D] = []
var _raised := false
var _start := Vector3.ZERO
var _end := Vector3.ZERO


func _build() -> void:
	snap_to_ground = false
	var a := WorldLayout.BRIDGE_START
	var b := WorldLayout.BRIDGE_END
	_start = Vector3(a.x, WorldTerrain.height_at_world(a.x, a.y), a.y)
	_end = Vector3(b.x, WorldTerrain.height_at_world(b.x, b.y), b.y)
	global_position = _start
	var machine_root := Node3D.new()
	machine_root.name = "Machine"
	add_child(machine_root)
	machine_root.global_position = _start + machine_offset
	WorldTerrain.snap_node(machine_root)
	_machine = PropLibrary.place(machine_root, "bridge_machine", Vector3.ZERO, 30.0, 1.0, false)
	PropLibrary.add_collision(_machine, "bridge_machine", true)
	_gear = _machine.get_node_or_null("bridge_gear") as Node3D
	_lever = _machine.get_node_or_null("bridge_lever") as Node3D
	interactable = make_interactable("Raise the bridge", 2.2, Vector3(0, 1.2, 0), machine_root)
	interactable.interacted.connect(_on_used)
	GameState.flag_changed.connect(func(_f: StringName, _v: Variant) -> void: _refresh_prompt())
	_build_deck()
	_build_safety()
	_refresh_prompt()


func machine_position() -> Vector3:
	return get_node("Machine").global_position


func _build_deck() -> void:
	var dir := _end - _start
	var flat := Vector3(dir.x, 0, dir.z)
	var length := flat.length()
	var yaw := atan2(flat.x, flat.z)
	var deck := Node3D.new()
	deck.name = "Deck"
	add_child(deck)
	deck.global_position = _start
	deck.global_rotation = Vector3(0, yaw, 0)
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(3.2, 0.18, 0.55)
	var wood := PropLibrary.material("wood")
	var count := int(length / 0.62)
	for i in count:
		var plank := MeshInstance3D.new()
		plank.mesh = plank_mesh
		plank.material_override = wood
		var t := (i + 0.5) / count
		plank.position = Vector3(randf_range(-0.06, 0.06), lerpf(0.0, _end.y - _start.y, t) - 0.1 + sin(t * PI) * 0.25, t * length)
		plank.rotation.y = randf_range(-0.04, 0.04)
		deck.add_child(plank)
		_planks.append(plank)
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rail_mesh := CylinderMesh.new()
		rail_mesh.top_radius = 0.06
		rail_mesh.bottom_radius = 0.06
		rail_mesh.height = length
		rail.mesh = rail_mesh
		rail.material_override = PropLibrary.material("bark")
		rail.position = Vector3(side * 1.55, 0.9 + (_end.y - _start.y) * 0.5, length * 0.5)
		rail.rotation.x = PI * 0.5
		deck.add_child(rail)
		_rails.append(rail)
		for p in 5:
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.09
			pm.bottom_radius = 0.11
			pm.height = 1.0
			post.mesh = pm
			post.material_override = PropLibrary.material("bark")
			var t := p / 4.0
			post.position = Vector3(side * 1.55, 0.45 + (_end.y - _start.y) * t, t * length)
			deck.add_child(post)
			_rails.append(post)
	_deck_body = StaticBody3D.new()
	_deck_body.collision_layer = 1
	deck.add_child(_deck_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.3, length + 1.0)
	shape.shape = box
	shape.position = Vector3(0, -0.12 + (_end.y - _start.y) * 0.5, length * 0.5)
	shape.rotation.x = -atan2(_end.y - _start.y, length)
	_deck_body.add_child(shape)
	var rail_body := StaticBody3D.new()
	rail_body.collision_layer = 1 << 7
	deck.add_child(rail_body)
	for side in [-1.0, 1.0]:
		var rs := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = Vector3(0.2, 2.0, length)
		rs.shape = rb
		rs.position = Vector3(side * 1.6, 1.0 + (_end.y - _start.y) * 0.5, length * 0.5)
		rail_body.add_child(rs)


func _build_safety() -> void:
	var walls := StaticBody3D.new()
	walls.name = "RavineRails"
	walls.collision_layer = 1 << 7
	walls.top_level = true
	add_child(walls)
	walls.global_transform = Transform3D.IDENTITY
	var pts := WorldLayout.RAVINE_POINTS
	var bridge_mid := (WorldLayout.BRIDGE_START + WorldLayout.BRIDGE_END) * 0.5
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var seg := p1 - p0
		var normal := Vector2(-seg.y, seg.x).normalized()
		var steps := int(seg.length() / 3.0) + 1
		for s in steps:
			var c := p0.lerp(p1, (s + 0.5) / steps)
			if c.x < corridor_min_x or c.x > corridor_max_x:
				continue
			for side in [-1.0, 1.0]:
				var q: Vector2 = c + normal * side * (WorldLayout.RAVINE_HALF_WIDTH + 0.9)
				if q.distance_to(bridge_mid + normal * side * 7.0) < 2.4:
					continue
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(seg.length() / steps + 0.4, 6.0, 0.4)
				shape.shape = box
				var y := WorldTerrain.height_at_world(q.x, q.y)
				shape.position = Vector3(q.x, y + 2.0, q.y)
				shape.rotation.y = -atan2(seg.y, seg.x)
				walls.add_child(shape)
	for end_point in [_start, _end]:
		var blocker := CollisionShape3D.new()
		var box2 := BoxShape3D.new()
		box2.size = Vector3(4.6, 6.0, 0.5)
		blocker.shape = box2
		var dir := (_end - _start).normalized()
		var inset: Vector3 = dir * (0.6 if end_point == _start else -0.6)
		blocker.position = end_point + inset + Vector3.UP * 2.5
		blocker.rotation.y = atan2(dir.x, dir.z)
		walls.add_child(blocker)
		_end_blockers.append(blocker)
	var hazard := WaterHazard.new()
	hazard.size = Vector3(corridor_max_x - corridor_min_x + 20.0, 3.0, 12.0)
	hazard.top_level = true
	add_child(hazard)
	hazard.global_position = Vector3((corridor_min_x + corridor_max_x) * 0.5, -6.6, bridge_mid.y - 2.0)


func _restore_state() -> void:
	_raised = GameState.has_flag(&"bridge_raised")
	_apply(false)


func _hum_machine() -> void:
	if hum == null:
		hum = Audio.make_loop_3d(get_node("Machine"), &"machine_hum", -14.0, 4.0, 30.0)


func _refresh_prompt() -> void:
	if _raised:
		interactable.enabled = false
		return
	var have := GameState.set_count(switch_set)
	interactable.locked = have < required_switches
	interactable.locked_prompt = "No power  (%d/%d switches)" % [have, required_switches]
	PropLibrary.set_power(_machine, float(have) / required_switches * 0.5)


func _on_used(_player: Node) -> void:
	if _raised or GameState.set_count(switch_set) < required_switches:
		return
	_raised = true
	interactable.enabled = false
	GameState.set_flag(&"bridge_raised", true)
	Audio.play_sfx_3d(&"lever", machine_position(), 0.0)
	if _lever:
		var lt := create_tween()
		lt.tween_property(_lever, "rotation:x", 0.9, 0.5).set_trans(Tween.TRANS_BACK)
	tween_power(_machine, 0.5, 1.0, 0.8)
	Events.look_at_requested.emit((_start + _end) * 0.5 + Vector3.UP, 5.0)
	_apply(true)
	await get_tree().create_timer(4.0).timeout
	Events.restoration_requested.emit(&"forest", self)


func _apply(animate: bool) -> void:
	for blocker in _end_blockers:
		blocker.set_deferred("disabled", _raised)
	_deck_body.process_mode = Node.PROCESS_MODE_INHERIT if _raised else Node.PROCESS_MODE_DISABLED
	if not _raised:
		for plank in _planks:
			plank.visible = false
		for rail in _rails:
			rail.visible = false
		return
	if not animate:
		for plank in _planks:
			plank.visible = true
		for rail in _rails:
			rail.visible = true
		PropLibrary.set_power(_machine, 1.0)
		_hum_machine()
		return
	if _gear:
		var gt := create_tween()
		gt.tween_property(_gear, "rotation:z", _gear.rotation.z + TAU * 2.0, 3.6)
	Audio.play_sfx_3d(&"bridge_extend", (_start + _end) * 0.5, 0.0)
	for i in _planks.size():
		var plank := _planks[i]
		var target_y := plank.position.y
		plank.position.y = target_y - 3.0
		plank.visible = true
		var pt := create_tween()
		pt.tween_interval(i * 0.12)
		pt.tween_property(plank, "position:y", target_y, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hum_machine()
	await get_tree().create_timer(_planks.size() * 0.12 + 0.3).timeout
	for rail in _rails:
		rail.visible = true
		rail.scale = Vector3(1, 0.01, 1)
		var rt := create_tween()
		rt.tween_property(rail, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK)
