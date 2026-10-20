class_name ScifiParts
extends RefCounted
## Reusable pieces for the facility areas: powered blast doors, holographic notes, timed
## hazards, flickering lights and a laser beam tracer.

const LASER_LAYER := 1 << 9


## Two-leaf blast door (sf_door prop). Sealed until open() is called; shows a locked prompt.
class Door extends Node3D:
	var locked_text := "Sealed. No power."
	var is_open := false
	var _frame: Node3D
	var _left: Node3D
	var _right: Node3D
	var _interactable: Interactable
	var _lamp_color := Color(1.0, 0.25, 0.2)

	func _ready() -> void:
		_frame = ScifiKit.place(self, "sf_door", Vector3.ZERO, 0.0, 1.0, "")
		_left = _frame.get_node("door_left")
		_right = _frame.get_node("door_right")
		# Frame posts and lintel collide; each leaf carries its own box that moves with it.
		for side in [-1.0, 1.0]:
			_box(_frame, Vector3(0.36, 3.3, 0.6), Vector3(side * 1.67, 1.65, 0))
		_box(_frame, Vector3(3.7, 0.5, 0.6), Vector3(0, 3.15, 0))
		_box(_left, Vector3(1.5, 2.9, 0.22), Vector3(0.75, 1.45, 0))
		_box(_right, Vector3(1.5, 2.9, 0.22), Vector3(-0.75, 1.45, 0))
		_interactable = Interactable.new()
		_interactable.prompt = locked_text
		_interactable.locked_prompt = locked_text
		_interactable.locked = true
		_interactable.robot_action = &""
		_interactable.radius = 2.4
		_interactable.focus_offset = Vector3(0, 1.0, 0)
		add_child(_interactable)
		ScifiKit.set_glow(_frame, _lamp_color, 2.4)

	func _box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
		var body := StaticBody3D.new()
		parent.add_child(body)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		body.add_child(cs)

	func open(instant := false) -> void:
		if is_open:
			return
		is_open = true
		_interactable.enabled = false
		ScifiKit.set_glow(_frame, Color(0.3, 1.0, 0.5), 2.4)
		if instant:
			_left.position.x = -2.9
			_right.position.x = 2.9
			return
		Audio.play_sfx_3d(&"door_slide", global_position, 0.0)
		var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(_left, "position:x", -2.9, 1.4)
		tween.tween_property(_right, "position:x", 2.9, 1.4)


## Floating holographic text over a projector (logs, clues, labels).
class HoloNote extends Node3D:
	var text := ""
	var color := Color(0.45, 0.9, 1.0)
	var height := 1.6
	var size := 0.05
	var projector := true
	var label: Label3D

	func _ready() -> void:
		if projector:
			ScifiKit.place(self, "sf_projector", Vector3.ZERO, 0.0, 1.0, "")
		label = ScifiKit.sign(self, text, Vector3(0, height, 0), 0.0, size, color)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.width = 1500.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		var glow := OmniLight3D.new()
		glow.light_color = color
		glow.light_energy = 0.5
		glow.omni_range = 2.5
		add_child(glow)
		glow.position = Vector3(0, height, 0)

	func _process(_delta: float) -> void:
		if label:
			var t := Time.get_ticks_msec() * 0.001
			label.modulate.a = 0.82 + 0.1 * sin(t * 3.0) - (0.4 if fmod(t * 7.3, 13.0) < 0.15 else 0.0)


## A hazard that charges (telegraph), fires for a while, then rests. Touching it while it is
## firing calls `on_hit(player)`. Visual nodes get their "charge"/"pulse" from `level`.
class Hazard extends Area3D:
	signal fired
	var period := 4.0
	var telegraph := 0.9
	var active_time := 1.2
	var offset := 0.0
	var size := Vector3(2, 2, 2)
	var on_hit: Callable
	var paused := false
	var level := 0.0
	var warn_sound: StringName = &"hazard_warn"
	var fire_sound: StringName = &"hazard_burst"
	var visuals: Array[GeometryInstance3D] = []
	var _t := 0.0
	var _was_active := false
	var _was_warning := false

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1 << 1
		monitoring = true
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		add_child(cs)
		_t = offset

	func is_active() -> bool:
		var phase := fmod(_t, period)
		return phase >= telegraph and phase < telegraph + active_time

	func _physics_process(delta: float) -> void:
		if not paused:
			_t += delta
		var phase := fmod(_t, period)
		var warning := phase < telegraph
		var active := is_active()
		level = (phase / telegraph * 0.35) if warning else (1.0 if active else 0.0)
		for v in visuals:
			v.set_instance_shader_parameter("charge", clampf(level, 0.0, 1.0))
		if warning and not _was_warning and not paused:
			Audio.play_sfx_3d(warn_sound, global_position, -10.0)
		if active and not _was_active:
			Audio.play_sfx_3d(fire_sound, global_position, -6.0)
			fired.emit()
		_was_warning = warning
		_was_active = active
		if active and on_hit.is_valid():
			for body in get_overlapping_bodies():
				if body is Player:
					on_hit.call(body)
					break


