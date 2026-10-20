extends FacilityArea
## Area 7: the Quantum Space-Time Laboratory. A white, impossible facility floating in a
## nebula, where gravity, space and time are lab equipment. Three systems, used in order and
## then all together:
##   1. Gravity: engage the low-gravity field and float up the well to the high ledge.
##   2. Phase: platforms belong to dimension A (blue) or B (amber); only one set is solid.
##      Switch dimensions at consoles on the white (neutral) platforms to cross the void.
##   3. Time: freeze time to slip past the spinning blades in the corridor.
##   Final: raise gravity, phase to B and freeze time, all at once, to reach the exit core.

const STEP_SET := &"quantum_systems"
const A_COLOR := Color(0.35, 0.65, 1.0)
const B_COLOR := Color(1.0, 0.6, 0.22)
const NEUTRAL_GLOW := Color(0.75, 0.5, 1.0)
const FREEZE_TIME := 6.0
const LOW_GRAVITY := 0.3

var dimension := 0
var frozen := false
var _freeze_left := 0.0
var _phase_platforms: Array[Dictionary] = []   # {body, dim, mesh, shape, ghost}
var _gravity_zones: Array[Dictionary] = []     # {area, on, console, motes, light}
var _blades: Array[Dictionary] = []            # {rotor, hazard, speed}
var _movers: Array[ScifiParts.MovingPlatform] = []
var _floaters: Array[Node3D] = []
var _rifts: Array[MeshInstance3D] = []
var _core: Node3D
var _core_it: Interactable
var _exit_disc: MeshInstance3D
var _exit_it: Interactable
var _completion: CompletionScreen
var _time := 0.0
var _mat_solid := {}
var _mat_ghost := {}


func _ready() -> void:
	bounds_size = Vector3(110, 70, 120)
	bounds_center = Vector3(14, 8, -16)
	for dim in [0, 1]:
		var c: Color = A_COLOR if dim == 0 else B_COLOR
		var solid := ScifiKit.glow(c, 1.6)
		solid.albedo_color = Color(0.92, 0.93, 0.97).lerp(c, 0.25)
		solid.emission_energy_multiplier = 0.35
		solid.roughness = 0.2
		_mat_solid[dim] = solid
		_mat_ghost[dim] = ScifiKit.holo_material(c, 0.12, 0.8)
	_build_antechamber()
	_build_gravity_well()
	_build_phase_bridge()
	_build_time_corridor()
	_build_final()
	_build_impossible_decor()
	var kill := ScifiParts.KillZone.new()
	kill.size = Vector3(130, 2, 140)
	kill.on_enter = func() -> void: facility.respawn_at_checkpoint(true)
	add_child(kill)
	kill.position = Vector3(14, -8, -16)
	_completion = (load("res://scenes/ui/completion_screen.tscn") as PackedScene).instantiate() as CompletionScreen
	add_child(_completion)
	_restore()


func mood() -> Dictionary:
	var m := {
		"ambient": Color(0.5, 0.48, 0.6), "ambient_energy": 0.85, "fog": Color(0.55, 0.45, 0.75),
		"fog_density": 0.0025, "vol_fog": 0.006, "vol_albedo": Color(0.8, 0.75, 0.95),
		"glow": 0.9, "exposure": 1.0, "nebula": 1.0, "planet": 0.0, "saturation": 1.0,
	}
	if dimension == 1:
		m["ambient"] = Color(0.62, 0.48, 0.4)
		m["fog"] = Color(0.8, 0.55, 0.35)
		m["vol_albedo"] = Color(1.0, 0.8, 0.65)
	if frozen:
		m["saturation"] = 0.25
		m["exposure"] = 1.15
		m["ambient"] = Color(0.55, 0.62, 0.75)
	return m


func on_respawn() -> void:
	set_dimension(0, false)


