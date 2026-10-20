extends FacilityArea
## Area 6: the Alien Energy Reactor. A vast cavern around a living alien core, deep under the
## research station. Stabilize it in three steps:
##   1. Synchronize the bridge arms: two arms swing over the pit; lock each one at the moment
##      it lines up with the bridge (a console lamp turns green inside the window).
##   2. Balance the cores: pour energy between cores of capacity 8, 5 and 3 until A and B
##      hold 4 each (a transfer pours until the source is empty or the target is full).
##   3. Wake the four nodes on the upper pads in the rhythm the heart beats (3, 1, 4, 2 beats),
##      crossing timed hard-light bridges. A moving lift carries the robot up.
## Hazards: plasma vents on the entry walkway (telegraphed), the pit (back to checkpoint).

const STEP_SET := &"reactor_stability"
const CAPS := [8, 5, 3]
const START_LEVELS := [8, 0, 0]
const RHYTHM := [3, 1, 4, 2]
const PAD_DOTS := [2, 4, 1, 3]      # P1..P4
const PAD_POS := [Vector3(-10.5, 8, -24.5), Vector3(10.5, 8, -24.5), Vector3(10.5, 8, -37.5), Vector3(-10.5, 8, -37.5)]
const ARM_WINDOW := 14.0
const STABLE_GREEN := Color(0.35, 1.0, 0.85)

var _vents: Array[ScifiParts.Hazard] = []
var _arms: Array[Dictionary] = []
var _cores: Array[Dictionary] = []
var _levels: Array[int] = []
var _heart: Node3D
var _heart_fx: MeshInstance3D
var _heart_light: OmniLight3D
var _nodes: Array[Dictionary] = []
var _node_progress := 0
var _bridges: Array[ScifiParts.EnergyBridge] = []
var _portal_bridge: ScifiParts.EnergyBridge
var _portal_disc: MeshInstance3D
var _portal_it: Interactable
var _rings: Array[Node3D] = []
var _gears: Array[Node3D] = []
var _plasma: MeshInstance3D
var _lift: ScifiParts.MovingPlatform
var _time := 0.0
var _beat_t := 0.0
var _beat_queue: Array[float] = []


func _ready() -> void:
	bounds_size = Vector3(100, 70, 130)
	bounds_center = Vector3(0, 6, -12)
	_build_cavern()
	_build_entry()
	_build_walkway()
	_build_arms()
	_build_core_platform()
	_build_upper_pads()
	_build_portal()
	var kill := ScifiParts.KillZone.new()
	kill.size = Vector3(110, 2, 140)
	kill.on_enter = func() -> void: facility.respawn_at_checkpoint(true)
	add_child(kill)
	kill.position = Vector3(0, -9, -12)
	_restore()


func mood() -> Dictionary:
	var stable := _is_stable()
	return {
		"ambient": Color(0.16, 0.24, 0.25) if not stable else Color(0.2, 0.28, 0.3),
		"ambient_energy": 0.95,
		"fog": Color(0.25, 0.45, 0.42),
		"fog_density": 0.006,
		"vol_fog": 0.02 if not stable else 0.014,
		"vol_albedo": Color(0.55, 0.85, 0.78),
		"glow": 1.0, "exposure": 1.05, "nebula": 0.0, "planet": 0.0,
	}


func on_respawn() -> void:
	for vent in _vents:
		vent.paused = false


func _is_stable() -> bool:
	return GameState.set_count(STEP_SET) >= GameData.REACTOR_STABILITY_COUNT


func _process(delta: float) -> void:
	_time += delta
	for i in _rings.size():
		_rings[i].rotation.y += delta * (0.12 if i == 0 else -0.08)
	for i in _gears.size():
		_gears[i].rotation.y += delta * (0.3 if i % 2 == 0 else -0.45)
	_update_arms(delta)
	_update_heart(delta)


# --- Construction helpers ----------------------------------------------------------------

func _slab(x0: float, x1: float, z0: float, z1: float, top: float, thickness := 0.8) -> MeshInstance3D:
	var size := Vector3(absf(x1 - x0), thickness, absf(z1 - z0))
	var block := ScifiKit.block(self, size, Vector3((x0 + x1) * 0.5, top - thickness * 0.5, (z0 + z1) * 0.5), &"reactor_floor")
	# Glowing edge trims along the long sides.
	for side in [-1.0, 1.0]:
		var trim := BoxMesh.new()
		trim.size = Vector3(size.x + 0.1, 0.08, 0.08) if size.x >= size.z else Vector3(0.08, 0.08, size.z + 0.1)
		var mi := MeshInstance3D.new()
		mi.mesh = trim
		mi.material_override = ScifiKit.material("sf_alien_glow")
		add_child(mi)
		var off := Vector3(0, 0, side * size.z * 0.5) if size.x >= size.z else Vector3(side * size.x * 0.5, 0, 0)
		mi.position = Vector3((x0 + x1) * 0.5, top - 0.06, (z0 + z1) * 0.5) + off
	return block