## Traces a laser through mirrors (StaticBody3D on LASER_LAYER with meta "mirror": "S" or "N")
## and draws it. Mirror "S": +X<->+Z / -X<->-Z.  Mirror "N": +X<->-Z / -X<->+Z.
## Bodies with meta "receiver" report hits; everything else on layer 1 blocks the beam.
class Laser extends Node3D:
	signal receiver_changed(receiver: Node, lit: bool)
	var direction := Vector3.RIGHT
	var max_length := 60.0
	var color := Color(1.0, 0.25, 0.2)
	var enabled := true
	var _segments: Array[MeshInstance3D] = []
	var _hits: Array[MeshInstance3D] = []
	var _lit: Dictionary = {}
	var _hum: AudioStreamPlayer3D
	var _mat: StandardMaterial3D
	var _timer := 0.0

	func _ready() -> void:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = color
		_mat.emission_enabled = true
		_mat.emission = color
		_mat.emission_energy_multiplier = 6.0
		_hum = Audio.make_loop_3d(self, &"laser_hum", -18.0, 3.0, 20.0)

	func _physics_process(delta: float) -> void:
		_timer -= delta
		if _timer > 0.0:
			return
		_timer = 0.05
		trace()

	func trace() -> Array:
		var points: Array[Vector3] = [global_position]
		var lit_now := {}
		if enabled:
			var origin := global_position
			var dir := direction.normalized()
			var space := get_world_3d().direct_space_state
			for bounce in 10:
				var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_length, 1 | ScifiParts.LASER_LAYER)
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					points.append(origin + dir * max_length)
					break
				var pos: Vector3 = hit["position"]
				var col: Object = hit["collider"]
				if col.has_meta("mirror"):
					var center: Vector3 = (col as Node3D).global_position
					pos = Vector3(center.x, origin.y, center.z)
					points.append(pos)
					dir = ScifiParts.reflect(dir, String(col.get_meta("mirror")))
					origin = pos + dir * 0.4
					continue
				points.append(pos)
				if col.has_meta("receiver"):
					lit_now[col.get_meta("receiver")] = true
				break
		_draw(points)
		for r: Object in lit_now:
			if not _lit.has(r):
				receiver_changed.emit(r, true)
		for r: Object in _lit:
			if not lit_now.has(r) and is_instance_valid(r):
				receiver_changed.emit(r, false)
		_lit = lit_now
		return points

	func _draw(points: Array[Vector3]) -> void:
		var count := points.size() - 1
		while _segments.size() < count:
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.025
			cyl.bottom_radius = 0.025
			cyl.height = 1.0
			cyl.radial_segments = 8
			cyl.rings = 1
			mi.mesh = cyl
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.top_level = true
			add_child(mi)
			var glow := OmniLight3D.new()
			glow.light_color = color
			glow.light_energy = 0.7
			glow.omni_range = 1.6
			glow.shadow_enabled = false
			mi.add_child(glow)
			_segments.append(mi)
		for i in _segments.size():
			var seg := _segments[i]
			seg.visible = i < count
			if i >= count:
				continue
			var a := points[i]
			var b := points[i + 1]
			var len := a.distance_to(b)
			var mid := (a + b) * 0.5
			var up := (b - a).normalized()
			var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
			# The unit cylinder runs along local Y: stretch that column to the segment length.
			seg.global_transform = Transform3D(Basis(side, up * len, side.cross(up)), mid)


static func reflect(dir: Vector3, kind: String) -> Vector3:
	var d := Vector3(roundf(dir.x), 0.0, roundf(dir.z))
	if kind == "S":
		return Vector3(d.z, 0.0, d.x)
	return Vector3(-d.z, 0.0, -d.x)