func _process(delta: float) -> void:
	_time += delta
	if frozen:
		_freeze_left -= delta
		if _freeze_left <= 0.0:
			_set_frozen(false)
	var dt := 0.0 if frozen else delta
	for b: Dictionary in _blades:
		if b.get("stopped", false):
			continue
		(b["rotor"] as Node3D).rotation.y += dt * float(b["speed"])
	for i in _floaters.size():
		var f := _floaters[i]
		f.rotation.x += dt * 0.07 * (1.0 + i % 3)
		f.rotation.y += dt * 0.05 * (1.0 + i % 2)
	for mover in _movers:
		mover.running = not frozen
	for r in _rifts:
		r.rotation.z += dt * 0.2
	if _core_it and _core_it.enabled:
		_core_it.locked = GameState.set_count(STEP_SET) < GameData.QUANTUM_SYSTEM_COUNT


# --- Builders ---------------------------------------------------------------------------

func _slab(x0: float, x1: float, z0: float, z1: float, top: float, thickness := 0.6, style: StringName = &"quantum_white") -> MeshInstance3D:
	var size := Vector3(absf(x1 - x0), thickness, absf(z1 - z0))
	return ScifiKit.block(self, size, Vector3((x0 + x1) * 0.5, top - thickness * 0.5, (z0 + z1) * 0.5), style)


func _wall(center: Vector3, size: Vector3) -> void:
	ScifiKit.block(self, size, center, &"quantum_white")


func _console(pos: Vector3, yaw: float, prompt: String, label: String, color: Color, action: Callable) -> Node3D:
	var c := ScifiKit.place(self, "qt_console", pos, yaw)
	ScifiKit.set_glow(c, color, 2.6)
	var l := ScifiKit.sign(self, label, pos + Vector3(0, 1.75, 0), 0.0, 0.07, color)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var it := Interactable.new()
	it.prompt = prompt
	it.radius = 1.7
	it.focus_offset = Vector3(0, 1.0, 0)
	c.add_child(it)
	it.interacted.connect(func(_p: Node) -> void: action.call())
	return c


func _note(text: String, pos: Vector3, color := NEUTRAL_GLOW) -> void:
	var note := ScifiParts.HoloNote.new()
	note.text = text
	note.color = color.lerp(Color.WHITE, 0.35)
	add_child(note)
	note.position = pos


# --- Antechamber --------------------------------------------------------------------------

func _build_antechamber() -> void:
	_slab(-6, 6, 20, 33, 0.0)
	_wall(Vector3(-6.2, 3, 26.5), Vector3(0.4, 6, 13))
	_wall(Vector3(6.2, 3, 26.5), Vector3(0.4, 6, 13))
	_wall(Vector3(0, 3, 33.2), Vector3(12.8, 6, 0.4))
	_slab(-6, 6, 20, 33, 6.4, 0.4)
	# The folded room: a staircase climbing down out of the ceiling, a doorway on the ceiling.
	var stairs := ScifiKit.place(self, "qt_stairs", Vector3(-3.5, 6.2, 31.0), 180.0, 1.0, "")
	stairs.rotation_degrees.z = 180.0
	ScifiKit.place(self, "qt_pillar", Vector3(3.5, 6.2, 30.0), 0.0, 1.0, "").rotation_degrees.x = 180.0
	ScifiKit.place(self, "qt_pad", Vector3(0, 0, 25.5), 0.0)
	var back_pad := ScifiKit.place(self, "qt_pad", Vector3(4.0, 0, 30.5), 0.0)
	var bit := Interactable.new()
	bit.prompt = "Return to the reactor"
	bit.radius = 1.4
	bit.focus_offset = Vector3(0, 0.5, 0)
	bit.robot_action = &""
	back_pad.add_child(bit)
	bit.interacted.connect(func(_p: Node) -> void: facility.teleport_to_checkpoint(&"reactor_cores", &"portal_whoosh"))
	ScifiKit.light(self, Vector3(0, 5.5, 26), Color(0.95, 0.95, 1.0), 2.0, 12.0, true)
	ScifiKit.light(self, Vector3(4.0, 1.0, 30.5), NEUTRAL_GLOW, 1.0, 4.0)
	_note("QUANTUM LAB · ANTECHAMBER\nHere gravity, phase and time are instruments.\nLearn each one. The exit needs all three.", Vector3(-3.5, 0, 22.5))