func _support(x: float, z: float, top: float, w := 1.6) -> void:
	ScifiKit.block(self, Vector3(w, top + 26.0, w), Vector3(x, (top - 26.0) * 0.5 - 0.4, z), &"reactor_support", false)


func _label(text: String, pos: Vector3, yaw := 0.0, size := 0.08, color := STABLE_GREEN) -> Label3D:
	var l := ScifiKit.sign(self, text, pos, yaw, size, color)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	return l


# --- Cavern ---------------------------------------------------------------------------

func _build_cavern() -> void:
	for x in [-46.0, 46.0]:
		ScifiKit.block(self, Vector3(2, 64, 120), Vector3(x, 8, -12), &"reactor_cavern", false)
	for z in [-72.0, 48.0]:
		ScifiKit.block(self, Vector3(94, 64, 2), Vector3(0, 8, z), &"reactor_cavern", false)
	ScifiKit.block(self, Vector3(94, 2, 122), Vector3(0, 40, -12), &"reactor_cavern", false)
	# Glowing conduit bands circling the cavern at a few heights (instead of a grid of strips).
	for y in [-6.0, 16.0]:
		for side: Array in [[Vector3(-44.9, y, -12), Vector3(0.12, 0.25, 118)], [Vector3(44.9, y, -12), Vector3(0.12, 0.25, 118)],
				[Vector3(0, y, -70.9), Vector3(92, 0.25, 0.12)], [Vector3(0, y, 46.9), Vector3(92, 0.25, 0.12)]]:
			var band := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = side[1]
			band.mesh = box
			band.material_override = ScifiKit.material("sf_alien_glow")
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(band)
			band.position = side[0]
	# The plasma sea far below.
	var plane := PlaneMesh.new()
	plane.size = Vector2(92, 120)
	_plasma = ScifiKit.energy_mesh(self, plane, Vector3(0, -24, -12), Color(0.15, 0.7, 0.55), Color(0.8, 1.0, 0.6), 1.3)
	(_plasma.material_override as ShaderMaterial).set_shader_parameter("flow", Vector2(0.03, 0.05))
	(_plasma.material_override as ShaderMaterial).set_shader_parameter("noise_scale", 0.12)
	for p in [Vector3(-20, -16, -30), Vector3(20, -16, -30), Vector3(0, -16, 10), Vector3(0, -16, -55)]:
		var l := ScifiKit.light(self, p, Color(0.35, 1.0, 0.75), 3.0, 30.0)
		l.light_volumetric_fog_energy = 2.0
		l.distance_fade_enabled = false
	# Huge rings turning around the heart high above, and machinery on the walls.
	var ring := ScifiKit.place(self, "rx_ring", Vector3(0, 22, -31), 0.0, 2.4, "")
	_rings.append(ring)
	var ring2 := ScifiKit.place(self, "rx_ring", Vector3(0, 26, -31), 0.0, 1.6, "")
	ring2.rotation_degrees.x = 14.0
	_rings.append(ring2)
	for g: Array in [[Vector3(-44.5, 14, -20), 90.0], [Vector3(-44.5, 6, -42), 90.0], [Vector3(44.5, 12, -30), -90.0], [Vector3(44.5, 20, 5), -90.0], [Vector3(10, 18, -71), 0.0]]:
		var holder := Node3D.new()
		add_child(holder)
		holder.position = g[0]
		holder.rotation_degrees = Vector3(90.0, g[1], 0.0)
		var gear := ScifiKit.place(holder, "rx_gear", Vector3.ZERO, 0.0, 2.2, "")
		_gears.append(gear)
	for p in [Vector3(-22, -16, -31), Vector3(22, -16, -31), Vector3(-22, -16, -2), Vector3(22, -16, -2), Vector3(-16, -16, -55), Vector3(16, -16, -55)]:
		ScifiKit.place(self, "rx_pylon", p, randf() * 60.0, 3.0, "")
	# Heavy cables hanging across the cavern.
	for i in 6:
		var a := Vector3(-45, 26 - i * 1.5, -60 + i * 18)
		var b := Vector3(45, 24 - i * 1.2, -50 + i * 14)
		_cable(a, b, 4.0 + i)