## Random flicker for failing lights: drives the energy of a light (and an optional lamp mesh).
class Flicker extends Node:
	var lights: Array[Light3D] = []
	var base_energy := 1.0
	var amount := 0.6
	var _t := 0.0
	var _next := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t < _next:
			return
		_next = _t + randf_range(0.04, 0.35)
		var e := base_energy * (randf_range(1.0 - amount, 1.0) if randf() > 0.12 else 0.05)
		for l in lights:
			if is_instance_valid(l):
				l.light_energy = e


## Platform that travels between points (pausing at each), carrying the robot.
class MovingPlatform extends AnimatableBody3D:
	var points: Array[Vector3] = []
	var speed := 2.0
	var pause := 1.2
	var prop := "rx_lift"
	var size := Vector3(2.8, 0.35, 2.8)
	var running := true
	var _index := 0
	var _wait := 0.0

	func _ready() -> void:
		sync_to_physics = true
		var visual := ScifiKit.instance(prop)
		add_child(visual)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = Vector3(0, -size.y * 0.5, 0)
		add_child(cs)
		if not points.is_empty():
			position = points[0]

	func _physics_process(delta: float) -> void:
		if not running or points.size() < 2:
			return
		if _wait > 0.0:
			_wait -= delta
			return
		var target := points[(_index + 1) % points.size()]
		var to := target - position
		var step := speed * delta
		if to.length() <= step:
			position = target
			_index = (_index + 1) % points.size()
			_wait = pause
		else:
			position += to.normalized() * step


## Hard-light bridge: a glowing slab that is solid only while `solid` is true. With a cycle
## set, it phases on and off by itself (telegraphed by flicker before vanishing).
class EnergyBridge extends StaticBody3D:
	var size := Vector3(2.0, 0.2, 8.0)
	var color_a := Color(0.12, 0.55, 0.75)
	var color_b := Color(0.55, 0.95, 1.0)
	var cycle_on := 0.0
	var cycle_off := 0.0
	var cycle_offset := 0.0
	var solid := true:
		set(value):
			solid = value
			_apply()
	var _mesh: MeshInstance3D
	var _shape: CollisionShape3D
	var _t := 0.0

	func _ready() -> void:
		var box := BoxMesh.new()
		box.size = size
		_mesh = ScifiKit.energy_mesh(self, box, Vector3.ZERO, color_a, color_b, 0.55)
		(_mesh.material_override as ShaderMaterial).set_shader_parameter("flow", Vector2(0.0, 0.25))
		(_mesh.material_override as ShaderMaterial).set_shader_parameter("noise_scale", 0.5)
		_shape = CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		_shape.shape = shape
		add_child(_shape)
		_t = cycle_offset
		_apply()

	func _physics_process(delta: float) -> void:
		if cycle_on <= 0.0:
			return
		_t += delta
		var phase := fmod(_t, cycle_on + cycle_off)
		var on := phase < cycle_on
		if on != solid:
			solid = on
		# Flicker during the last 0.6 s before switching off.
		if on and phase > cycle_on - 0.6:
			_mesh.set_instance_shader_parameter("charge", 0.35 + 0.65 * float(int(phase * 14.0) % 2))

	func _apply() -> void:
		if _shape == null:
			return
		_shape.disabled = not solid
		_mesh.set_instance_shader_parameter("charge", 1.0 if solid else 0.0)
		_mesh.visible = solid


## Falling into this volume sends the robot back to its checkpoint.
class KillZone extends Area3D:
	var size := Vector3(100, 4, 100)
	var on_enter: Callable

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1 << 1
		monitoring = true
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		add_child(cs)
		body_entered.connect(func(body: Node3D) -> void:
			if body is Player and on_enter.is_valid():
				on_enter.call())


## Knocks the robot away from a point and stuns it briefly (hazard contact).
static func knock_back(player: Player, from: Vector3, strength := 8.0) -> void:
	if player.has_meta("stunned"):
		return
	var away := player.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else -player.global_basis.z
	player.velocity = away * strength + Vector3.UP * 4.5
	player.visual.express(&"hurt", 0.8)
	player.visual.jolt(1.0)
	player.camera_rig.add_shake(0.5) if player.camera_rig else null
	Audio.play_sfx(&"bonk", -3.0)
	player.set_meta("stunned", true)
	player.input_enabled = false
	player.get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(player):
			player.input_enabled = true
			player.remove_meta("stunned"))