# --- Stage 1: gravity well ---------------------------------------------------------------------

func _build_gravity_well() -> void:
	_slab(-8, 8, -0.2, 20, 0.0)
	_wall(Vector3(-8.2, 7.5, 7), Vector3(0.4, 15, 26))
	_wall(Vector3(8.2, 7.5, 7), Vector3(0.4, 15, 26))
	_wall(Vector3(0, 10.5, 20.2), Vector3(16.8, 9, 0.4))
	_wall(Vector3(0, 5.0, -0.2), Vector3(16, 10, 0.4))
	_slab(-6, 6, -6.5, -0.2, 10.0, 0.8)
	# Floating platforms: the first is out of reach without the field.
	_float_platform(Vector3(-4, 2.4, 14))
	var mover := ScifiParts.MovingPlatform.new()
	mover.prop = "qt_platform"
	mover.size = Vector3(3.0, 0.45, 3.0)
	mover.points.assign([Vector3(1.5, 4.8, 9), Vector3(5.0, 4.8, 9)])
	mover.speed = 1.0
	mover.pause = 1.0
	add_child(mover)
	_movers.append(mover)
	_float_platform(Vector3(-3, 7.2, 4.5))
	_float_platform(Vector3(-6.6, 5.8, 15.5), 0.55)
	var zone := _gravity_zone(Vector3(0, 7.5, 7), Vector3(16, 15, 27))
	_console(Vector3(4.5, 0, 17.5), 200.0, "Engage the low-gravity field", "GRAVITY", NEUTRAL_GLOW,
		func() -> void: toggle_gravity(zone))
	zone["console_pos"] = Vector3(4.5, 1, 17.5)
	var ledge := Area3D.new()
	ledge.collision_layer = 0
	ledge.collision_mask = 1 << 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 3, 6)
	cs.shape = box
	ledge.add_child(cs)
	add_child(ledge)
	ledge.position = Vector3(0, 11.5, -3.4)
	ledge.body_entered.connect(func(body: Node3D) -> void:
		if body is Player and not step_done(STEP_SET, &"gravity"):
			complete_step(STEP_SET, &"gravity", "Gravity mastered"))
	_console(Vector3(-4.6, 10, -4.8), 30.0, "Shift dimension", "PHASE", NEUTRAL_GLOW, func() -> void: set_dimension(1 - dimension, true))
	ScifiKit.light(self, Vector3(0, 13, 9), Color(0.9, 0.9, 1.0), 2.2, 18.0, true)
	ScifiKit.light(self, Vector3(-5, 3, 15), NEUTRAL_GLOW, 1.2, 8.0)
	_note("GRAVITY WELL\nThe field lowers gravity inside the well.\nFloat up to the ledge.", Vector3(-4.5, 0, 18.5))


func _float_platform(pos: Vector3, scale := 1.0) -> Node3D:
	var p := ScifiKit.place(self, "qt_platform", pos, 0.0, scale)
	return p


func _gravity_zone(center: Vector3, size: Vector3) -> Dictionary:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	add_child(area)
	area.position = center
	var motes := FxFactory.ambient_motes(Color(0.8, 0.7, 1.0, 0.9), 90, size * 0.45, 0.07, 0.25, 6.0)
	motes.emitting = false
	area.add_child(motes)
	var light := ScifiKit.light(self, center, NEUTRAL_GLOW, 0.0, maxf(size.x, size.z) * 0.8)
	var zone := {"area": area, "on": false, "motes": motes, "light": light}
	area.body_entered.connect(func(body: Node3D) -> void:
		if body is Player and zone["on"]:
			(body as Player).gravity_scale = LOW_GRAVITY)
	area.body_exited.connect(func(body: Node3D) -> void:
		if body is Player:
			(body as Player).gravity_scale = 1.0)
	_gravity_zones.append(zone)
	return zone