func _cable(a: Vector3, b: Vector3, sag: float) -> void:
	var pts: Array[Vector3] = []
	for i in 13:
		var t := float(i) / 12.0
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	for i in pts.size() - 1:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.18
		cyl.height = pts[i].distance_to(pts[i + 1])
		cyl.radial_segments = 8
		mi.mesh = cyl
		mi.material_override = ScifiKit.material("sf_dark")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var up := (pts[i + 1] - pts[i]).normalized()
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		mi.transform = Transform3D(Basis(side, up, side.cross(up)), (pts[i] + pts[i + 1]) * 0.5)


# --- Entry gantry and walkway ------------------------------------------------------------------

func _build_entry() -> void:
	_slab(-7, 7, 26, 37, 0.0)
	for p in [Vector2(-6, 27), Vector2(6, 27), Vector2(-6, 36), Vector2(6, 36)]:
		_support(p.x, p.y, 0.0)
	var lift := ScifiKit.place(self, "sf_lift", Vector3(0, 0, 33.5), 0.0)
	var up := Interactable.new()
	up.prompt = "Ride the freight lift up"
	up.radius = 2.2
	up.focus_offset = Vector3(1.2, 1.1, 1.3)
	up.robot_action = &""
	lift.add_child(up)
	up.interacted.connect(func(_p: Node) -> void: facility.teleport_to_checkpoint(&"lab_control"))
	ScifiKit.place(self, "sf_crate", Vector3(-5.2, 0, 34.5), 12.0)
	ScifiKit.place(self, "sf_crate", Vector3(-5.6, 0, 33.2), -8.0)
	ScifiKit.place(self, "sf_crate", Vector3(5.5, 0, 28.0), 30.0)
	ScifiKit.place(self, "sf_rack", Vector3(6.3, 0, 32.0), -90.0)
	var spot := ScifiKit.spot(self, Vector3(0, 9, 34), Vector3(0, 0, 30), Color(1.0, 0.9, 0.75), 3.0, 16.0, 45.0, true)
	spot.light_volumetric_fog_energy = 1.5
	var note := ScifiParts.HoloNote.new()
	note.text = "SURVEY TEAM 2 · REACTOR ACCESS\nThe core is unstable. Plasma vents on the walkway fire in sequence: watch the glow, then cross.\nThe bridge arms must be locked in sync before anyone can reach the core."
	note.color = Color(0.5, 1.0, 0.85)
	add_child(note)
	note.position = Vector3(3.5, 0, 28.5)


func _build_walkway() -> void:
	_slab(-2.2, 2.2, 6, 26, 0.0, 0.6)
	for z in [10.0, 18.0, 25.0]:
		_support(0, z, 0.0, 1.2)
	# Railings so the vents are the challenge, not falling off.
	for side in [-1.0, 1.0]:
		ScifiKit.block(self, Vector3(0.15, 0.7, 20), Vector3(side * 2.15, 0.35, 16), &"trim")
	for i in 3:
		var z := 21.0 - i * 5.0
		var vent := ScifiKit.place(self, "rx_vent", Vector3(0, 0.0, z), 0.0, 0.9, "")
		vent.position.y = -0.07
		var hazard := ScifiParts.Hazard.new()
		hazard.size = Vector3(4.2, 2.6, 2.2)
		hazard.period = 3.0
		hazard.telegraph = 0.85
		hazard.active_time = 0.9
		hazard.offset = i * 1.0
		hazard.on_hit = func(p: Player) -> void: ScifiParts.knock_back(p, hazard.global_position, 7.0)
		add_child(hazard)
		hazard.position = Vector3(0, 1.3, z)
		var col := CylinderMesh.new()
		col.top_radius = 1.0
		col.bottom_radius = 1.2
		col.height = 3.0
		col.cap_top = false
		col.cap_bottom = false
		var fx := ScifiKit.energy_mesh(self, col, Vector3(0, 1.5, z), Color(1.0, 0.45, 0.15), Color(1.0, 0.9, 0.5), 2.2)
		(fx.material_override as ShaderMaterial).set_shader_parameter("flow", Vector2(0.0, -1.8))
		hazard.visuals.append(fx)
		var glow := ScifiKit.light(self, Vector3(0, 0.6, z), Color(1.0, 0.5, 0.2), 0.0, 6.0)
		hazard.fired.connect(func() -> void:
			var tw := create_tween()
			glow.light_energy = 4.0
			tw.tween_property(glow, "light_energy", 0.0, 1.0))
		_vents.append(hazard)
	# Ramp up to the arm landing.
	var ramp := ScifiKit.block(self, Vector3(4.4, 0.4, 7.21), Vector3(0, 1.834, 3.889), &"reactor_floor")
	ramp.rotation_degrees.x = 33.69
	_slab(-4, 4, -2.05, 1.2, 4.0)
	_support(0, -0.5, 4.0)


# --- Bridge arms ---------------------------------------------------------------------------

func _build_arms() -> void:
	var defs := [
		{"pivot": Vector3(0, 4, -3.4), "aligned": 90.0, "period": 8.0, "console": Vector3(-3.0, 4, 0.4), "name": "ARM 1"},
		{"pivot": Vector3(0, 4, -22.6), "aligned": -90.0, "period": 6.5, "console": Vector3(3.0, 4, 0.4), "name": "ARM 2"},
	]
	for i in defs.size():
		var d: Dictionary = defs[i]
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		add_child(body)
		body.position = d["pivot"]
		body.add_child(ScifiKit.instance("rx_arm"))
		var pivot_cs := CollisionShape3D.new()
		var pivot_shape := CylinderShape3D.new()
		pivot_shape.radius = 1.3
		pivot_shape.height = 0.6
		pivot_cs.shape = pivot_shape
		pivot_cs.position = Vector3(0, -0.3, 0)
		body.add_child(pivot_cs)
		for part: Array in [[Vector3(9.0, 0.4, 1.6), Vector3(4.5, -0.2, 0)], [Vector3(1.8, 0.4, 1.8), Vector3(8.7, -0.2, 0)]]:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = part[0]
			cs.shape = box
			cs.position = part[1]
			body.add_child(cs)
		var console := ScifiKit.place(self, "sf_console", d["console"], 180.0)
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		lamp.mesh = sphere
		console.add_child(lamp)
		lamp.position = Vector3(0, 1.55, 0.2)
		_label(d["name"], (d["console"] as Vector3) + Vector3(0, 1.95, 0), 0.0, 0.07)
		var arm := {"body": body, "aligned": float(d["aligned"]), "period": float(d["period"]), "locked": false,
			"lamp": lamp, "angle": float(d["aligned"]), "t": i * 1.7}
		var it := Interactable.new()
		it.prompt = "Lock %s" % d["name"]
		it.radius = 1.8
		it.focus_offset = Vector3(0, 1.0, 0)
		console.add_child(it)
		it.interacted.connect(func(_p: Node) -> void: _try_lock(arm))
		arm["interactable"] = it
		_arms.append(arm)
	# Marker beacons on the bridge line show where the arms must stop.
	for z in [-7.5, -12.9, -18.3]:
		var beacon := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.06
		cyl.height = 0.8
		beacon.mesh = cyl
		beacon.material_override = ScifiKit.material("sf_glow_orange")
		add_child(beacon)
		beacon.position = Vector3(0, 6.2, z)
	var note := ScifiParts.HoloNote.new()
	note.text = "ARM SYNC\nEach arm swings across the gap. Lock it as it lines up with the bridge beacons: its console lamp turns green."
	note.color = Color(0.5, 1.0, 0.85)
	add_child(note)
	note.position = Vector3(0, 4, 0.6)
	ScifiKit.light(self, Vector3(0, 9, -1), Color(1.0, 0.85, 0.7), 2.0, 12.0, true)


func arm_offset(arm: Dictionary) -> float:
	return wrapf(float(arm["angle"]) - float(arm["aligned"]), -180.0, 180.0)


func arm_in_window(arm: Dictionary) -> bool:
	return absf(arm_offset(arm)) < ARM_WINDOW


func _update_arms(delta: float) -> void:
	for arm in _arms:
		var lamp: MeshInstance3D = arm["lamp"]
		if arm["locked"]:
			lamp.material_override = _glow_mat(STABLE_GREEN, 3.0)
			continue
		arm["t"] = float(arm["t"]) + delta
		arm["angle"] = float(arm["aligned"]) + 80.0 * sin(TAU * float(arm["t"]) / float(arm["period"]))
		(arm["body"] as Node3D).rotation_degrees.y = arm["angle"]
		lamp.material_override = _glow_mat(Color(0.3, 1.0, 0.45), 4.0) if arm_in_window(arm) else _glow_mat(Color(1.0, 0.55, 0.15), 2.0)


var _glow_mats := {}


func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var key := c.to_html() + str(e)
	if not _glow_mats.has(key):
		_glow_mats[key] = ScifiKit.glow(c, e)
	return _glow_mats[key]


func _try_lock(arm: Dictionary) -> void:
	if arm["locked"]:
		return
	if not arm_in_window(arm):
		Audio.play_sfx(&"error_buzz", -4.0)
		Events.toast("Missed. Lock it as it lines up with the beacons.", "locked")
		return
	_lock_arm(arm, true)