## Turns a low-gravity field on or off (exposed for tests).
func toggle_gravity(zone: Dictionary, on: Variant = null) -> void:
	var value: bool = (not zone["on"]) if on == null else bool(on)
	zone["on"] = value
	(zone["motes"] as GPUParticles3D).emitting = value
	create_tween().tween_property(zone["light"], "light_energy", 1.6 if value else 0.0, 0.8)
	Audio.play_sfx(&"gravity_shift", -2.0, 1.0 if value else 0.8)
	var area: Area3D = zone["area"]
	for body in area.get_overlapping_bodies():
		if body is Player:
			(body as Player).gravity_scale = LOW_GRAVITY if value else 1.0
	GameState.set_puzzle_state(StringName("quantum_gravity_%d" % _gravity_zones.find(zone)), value)


# --- Stage 2: phase bridge -------------------------------------------------------------------

func _build_phase_bridge() -> void:
	var defs := [
		[Vector3(0, 10, -9), 0], [Vector3(3, 10, -13), 0], [Vector3(3, 10, -17.5), -1],
		[Vector3(-0.5, 10, -21), 1], [Vector3(-4, 10, -24.5), 1], [Vector3(-8.5, 10, -21), 1],
		[Vector3(-4.5, 10, -29), -1], [Vector3(-1, 10, -32.5), 0], [Vector3(2.5, 10, -36), 0],
	]
	for d: Array in defs:
		var pos: Vector3 = d[0]
		var dim: int = d[1]
		if dim < 0:
			var n := ScifiKit.place(self, "qt_platform", pos, 0.0)
			ScifiKit.set_glow(n, NEUTRAL_GLOW, 3.0)
			_console(pos + Vector3(-0.9, 0, -0.6), 30.0, "Shift dimension", "PHASE", NEUTRAL_GLOW, func() -> void: set_dimension(1 - dimension, true))
			continue
		_phase_platform(pos, dim)
	_slab(0, 8, -44, -38.5, 10.0, 0.8)
	ScifiKit.light(self, Vector3(0, 16, -22), Color(0.95, 0.95, 1.0), 2.5, 26.0, true)
	ScifiKit.light(self, Vector3(4, 13, -41), Color(0.95, 0.95, 1.0), 1.6, 10.0)
	var end := Area3D.new()
	end.collision_layer = 0
	end.collision_mask = 1 << 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 5.5)
	cs.shape = box
	end.add_child(cs)
	add_child(end)
	end.position = Vector3(4, 11.5, -41.25)
	end.body_entered.connect(func(body: Node3D) -> void:
		if body is Player and step_done(STEP_SET, &"gravity") and not step_done(STEP_SET, &"phase"):
			complete_step(STEP_SET, &"phase", "Phase shifting mastered"))
	_note("PHASE BRIDGE\nBlue platforms exist in dimension A, amber ones in B.\nOnly one dimension is solid at a time. Shift on the white platforms.", Vector3(4.2, 10, -5.2))
	# A time echo of the robot waving on the far platform.
	var echo := (load("res://assets/characters/pink_robot/pink_robot.glb") as PackedScene).instantiate() as Node3D
	add_child(echo)
	echo.position = Vector3(2.5, 10.15, -43.2)
	echo.rotation_degrees.y = 160.0
	var holo := ScifiKit.holo_material(Color(1.0, 0.55, 0.85), 0.3, 1.3)
	for mi: MeshInstance3D in echo.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = holo
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ap := echo.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(&"Victory"):
		ap.get_animation(&"Victory").loop_mode = Animation.LOOP_LINEAR
		ap.play(&"Victory")


func _phase_platform(pos: Vector3, dim: int) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.position = pos
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 0.45, 3.0)
	mi.mesh = box
	body.add_child(mi)
	mi.position = Vector3(0, -0.225, 0)
	var rim := MeshInstance3D.new()
	var rim_box := BoxMesh.new()
	rim_box.size = Vector3(3.1, 0.06, 3.1)
	rim.mesh = rim_box
	rim.material_override = ScifiKit.glow(A_COLOR if dim == 0 else B_COLOR, 3.0)
	body.add_child(rim)
	rim.position = Vector3(0, -0.02, 0)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 0.45, 3.0)
	cs.shape = shape
	cs.position = Vector3(0, -0.225, 0)
	body.add_child(cs)
	_phase_platforms.append({"body": body, "dim": dim, "mesh": mi, "rim": rim, "shape": cs})