func _lock_arm(arm: Dictionary, animate: bool) -> void:
	arm["locked"] = true
	(arm["interactable"] as Interactable).enabled = false
	var body: Node3D = arm["body"]
	var idx := _arms.find(arm)
	GameState.set_puzzle_state(StringName("reactor_arm_%d" % idx), true)
	if animate:
		Audio.play_sfx_3d(&"sync_lock", body.global_position, 0.0)
		var tw := create_tween()
		tw.tween_property(body, "rotation_degrees:y", float(arm["aligned"]), 0.5).set_trans(Tween.TRANS_BACK)
	else:
		body.rotation_degrees.y = arm["aligned"]
	arm["angle"] = arm["aligned"]
	if _arms.all(func(a: Dictionary) -> bool: return a["locked"]) and not step_done(STEP_SET, &"arms"):
		complete_step(STEP_SET, &"arms", "Bridge arms synchronized")
		show_effect(Vector3(0, 4, -13), 2.4)


# --- Core platform: heart and core balancing ----------------------------------------------------

func _build_core_platform() -> void:
	_slab(-13, 13, -40, -22, 4.0, 1.0)
	for p in [Vector2(-11, -24), Vector2(11, -24), Vector2(-11, -38), Vector2(11, -38), Vector2(0, -38)]:
		_support(p.x, p.y, 4.0, 2.2)
	_heart = ScifiKit.place(self, "rx_core", Vector3(0, 4, -31), 0.0, 1.2)
	var col := CylinderMesh.new()
	col.top_radius = 1.0
	col.bottom_radius = 1.0
	col.height = 6.8
	_heart_fx = ScifiKit.energy_mesh(self, col, Vector3(0, 8.26, -31), Color(0.25, 1.0, 0.8), Color(0.9, 1.0, 0.9), 2.0)
	_heart_light = ScifiKit.light(self, Vector3(0, 8, -31), STABLE_GREEN, 4.0, 26.0, true)
	_heart_light.light_volumetric_fog_energy = 2.5
	_heart_light.distance_fade_enabled = false
	var positions := [Vector3(-5.5, 4, -27.5), Vector3(5.5, 4, -27.5), Vector3(0, 4, -36.5)]
	var names := ["A", "B", "C"]
	for i in 3:
		var cap: int = CAPS[i]
		var s := 0.25 + cap * 0.04
		var core := ScifiKit.place(self, "rx_core", positions[i], 0.0, s)
		var h := 5.7 * s
		var fill := CylinderMesh.new()
		fill.top_radius = 0.95 * s
		fill.bottom_radius = 0.95 * s
		fill.height = h
		var fx := ScifiKit.energy_mesh(self, fill, positions[i] + Vector3(0, 0.7 * s + h * 0.5, 0), Color(0.3, 0.9, 1.0), Color(0.9, 1.0, 1.0), 2.4)
		var mat := fx.material_override as ShaderMaterial
		mat.set_shader_parameter("fill_bottom", -h * 0.5)
		mat.set_shader_parameter("fill_height", h)
		# Unit marks up the glass.
		for u in range(1, cap):
			var ring := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 1.12 * s
			tor.outer_radius = 1.2 * s
			ring.mesh = tor
			ring.material_override = ScifiKit.material("sf_alien")
			add_child(ring)
			ring.position = positions[i] + Vector3(0, 0.7 * s + h * float(u) / cap, 0)
		var label := _label("%s · %d" % [names[i], cap], positions[i] + Vector3(0, 7.6 * s + 0.4, 0), 0.0, 0.1)
		var level_label := _label("", positions[i] + Vector3(0, 7.6 * s + 0.0, 0), 0.0, 0.07, Color(0.85, 1.0, 1.0))
		_cores.append({"node": core, "fx": fx, "label": label, "level_label": level_label, "pos": positions[i]})
	var valves := [[0, 1, Vector3(0, 4, -25.2), 180.0], [1, 2, Vector3(5.2, 4, -33.2), 120.0], [2, 0, Vector3(-5.2, 4, -33.2), -120.0]]
	for v: Array in valves:
		var node := ScifiKit.place(self, "rx_valve", v[2], v[3])
		var text := "%s → %s" % [names[v[0]], names[v[1]]]
		_label(text, (v[2] as Vector3) + Vector3(0, 1.5, 0), 0.0, 0.08)
		var it := Interactable.new()
		it.prompt = "Transfer %s" % text
		it.radius = 1.6
		it.focus_offset = Vector3(0, 0.7, 0)
		node.add_child(it)
		var from_i: int = v[0]
		var to_i: int = v[1]
		it.interacted.connect(func(_p: Node) -> void:
			var wheel := node.get_node_or_null("valve_wheel") as Node3D
			if wheel:
				create_tween().tween_property(wheel, "rotation:y", wheel.rotation.y + PI, 0.6)
			transfer(from_i, to_i))
	var reset := ScifiKit.place(self, "sf_lever", Vector3(11.5, 4, -30), -90.0)
	_label("PURGE", Vector3(11.5, 5.5, -30), 0.0, 0.07, Color(1.0, 0.6, 0.3))
	var rit := Interactable.new()
	rit.prompt = "Purge the cores (start over)"
	rit.radius = 1.6
	rit.focus_offset = Vector3(0, 0.7, 0)
	reset.add_child(rit)
	rit.interacted.connect(func(_p: Node) -> void:
		if step_done(STEP_SET, &"cores"):
			return
		_levels.assign(START_LEVELS.duplicate())
		_save_levels()
		_update_cores(true)
		Audio.play_sfx(&"relay_toggle", -4.0))
	var note := ScifiParts.HoloNote.new()
	note.text = "CORE BALANCE\nA holds 8, B holds 5, C holds 3.\nA transfer pours until the source is empty or the target is full.\nThe heart steadies when A and B hold 4 each."
	note.color = Color(0.5, 1.0, 0.85)
	add_child(note)
	note.position = Vector3(-8.5, 4, -24.0)
	for p in [Vector3(-9, 14, -31), Vector3(9, 14, -31)]:
		ScifiKit.spot(self, p, Vector3(p.x * 0.4, 4, -31), Color(0.85, 0.95, 1.0), 4.0, 20.0, 55.0, p.x < 0.0)
	ScifiKit.spot(self, Vector3(0, 16, -18), Vector3(0, 4, -28), Color(1.0, 0.92, 0.8), 3.5, 24.0, 40.0, false)


## Pours from one core into another (exposed for tests).
func transfer(from_i: int, to_i: int) -> void:
	if step_done(STEP_SET, &"cores"):
		return
	var amount := mini(_levels[from_i], CAPS[to_i] - _levels[to_i])
	if amount <= 0:
		Audio.play_sfx(&"error_buzz", -6.0)
		return
	_levels[from_i] -= amount
	_levels[to_i] += amount
	_save_levels()
	Audio.play_sfx_3d(&"core_transfer", _cores[to_i]["pos"], -2.0)
	_arc(_cores[from_i]["pos"] + Vector3(0, 2, 0), _cores[to_i]["pos"] + Vector3(0, 2, 0))
	_update_cores(true)
	if _levels[0] == 4 and _levels[1] == 4:
		complete_step(STEP_SET, &"cores", "Cores balanced. The heart begins to beat.")
		show_effect(Vector3(0, 8, -31), 3.0)


func core_levels() -> Array[int]:
	return _levels.duplicate()


func _save_levels() -> void:
	GameState.set_puzzle_state(&"reactor_levels", _levels.duplicate())


func _update_cores(animate: bool) -> void:
	for i in 3:
		var fx: MeshInstance3D = _cores[i]["fx"]
		var target := float(_levels[i]) / float(CAPS[i])
		if animate:
			var from: float = fx.get_instance_shader_parameter("charge") if fx.get_instance_shader_parameter("charge") != null else target
			create_tween().tween_method(func(v: float) -> void: fx.set_instance_shader_parameter("charge", v), from, target, 0.9)
		else:
			fx.set_instance_shader_parameter("charge", target)
		(_cores[i]["level_label"] as Label3D).text = "%d / %d" % [_levels[i], CAPS[i]]


func _arc(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = a.distance_to(b)
	mi.mesh = cyl
	var m := ShaderMaterial.new()
	m.shader = ScifiKit.ENERGY
	m.set_shader_parameter("color_a", Color(0.3, 0.9, 1.0))
	m.set_shader_parameter("color_b", Color(1, 1, 1))
	m.set_shader_parameter("intensity", 4.0)
	m.set_shader_parameter("flow", Vector2(0, 3))
	m.set_shader_parameter("noise_tex", ScifiKit.NOISE)
	mi.material_override = m
	add_child(mi)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(side, up, side.cross(up)), global_transform * ((a + b) * 0.5))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("charge", v), 1.0, 0.0, 0.9)
	tw.tween_callback(mi.queue_free)