## Switches the solid dimension (exposed for tests).
func set_dimension(dim: int, animate: bool) -> void:
	dimension = dim
	for p: Dictionary in _phase_platforms:
		var solid := int(p["dim"]) == dim
		(p["shape"] as CollisionShape3D).set_deferred("disabled", not solid)
		(p["mesh"] as MeshInstance3D).material_override = _mat_solid[p["dim"]] if solid else _mat_ghost[p["dim"]]
		(p["rim"] as MeshInstance3D).visible = solid
	if animate:
		Audio.play_sfx(&"phase_shift", -2.0, 1.0 if dim == 1 else 0.85)
		if facility and facility.player:
			FxFactory.ring_pulse(self, facility.player.global_position + Vector3(0, 0.4, 0), A_COLOR if dim == 0 else B_COLOR, 6.0, 0.7)
		Events.toast("Dimension %s" % ("A" if dim == 0 else "B"), "info")


# --- Stage 3: time corridor -------------------------------------------------------------------

func _build_time_corridor() -> void:
	_slab(8, 30, -43, -39.5, 10.0, 0.6)
	for z in [-43.1, -39.4]:
		ScifiKit.block(self, Vector3(22, 1.4, 0.2), Vector3(19, 10.7, z), &"quantum_white")
	# A clear ceiling stops hopping over the blades.
	var roof := MeshInstance3D.new()
	var roof_box := BoxMesh.new()
	roof_box.size = Vector3(22, 0.1, 3.8)
	roof.mesh = roof_box
	roof.material_override = ScifiKit.material("sf_glass")
	add_child(roof)
	roof.position = Vector3(19, 11.45, -41.25)
	var roof_body := StaticBody3D.new()
	roof.add_child(roof_body)
	var rcs := CollisionShape3D.new()
	var rshape := BoxShape3D.new()
	rshape.size = Vector3(22, 0.1, 3.8)
	rcs.shape = rshape
	roof_body.add_child(rcs)
	for x in [12.0, 18.5, 25.0]:
		_blade(Vector3(x, 10.0, -41.25), 5.5 if x != 18.5 else -6.5)
	_console(Vector3(6.6, 10, -39.6), 230.0, "Freeze time", "TIME", Color(0.6, 0.85, 1.0), func() -> void: freeze_time())
	var end := Area3D.new()
	end.collision_layer = 0
	end.collision_mask = 1 << 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 3, 4)
	cs.shape = box
	end.add_child(cs)
	add_child(end)
	end.position = Vector3(29.0, 11.5, -41.25)
	end.body_entered.connect(func(body: Node3D) -> void:
		if body is Player and step_done(STEP_SET, &"phase") and not step_done(STEP_SET, &"time"):
			complete_step(STEP_SET, &"time", "Time mastered"))
	for x in [10.0, 16.0, 22.0, 28.0]:
		ScifiKit.light(self, Vector3(x, 11.2, -41.25), Color(0.85, 0.9, 1.0), 0.9, 5.0)
	_note("TIME CORRIDOR\nNothing outruns these blades.\nStop the clock, then go. Boost helps.", Vector3(6.8, 10, -43.0), Color(0.6, 0.85, 1.0))


func _blade(pos: Vector3, speed: float) -> Dictionary:
	var base := ScifiKit.place(self, "qt_blade", pos, 0.0, 1.0, "")
	var rotor := base.get_node("blade_rotor") as Node3D
	var hazard := ScifiParts.Hazard.new()
	hazard.size = Vector3(5.8, 1.2, 5.8)
	hazard.period = 1.0
	hazard.telegraph = 0.0
	hazard.active_time = 1.0
	hazard.warn_sound = &""
	hazard.fire_sound = &""
	hazard.on_hit = func(p: Player) -> void:
		if not frozen:
			ScifiParts.knock_back(p, hazard.global_position, 9.0)
			facility.respawn_at_checkpoint(true)
	add_child(hazard)
	hazard.position = pos + Vector3(0, 0.75, 0)
	var hum := Audio.make_loop_3d(base, &"blade_whir", -10.0, 4.0, 22.0)
	var entry := {"rotor": rotor, "hazard": hazard, "speed": speed, "hum": hum, "pos": pos}
	_blades.append(entry)
	return entry