func _update_heart(delta: float) -> void:
	var balanced := step_done(STEP_SET, &"cores")
	var stable := _is_stable()
	var pulse := 0.0
	if stable:
		pulse = 0.25 + 0.25 * sin(_time * 1.6)
	elif balanced:
		# Beat groups of the rhythm: 3 . 1 . 4 . 2 ... (pause) ... repeat.
		_beat_t += delta
		if _beat_queue.is_empty():
			var t := 0.6
			for group: int in RHYTHM:
				for b in group:
					_beat_queue.append(t)
					t += 0.42
				t += 1.3
			_beat_queue.append(t + 2.2)   # end of cycle marker
			_beat_t = 0.0
		var next: float = _beat_queue[0]
		if _beat_t >= next:
			_beat_queue.pop_front()
			if not _beat_queue.is_empty():
				Audio.play_sfx_3d(&"note_low", _heart.global_position, -2.0, 0.5)
				_heart_flash = 1.0
		pulse = _heart_flash
		_heart_flash = maxf(_heart_flash - delta * 4.0, 0.0)
	else:
		pulse = 0.6 * absf(sin(_time * 7.3)) * (0.5 + 0.5 * sin(_time * 2.1))
	_heart_fx.set_instance_shader_parameter("pulse", pulse * 1.5)
	_heart_light.light_energy = 2.2 + pulse * 3.0
	_heart_light.light_color = STABLE_GREEN if balanced else Color(1.0, 0.55, 0.3).lerp(STABLE_GREEN, 0.35)


var _heart_flash := 0.0


# --- Upper pads: nodes, energy bridges and lift ---------------------------------------------------

func _build_upper_pads() -> void:
	for i in 4:
		var p: Vector3 = PAD_POS[i]
		ScifiKit.place(self, "rx_platform", p, 30.0)
		var node := ScifiKit.place(self, "rx_node", p, 0.0)
		var dots := ""
		for d in PAD_DOTS[i]:
			dots += "● "
		_label(dots.strip_edges(), p + Vector3(0, 3.0, 0), 0.0, 0.11)
		var it := Interactable.new()
		it.prompt = "Wake the node"
		it.radius = 1.9
		it.focus_offset = Vector3(0, 1.5, 0)
		node.add_child(it)
		var entry := {"node": node, "dots": PAD_DOTS[i], "on": false, "interactable": it}
		it.interacted.connect(func(_p: Node) -> void: wake_node(_nodes.find(entry)))
		_nodes.append(entry)
		var l := ScifiKit.light(self, p + Vector3(0, 2.2, 0), STABLE_GREEN, 1.0, 6.0)
		entry["light"] = l
	# Hard-light bridges between neighbouring pads, phasing on and off.
	var defs := [[0, 1, 4.5, 2.5, 0.0], [1, 2, 3.5, 2.0, 1.2], [2, 3, 4.5, 2.5, 2.4], [3, 0, 3.5, 2.0, 0.6]]
	for d: Array in defs:
		var a: Vector3 = PAD_POS[d[0]]
		var b: Vector3 = PAD_POS[d[1]]
		var bridge := ScifiParts.EnergyBridge.new()
		var length := a.distance_to(b) - 4.6
		var along_x := absf(b.x - a.x) > absf(b.z - a.z)
		bridge.size = Vector3(length, 0.18, 1.8) if along_x else Vector3(1.8, 0.18, length)
		bridge.cycle_on = d[2]
		bridge.cycle_off = d[3]
		bridge.cycle_offset = d[4]
		add_child(bridge)
		bridge.position = (a + b) * 0.5 + Vector3(0, -0.09, 0)
		_bridges.append(bridge)
	_lift = ScifiParts.MovingPlatform.new()
	_lift.points.assign([Vector3(-10.5, 4.0, -20.4), Vector3(-10.5, 8.0, -20.4)])
	_lift.speed = 1.4
	_lift.pause = 2.2
	add_child(_lift)
	var note := ScifiParts.HoloNote.new()
	note.text = "NODE RITE\nWake the nodes in the rhythm of the heart."
	note.color = Color(0.5, 1.0, 0.85)
	add_child(note)
	note.position = Vector3(-8.0, 4, -21.2)