## Stops time for a few seconds (exposed for tests).
func freeze_time() -> void:
	if frozen:
		return
	_set_frozen(true)


func _set_frozen(on: bool) -> void:
	frozen = on
	for b: Dictionary in _blades:
		(b["hazard"] as ScifiParts.Hazard).paused = on
		(b["hazard"] as ScifiParts.Hazard).monitoring = not on and not b.get("stopped", false)
		if b["hum"]:
			(b["hum"] as AudioStreamPlayer3D).stream_paused = on
	if on:
		_freeze_left = FREEZE_TIME
		Audio.play_sfx(&"time_freeze", -1.0)
		if facility and facility.player:
			FxFactory.ring_pulse(self, facility.player.global_position + Vector3(0, 0.4, 0), Color(0.6, 0.85, 1.0), 9.0, 0.9)
		Events.toast("Time stopped", "info")
	else:
		Audio.play_sfx(&"time_resume", -2.0)


# --- Final challenge ----------------------------------------------------------------------------

func _build_final() -> void:
	_slab(30, 38, -46, -36, 10.0, 0.8)
	ScifiKit.place(self, "qt_platform", Vector3(34, 13.2, -48.5), 0.0)
	_slab(31, 37, -60, -54, 13.2, 0.8)
	_phase_platform(Vector3(34, 13.2, -52.0), 1)
	var zone := _gravity_zone(Vector3(34, 13, -48), Vector3(10, 10, 26))
	_console(Vector3(36.8, 10, -37.2), 200.0, "Engage the low-gravity field", "GRAVITY", NEUTRAL_GLOW,
		func() -> void: toggle_gravity(zone))
	_console(Vector3(32.6, 13.2, -47.4), 140.0, "Shift dimension", "PHASE", NEUTRAL_GLOW, func() -> void: set_dimension(1 - dimension, true))
	_console(Vector3(35.4, 13.2, -47.4), 220.0, "Freeze time", "TIME", Color(0.6, 0.85, 1.0), func() -> void: freeze_time())
	_core = ScifiKit.place(self, "qt_core", Vector3(34, 13.2, -57.5), 0.0)
	var ring := _blade(Vector3(34, 13.2, -57.5), 4.0)
	ring["final"] = true
	_core_it = Interactable.new()
	_core_it.prompt = "Open the way home"
	_core_it.locked_prompt = "Master gravity, phase and time first"
	_core_it.radius = 1.5
	_core_it.focus_offset = Vector3(0, 1.7, 0)
	_core.add_child(_core_it)
	_core_it.interacted.connect(func(_p: Node) -> void: activate_exit())
	var quad := QuadMesh.new()
	quad.size = Vector2(4.1, 4.1)
	_exit_disc = MeshInstance3D.new()
	_exit_disc.mesh = quad
	var pm := ShaderMaterial.new()
	pm.shader = ScifiKit.PORTAL
	pm.set_shader_parameter("noise_tex", ScifiKit.NOISE)
	pm.set_shader_parameter("portal_color", Color(1.0, 0.75, 0.9))
	pm.render_priority = 3
	_exit_disc.material_override = pm
	add_child(_exit_disc)
	_exit_disc.position = Vector3(34, 15.5, -59.6)
	_exit_it = Interactable.new()
	_exit_it.prompt = "Go home to the garden"
	_exit_it.radius = 2.0
	_exit_it.focus_offset = Vector3(0, 2.3, 0)
	_exit_it.robot_action = &""
	add_child(_exit_it)
	_exit_it.position = Vector3(34, 13.2, -58.8)
	_exit_it.interacted.connect(func(_p: Node) -> void: SceneRouter.travel_to(&"garden", &"heart"))
	var core_light := ScifiKit.light(self, Vector3(34, 15.5, -57.5), Color(0.85, 0.6, 1.0), 3.0, 14.0, true)
	core_light.distance_fade_enabled = false
	ScifiKit.light(self, Vector3(34, 15, -41), Color(0.95, 0.95, 1.0), 2.0, 14.0, true)
	_note("EXIT CORE\nThe way home is sealed behind every system at once.", Vector3(31.5, 10, -37.5))