## Activates a node (exposed for tests). Wrong order overloads and resets all nodes.
func wake_node(index: int) -> void:
	if step_done(STEP_SET, &"nodes") or index < 0:
		return
	var entry := _nodes[index]
	if entry["on"]:
		return
	if not step_done(STEP_SET, &"cores"):
		Audio.play_sfx(&"error_buzz", -6.0)
		Events.toast("The node is dark. The heart is too unstable.", "locked")
		return
	var expected: int = RHYTHM[_node_progress]
	var node: Node3D = entry["node"]
	if int(entry["dots"]) == expected:
		entry["on"] = true
		_node_progress += 1
		Audio.play_sfx_3d(&"node_wake", node.global_position, 0.0)
		ScifiKit.set_glow(node, Color(1.0, 0.95, 0.6), 5.0)
		(entry["light"] as OmniLight3D).light_color = Color(1.0, 0.95, 0.6)
		(entry["light"] as OmniLight3D).light_energy = 2.5
		if _node_progress >= RHYTHM.size():
			complete_step(STEP_SET, &"nodes", "Reactor stabilized")
			_set_stable(true)
		return
	Audio.play_sfx(&"overload", 0.0)
	Events.toast("Overload. The nodes fell out of rhythm.", "locked")
	node.add_child(FxFactory.burst(Color(1.0, 0.6, 0.3), 30, 4.0, 0.1))
	_node_progress = 0
	for e: Dictionary in _nodes:
		e["on"] = false
		ScifiKit.set_glow(e["node"], STABLE_GREEN, 3.0)
		(e["light"] as OmniLight3D).light_color = STABLE_GREEN
		(e["light"] as OmniLight3D).light_energy = 1.0


# --- Portal ----------------------------------------------------------------------------------

func _build_portal() -> void:
	_slab(-4.5, 4.5, -53, -44, 4.0)
	_support(0, -49, 4.0, 2.4)
	ScifiKit.place(self, "qt_portal", Vector3(0, 6.3, -50), 0.0, 1.0, "trimesh")
	var quad := QuadMesh.new()
	quad.size = Vector2(4.1, 4.1)
	_portal_disc = MeshInstance3D.new()
	_portal_disc.mesh = quad
	var pm := ShaderMaterial.new()
	pm.shader = ScifiKit.PORTAL
	pm.set_shader_parameter("noise_tex", ScifiKit.NOISE)
	_portal_disc.material_override = pm
	add_child(_portal_disc)
	_portal_disc.position = Vector3(0, 6.3, -50)
	_portal_bridge = ScifiParts.EnergyBridge.new()
	_portal_bridge.size = Vector3(2.4, 0.18, 4.4)
	add_child(_portal_bridge)
	_portal_bridge.position = Vector3(0, 3.91, -42.0)
	_portal_it = Interactable.new()
	_portal_it.prompt = "Step through the portal"
	_portal_it.radius = 2.6
	_portal_it.focus_offset = Vector3(0, 2.3, 0)
	_portal_it.robot_action = &""
	add_child(_portal_it)
	_portal_it.position = Vector3(0, 4.0, -48.5)
	_portal_it.interacted.connect(func(_p: Node) -> void: facility.teleport_to_checkpoint(&"quantum_entry", &"portal_whoosh"))
	ScifiKit.light(self, Vector3(0, 7, -48), Color(0.75, 0.5, 1.0), 2.0, 10.0)


func _set_stable(animate: bool) -> void:
	_portal_bridge.solid = true
	_portal_it.enabled = true
	_portal_disc.visible = true
	for vent in _vents:
		vent.paused = true
	for b in _bridges:
		b.cycle_on = 0.0
		b.solid = true
	if animate:
		_portal_disc.set_instance_shader_parameter("open", 0.0)
		create_tween().tween_method(func(v: float) -> void: _portal_disc.set_instance_shader_parameter("open", v), 0.0, 1.0, 2.5)
		Audio.play_sfx(&"power_restore", 0.0)
		show_effect(Vector3(0, 6, -48), 3.0)


func _restore() -> void:
	var saved: Variant = GameState.get_puzzle_state(&"reactor_levels")
	# Saved through JSON, numbers come back as floats.
	var source: Array = saved if saved is Array and (saved as Array).size() == 3 else START_LEVELS.duplicate()
	_levels.assign(source.map(func(v: Variant) -> int: return int(v)))
	if step_done(STEP_SET, &"cores"):
		_levels.assign([4, 4, 0])
	_update_cores(false)
	for i in _arms.size():
		if step_done(STEP_SET, &"arms") or GameState.get_puzzle_state(StringName("reactor_arm_%d" % i), false):
			_lock_arm(_arms[i], false)
	_portal_bridge.solid = false
	_portal_it.enabled = false
	_portal_disc.visible = false
	if step_done(STEP_SET, &"nodes"):
		_node_progress = RHYTHM.size()
		for e: Dictionary in _nodes:
			e["on"] = true
			ScifiKit.set_glow(e["node"], Color(1.0, 0.95, 0.6), 5.0)
		_set_stable(false)