## The final interaction (exposed for tests).
func activate_exit() -> void:
	if GameState.has_flag(&"quantum_complete"):
		return
	if GameState.set_count(STEP_SET) < GameData.QUANTUM_SYSTEM_COUNT:
		Audio.play_sfx(&"denied", -4.0)
		return
	GameState.set_flag(&"quantum_complete", true)
	Audio.play_sfx(&"heart_restore", 0.0)
	_open_exit(true)
	SaveSystem.save_game()
	show_effect(Vector3(34, 15, -58), 3.0)
	await get_tree().create_timer(4.2).timeout
	if is_inside_tree():
		Events.toast("All seven areas restored.", "discovery")
		_completion.open()


func _open_exit(animate: bool) -> void:
	_core_it.enabled = false
	_exit_disc.visible = true
	_exit_it.enabled = true
	for b: Dictionary in _blades:
		if b.get("final", false):
			b["stopped"] = true
			(b["hazard"] as ScifiParts.Hazard).monitoring = false
			if b["hum"]:
				(b["hum"] as AudioStreamPlayer3D).stop()
	ScifiKit.set_glow(_core, Color(1.0, 0.85, 0.95), 5.0)
	if animate:
		_exit_disc.set_instance_shader_parameter("open", 0.0)
		create_tween().tween_method(func(v: float) -> void: _exit_disc.set_instance_shader_parameter("open", v), 0.0, 1.0, 2.5)


# --- Decor ---------------------------------------------------------------------------------

func _build_impossible_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 26:
		var p := Vector3(rng.randf_range(-30, 60), rng.randf_range(-4, 30), rng.randf_range(-70, 20))
		if p.x > -10 and p.x < 40 and p.z > -62 and p.z < 22 and p.y > 4 and p.y < 18:
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.position = p
		var kind: String = ["qt_platform", "qt_pillar", "qt_stairs"][i % 3]
		var n := ScifiKit.place(holder, kind, Vector3.ZERO, 0.0, rng.randf_range(0.8, 2.2), "")
		n.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_floaters.append(n)
	for d: Array in [[Vector3(-42, 14, -24), 90.0, 2.2], [Vector3(72, 18, -30), -90.0, 2.6], [Vector3(16, 24, -96), 0.0, 3.0], [Vector3(26, 10, 52), 180.0, 1.8]]:
		var ring := ScifiKit.place(self, "qt_portal", d[0], d[1], d[2], "")
		var quad := QuadMesh.new()
		quad.size = Vector2(4.1, 4.1) * float(d[2])
		var disc := MeshInstance3D.new()
		disc.mesh = quad
		var pm := ShaderMaterial.new()
		pm.shader = ScifiKit.PORTAL
		pm.set_shader_parameter("noise_tex", ScifiKit.NOISE)
		pm.set_shader_parameter("strength", 0.14)
		pm.render_priority = 3
		disc.material_override = pm
		ring.add_child(disc)
		_rifts.append(disc)
	for p in [Vector3(-14, 4, -40), Vector3(44, 2, -10), Vector3(20, 26, -20)]:
		ScifiKit.light(self, p, NEUTRAL_GLOW, 1.5, 24.0)


func _restore() -> void:
	set_dimension(0, false)
	for i in _gravity_zones.size():
		var on: bool = bool(GameState.get_puzzle_state(StringName("quantum_gravity_%d" % i), false))
		_gravity_zones[i]["on"] = on
		(_gravity_zones[i]["motes"] as GPUParticles3D).emitting = on
		(_gravity_zones[i]["light"] as OmniLight3D).light_energy = 1.6 if on else 0.0
	_exit_disc.visible = false
	_exit_it.enabled = false
	if GameState.has_flag(&"quantum_complete"):
		_open_exit(false)


## Read-only helpers for tests.
func gravity_zone(index: int) -> Dictionary:
	return _gravity_zones[index]
