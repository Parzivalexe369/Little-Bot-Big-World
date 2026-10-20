extends FacilityArea
## Area 5: the Abandoned Space Research Facility. An orbital lab left in emergency power after
## Experiment Seven. Restore power in three steps:
##   1. Breaker Room: conduit couplers (each coupler toggles the conduits its pipes touch).
##   2. Optics Lab: push mirror carts along floor rails to route a laser to the receiver.
##   3. Control Room: restart four terminals in the reverse of the logged shutdown order.
## A loose vent (found with the scanner) hides a secret laboratory.

const STEP_SET := &"lab_power"
const COUPLER_START := [true, false, true, true, false]
const COUPLER_LINKS := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 2, 4]]
const CONDUIT_Z := [19.5, 21.75, 24.0, 26.25, 28.5]
const TERMINAL_NAMES := ["FIELD", "COOLANT", "CORE", "CONTAINMENT"]
const TERMINAL_ORDER := ["COOLANT", "CONTAINMENT", "FIELD", "CORE"]

var _door_a: ScifiParts.Door
var _door_b: ScifiParts.Door
var _door_c: ScifiParts.Door
var _conduits: Array[bool] = []
var _conduit_fx: Array[MeshInstance3D] = []
var _conduit_lamps: Array[Node3D] = []
var _lamp_on := ScifiKit.glow(Color(0.3, 0.95, 1.0), 3.0)
var _lamp_off := ScifiKit.glow(Color(1.0, 0.2, 0.15), 2.0)
var _couplers: Array[Node3D] = []
var _laser: ScifiParts.Laser
var _receiver: Node3D
var _carts: Array[Dictionary] = []
var _reward_glass: Node3D
var _vent: Node3D
var _vent_body: StaticBody3D
var _vent_interactable: Interactable
var _terminals: Array[Dictionary] = []
var _sequence: Array[String] = []
## Wall blocks; their light strips follow the power of the room they are in.
var _arch: Array[MeshInstance3D] = []
## One entry per ceiling light: {stage, red (emergency), main, lamp}.
var _light_spots: Array[Dictionary] = []
var _screens: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _flicker: ScifiParts.Flicker
var _freight: Interactable
var _power_stage := 0
var _time := 0.0


func _ready() -> void:
	bounds_size = Vector3(70, 20, 90)
	bounds_center = Vector3(0, 4, -4)
	_flicker = ScifiParts.Flicker.new()
	_flicker.base_energy = 0.55
	add_child(_flicker)
	_build_architecture()
	_build_arrival()
	_build_breaker_room()
	_build_optics_lab()
	_build_hidden_lab()
	_build_control_room()
	_restore()


func mood() -> Dictionary:
	# Emergency power: cool, dim ambient; the red comes only from the warning lights.
	var p := float(_power_stage) / 3.0
	return {
		"ambient": Color(0.22, 0.25, 0.31).lerp(Color(0.32, 0.35, 0.4), p),
		"ambient_energy": lerpf(0.75, 0.7, p),
		"fog": Color(0.4, 0.46, 0.55).lerp(Color(0.55, 0.62, 0.7), p),
		"fog_density": 0.003,
		"vol_fog": lerpf(0.018, 0.01, p),
		"vol_albedo": Color(0.7, 0.72, 0.76),
		"glow": 0.75, "exposure": lerpf(1.25, 1.0, p), "nebula": 0.5, "planet": 0.16,
	}


func _process(delta: float) -> void:
	_time += delta
	if _power_stage >= 3:
		for i in _arms.size():
			var arm := _arms[i]
			var lower := arm.get_node_or_null("arm_lower") as Node3D
			var upper := arm.get_node_or_null("arm_lower/arm_upper") as Node3D
			arm.rotation.y = sin(_time * 0.35 + i * 2.0) * 0.9
			if lower:
				lower.rotation.x = -0.35 + sin(_time * 0.5 + i) * 0.25
			if upper:
				upper.rotation.x = 0.9 + sin(_time * 0.7 + i * 1.3) * 0.35


# --- Architecture ---------------------------------------------------------------------

func _build_architecture() -> void:
	# Arrival hall
	_slab(Vector3(-8, 0, 18), Vector3(8, 0, 32), 5.0)
	_wall_z(32.0, -8.0, 8.0, 5.0, [])
	_wall_x(8.0, 18.0, 32.0, 5.0, [[21.0, 29.0, 1.2, 4.2]])
	_window(Vector3(8.0, 2.7, 25.0), Vector3(0.08, 3.0, 8.0))
	_wall_x(-8.0, 18.0, 32.0, 5.0, [[22.0, 26.0, 0.0, 3.4]])
	_wall_z(18.0, -8.0, 8.0, 5.0, [[-1.85, 1.85, 0.0, 3.4]])
	# Breaker room
	_slab(Vector3(-20, 0, 17), Vector3(-8, 0, 31), 5.0)
	_wall_x(-20.0, 17.0, 31.0, 5.0, [])
	_wall_z(17.0, -20.0, -8.0, 5.0, [])
	_wall_z(31.0, -20.0, -8.0, 5.0, [])
	# Corridor to the optics lab
	_slab(Vector3(-2.5, 0, 8), Vector3(2.5, 0, 18), 4.0)
	_wall_x(-2.5, 8.0, 18.0, 4.0, [])
	_wall_x(2.5, 8.0, 18.0, 4.0, [])
	# Optics lab
	_slab(Vector3(-14, 0, -14), Vector3(14, 0, 8), 6.0)
	_wall_z(8.0, -14.0, 14.0, 6.0, [[-2.5, 2.5, 0.0, 4.0]])
	_wall_z(-14.0, -14.0, 14.0, 6.0, [[-12.85, -9.15, 0.0, 3.4]])
	_wall_x(-14.0, -14.0, 8.0, 6.0, [])
	_wall_x(14.0, -14.0, 8.0, 6.0, [[-2.6, -1.4, 2.2, 3.5]])
	# Vent duct and hidden lab (raised floor)
	_slab_at(Vector3(14, 2.2, -2.6), Vector3(18, 2.2, -1.4), 1.3, &"lab_wall_dark")
	_wall_z(-2.6, 14.0, 18.0, 1.3, [], 2.2, &"lab_wall_dark")
	_wall_z(-1.4, 14.0, 18.0, 1.3, [], 2.2, &"lab_wall_dark")
	_slab_at(Vector3(18, 2.2, -8), Vector3(26, 2.2, 4), 3.2, &"lab_wall_dark")
	_wall_x(18.0, -8.0, 4.0, 3.2, [[-2.6, -1.4, 0.0, 1.3]], 2.2, &"lab_wall_dark")
	_wall_x(26.0, -8.0, 4.0, 3.2, [], 2.2, &"lab_wall_dark")
	_wall_z(-8.0, 18.0, 26.0, 3.2, [], 2.2, &"lab_wall_dark")
	_wall_z(4.0, 18.0, 26.0, 3.2, [], 2.2, &"lab_wall_dark")
	# Corridor to the control room
	_slab(Vector3(-13.5, 0, -24), Vector3(-8.5, 0, -14), 4.0)
	_wall_x(-13.5, -24.0, -14.0, 4.0, [])
	_wall_x(-8.5, -24.0, -14.0, 4.0, [])
	# Control room
	_slab(Vector3(-16, 0, -40), Vector3(4, 0, -24), 7.0)
	_wall_z(-24.0, -16.0, 4.0, 7.0, [[-13.5, -8.5, 0.0, 4.0]])
	_wall_z(-40.0, -16.0, 4.0, 7.0, [[-12.0, 0.0, 1.5, 6.0]])
	_window(Vector3(-6.0, 3.75, -40.0), Vector3(12.0, 4.5, 0.08))
	_wall_x(-16.0, -40.0, -24.0, 7.0, [[-33.85, -30.15, 0.0, 3.4]])
	_wall_x(4.0, -40.0, -24.0, 7.0, [])
	# Freight lift room
	_slab(Vector3(-24, 0, -36), Vector3(-16, 0, -28), 5.0)
	_wall_x(-24.0, -36.0, -28.0, 5.0, [])
	_wall_z(-36.0, -24.0, -16.0, 5.0, [])
	_wall_z(-28.0, -24.0, -16.0, 5.0, [])


## Floor slab and ceiling between two corners at floor level y=0.
func _slab(a: Vector3, b: Vector3, height: float) -> void:
	_slab_at(a, b, height, &"lab_ceiling")


func _slab_at(a: Vector3, b: Vector3, height: float, ceiling_style: StringName) -> void:
	var size := Vector3(absf(b.x - a.x), 0.4, absf(b.z - a.z))
	var c := Vector3((a.x + b.x) * 0.5, a.y - 0.2, (a.z + b.z) * 0.5)
	ScifiKit.block(self, size, c, &"lab_floor")
	ScifiKit.block(self, size, c + Vector3(0, height + 0.4, 0), ceiling_style)
	# Skirting trims are added by the walls.


## Wall along z (constant x) from z0 to z1, with rectangular gaps [za, zb, y0, y1].
func _wall_x(x: float, z0: float, z1: float, h: float, gaps: Array, base := 0.0, style: StringName = &"lab_wall") -> void:
	_wall(Vector3(x, base, z0), Vector3(x, base, z1), h, gaps, style)


func _wall_z(z: float, x0: float, x1: float, h: float, gaps: Array, base := 0.0, style: StringName = &"lab_wall") -> void:
	_wall(Vector3(x0, base, z), Vector3(x1, base, z), h, gaps, style)


func _wall(a: Vector3, b: Vector3, h: float, gaps: Array, style: StringName) -> void:
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var start := a.x if along_x else a.z
	var end := b.x if along_x else b.z
	var cuts: Array = [[start, start, 0.0, h]]
	for g: Array in gaps:
		cuts.append(g)
	cuts.append([end, end, 0.0, h])
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for i in cuts.size() - 1:
		var s0: float = cuts[i][1]
		var s1: float = cuts[i + 1][0]
		if s1 - s0 > 0.01:
			_wall_piece(a, along_x, s0, s1, 0.0, h, style)
	for g: Array in gaps:
		# Above and below each gap.
		if g[2] > 0.01:
			_wall_piece(a, along_x, g[0], g[1], 0.0, g[2], style)
		if g[3] < h - 0.01:
			_wall_piece(a, along_x, g[0], g[1], g[3], h, style)


func _wall_piece(a: Vector3, along_x: bool, s0: float, s1: float, y0: float, y1: float, style: StringName) -> void:
	var len := s1 - s0
	var mid := (s0 + s1) * 0.5
	var size := Vector3(len, y1 - y0, 0.4) if along_x else Vector3(0.4, y1 - y0, len)
	var center := Vector3(mid, a.y + (y0 + y1) * 0.5, a.z) if along_x else Vector3(a.x, a.y + (y0 + y1) * 0.5, mid)
	var block := ScifiKit.block(self, size, center, style)
	_arch.append(block)
	if y0 < 0.01:
		var trim := Vector3(len, 0.22, 0.48) if along_x else Vector3(0.48, 0.22, len)
		ScifiKit.block(self, trim, Vector3(center.x, a.y + 0.11, center.z), &"trim", false)


func _window(center: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = ScifiKit.material("sf_glass")
	add_child(mi)
	mi.position = center
	var body := StaticBody3D.new()
	mi.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)


func _light(stage: int, pos: Vector3, energy := 1.6, light_range := 9.0, shadow := false) -> void:
	# Each spot gets an emergency red light (on until main power) and a main light.
	var lamp := ScifiKit.place(self, "sf_lamp", pos + Vector3(0, 0.05, 0), 0.0, 1.0, "")
	lamp.rotation_degrees.x = 180.0
	var red := ScifiKit.light(self, pos + Vector3(0, -0.4, 0), Color(1.0, 0.22, 0.14), 0.55, light_range * 0.75)
	red.light_volumetric_fog_energy = 0.5
	_flicker.lights.append(red)
	var main := ScifiKit.light(self, pos + Vector3(0, -0.4, 0), Color(0.92, 0.96, 1.0), energy, light_range, shadow)
	main.visible = false
	main.set_meta("energy", energy)
	_light_spots.append({"stage": stage, "red": red, "main": main, "lamp": lamp})
	ScifiKit.set_glow(lamp, Color(0.15, 0.05, 0.05), 0.3)


# --- Arrival hall --------------------------------------------------------------------------

func _build_arrival() -> void:
	var lift := ScifiKit.place(self, "sf_lift", Vector3(0, 0, 28.5), 0.0)
	var up := Interactable.new()
	up.prompt = "Ride the lift up to the garden"
	up.radius = 2.2
	up.focus_offset = Vector3(1.2, 1.1, 1.3)
	up.robot_action = &""
	lift.add_child(up)
	up.interacted.connect(func(_p: Node) -> void: SceneRouter.travel_to(&"garden", &"garden_lift"))
	for i in 2:
		_light(1, Vector3(-3.5 + i * 7.0, 5.0, 25.0), 1.5, 10.0, i == 0)
	_light(1, Vector3(0, 5.0, 20.0), 1.2, 8.0)
	# Crate stack hiding a fragment on top.
	ScifiKit.place(self, "sf_crate", Vector3(-5.5, 0, 21.0), 8.0)
	ScifiKit.place(self, "sf_crate", Vector3(-5.5, 0.9, 21.0), -6.0)
	ScifiKit.place(self, "sf_crate", Vector3(-4.4, 0, 22.1), 20.0)
	ScifiKit.place(self, "sf_crate", Vector3(6.6, 0, 30.6), 0.0)
	ScifiKit.place(self, "sf_rack", Vector3(-7.2, 0, 30.2), 90.0)
	ScifiKit.place(self, "sf_console", Vector3(5.8, 0, 19.4), 180.0)
	_screens.append(ScifiKit.place(self, "sf_console", Vector3(3.6, 0, 19.4), 180.0))
	_build_station_map(Vector3(0, 0, 24.5))
	_ceiling_pipes(Vector3(-7.5, 4.6, 19), Vector3(-7.5, 4.6, 31.5))
	_ceiling_pipes(Vector3(7.5, 4.6, 19), Vector3(7.5, 4.6, 31.5))
	ScifiKit.place(self, "sf_shelf", Vector3(-7.4, 0, 27.0), 90.0)
	ScifiKit.place(self, "sf_cart", Vector3(-3.0, 0, 30.0), 25.0)
	ScifiKit.place(self, "sf_crate", Vector3(7.0, 0, 21.2), 15.0)
	var note := ScifiParts.HoloNote.new()
	note.text = "EMERGENCY POWER ONLY\nMain bus offline after Experiment 7.\nReconnect the conduit couplers in the Breaker Room (west)."
	add_child(note)
	note.position = Vector3(3.0, 0, 21.5)
	_door_a = ScifiParts.Door.new()
	_door_a.locked_text = "Sealed. The main bus has no power."
	add_child(_door_a)
	_door_a.position = Vector3(0, 0, 18.0)
	var sign := ScifiKit.sign(self, "ARRIVAL HALL  ·  DECK 3", Vector3(0, 4.2, 31.75), 180.0, 0.09)
	sign.modulate = Color(0.85, 0.9, 0.95, 0.8)


# --- Breaker room: conduit couplers --------------------------------------------------------

func _build_breaker_room() -> void:
	_light(1, Vector3(-14, 5.0, 24), 1.6, 12.0, true)
	_light(1, Vector3(-14, 5.0, 19.5), 1.0, 7.0)
	for i in 5:
		var z: float = CONDUIT_Z[i]
		# Glass conduit with metal end caps; the energy core inside shows its state.
		var tube := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.22
		cyl.height = 3.6
		cyl.radial_segments = 24
		tube.mesh = cyl
		tube.material_override = ScifiKit.material("sf_glass")
		add_child(tube)
		tube.position = Vector3(-19.45, 2.4, z)
		for y in [0.3, 4.5]:
			ScifiKit.block(self, Vector3(0.6, 0.4, 0.6), Vector3(-19.45, y, z), &"trim", false)
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = 0.1
		core_mesh.bottom_radius = 0.1
		core_mesh.height = 3.6
		core_mesh.radial_segments = 16
		var fx := ScifiKit.energy_mesh(self, core_mesh, Vector3(-19.45, 2.4, z), Color(0.25, 0.85, 1.0), Color(0.9, 1.0, 1.0), 2.4)
		var core_light := OmniLight3D.new()
		core_light.light_color = Color(0.35, 0.85, 1.0)
		core_light.light_energy = 0.8
		core_light.omni_range = 2.2
		fx.add_child(core_light)
		_conduit_fx.append(fx)
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		lamp.mesh = sphere
		add_child(lamp)
		lamp.position = Vector3(-19.3, 4.75, z)
		_conduit_lamps.append(lamp)
		ScifiKit.sign(self, "C%d" % (i + 1), Vector3(-19.7, 5.15, z), 90.0, 0.07)
	# Wall couplers between neighbouring conduits, plus the manifold console (C1, C3, C5).
	for k in 4:
		var z: float = (CONDUIT_Z[k] + CONDUIT_Z[k + 1]) * 0.5
		var c := ScifiKit.place(self, "sf_coupler", Vector3(-19.55, 1.05, z), 90.0, 0.9, "")
		_couplers.append(c)
		for idx: int in COUPLER_LINKS[k]:
			_pipe(Vector3(-19.4, 1.05, z), Vector3(-19.4, 1.05, CONDUIT_Z[idx]), 0.07)
		_make_coupler_interact(c, k, Vector3(0.0, 0.0, 0.0))
		ScifiKit.sign(self, "K%d" % (k + 1), Vector3(-19.6, 1.75, z), 90.0, 0.06, Color(1.0, 0.75, 0.45))
	var pedestal := ScifiKit.block(self, Vector3(0.9, 0.9, 0.9), Vector3(-16.0, 0.45, 24.0), &"trim")
	pedestal.name = "ManifoldPedestal"
	var k5 := ScifiKit.place(self, "sf_coupler", Vector3(-16.0, 1.3, 24.0), 90.0, 1.0, "")
	_couplers.append(k5)
	_make_coupler_interact(k5, 4, Vector3(0, 0, 0))
	ScifiKit.sign(self, "K5", Vector3(-16.0, 2.1, 24.0), 90.0, 0.07, Color(1.0, 0.75, 0.45))
	for idx: int in COUPLER_LINKS[4]:
		var top := Vector3(-19.2, 4.0, CONDUIT_Z[idx])
		_pipe(Vector3(-16.0, 1.6, 24.0), Vector3(-16.0, 4.0, 24.0), 0.08)
		_pipe(Vector3(-16.0, 4.0, 24.0), Vector3(-16.0, 4.0, top.z), 0.08)
		_pipe(Vector3(-16.0, 4.0, top.z), top, 0.08)
	var note := ScifiParts.HoloNote.new()
	note.text = "CONDUIT COUPLERS\nEach coupler joins the conduits its pipes touch, and flips them.\nEnergize all five conduits to restore the main bus."
	add_child(note)
	note.position = Vector3(-11.5, 0, 20.0)
	var lever := ScifiKit.place(self, "sf_lever", Vector3(-9.2, 0, 29.6), -90.0)
	var reset := Interactable.new()
	reset.prompt = "Reset the couplers"
	reset.radius = 1.6
	reset.focus_offset = Vector3(0, 0.7, 0)
	lever.add_child(reset)
	reset.interacted.connect(func(_p: Node) -> void:
		if step_done(STEP_SET, &"couplers"):
			return
		_conduits.assign(COUPLER_START.duplicate())
		_save_couplers()
		_update_conduits()
		_swing_lever(lever)
		Audio.play_sfx(&"relay_toggle", -4.0))
	ScifiKit.place(self, "sf_rack", Vector3(-9.2, 0, 18.0), 0.0)
	ScifiKit.place(self, "sf_rack", Vector3(-10.1, 0, 18.0), 0.0)


## Holographic map of the station turning over a projector table (the facility's layout).
func _build_station_map(at: Vector3) -> void:
	ScifiKit.place(self, "sf_projector", at, 0.0)
	var root := Node3D.new()
	add_child(root)
	root.position = at + Vector3(0, 1.7, 0)
	var holo := ScifiKit.holo_material(Color(0.4, 0.85, 1.0), 0.18, 1.3)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.05
	ring.outer_radius = 1.2
	ring.rings = 48
	var hub := CylinderMesh.new()
	hub.top_radius = 0.28
	hub.bottom_radius = 0.28
	hub.height = 0.9
	var parts := [[ring, Vector3.ZERO, Vector3.ZERO], [hub, Vector3.ZERO, Vector3.ZERO]]
	for spoke: Array in [[Vector3(0.6, 0, 0), Vector3(1.0, 0.06, 0.08)], [Vector3(-0.6, 0, 0), Vector3(1.0, 0.06, 0.08)],
			[Vector3(0, 0, 0.6), Vector3(0.08, 0.06, 1.0)], [Vector3(0, 0, -0.6), Vector3(0.08, 0.06, 1.0)]]:
		var box := BoxMesh.new()
		box.size = spoke[1]
		parts.append([box, spoke[0], Vector3.ZERO])
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = holo
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.position = part[1]
	var blink := MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	blink.mesh = dot
	blink.material_override = ScifiKit.holo_material(Color(1.0, 0.35, 0.25), 0.9, 3.0)
	root.add_child(blink)
	blink.position = Vector3(1.12, 0, 0)
	root.rotation_degrees.x = 18.0
	var spin := create_tween().set_loops()
	spin.tween_property(root, "rotation:y", TAU, 20.0).from(0.0)
	var here := ScifiKit.sign(self, "YOU ARE HERE", at + Vector3(0, 2.75, 0), 0.0, 0.05, Color(1.0, 0.5, 0.4))
	here.billboard = BaseMaterial3D.BILLBOARD_ENABLED


## A run of three parallel pipes along the ceiling.
func _ceiling_pipes(a: Vector3, b: Vector3) -> void:
	var side := (b - a).normalized().cross(Vector3.UP)
	for i in 3:
		var o := side * (i - 1) * 0.28 + Vector3(0, -0.05 * (i % 2), 0)
		_pipe(a + o, b + o, 0.08 if i != 1 else 0.11)


func _make_coupler_interact(node: Node3D, index: int, offset: Vector3) -> void:
	var it := Interactable.new()
	it.prompt = "Turn coupler K%d" % (index + 1)
	it.radius = 1.6
	it.focus_offset = offset
	node.add_child(it)
	it.position = Vector3(0, 0, 0.3)
	it.interacted.connect(func(_p: Node) -> void: _press_coupler(index))


func _press_coupler(index: int) -> void:
	if step_done(STEP_SET, &"couplers"):
		return
	for idx: int in COUPLER_LINKS[index]:
		_conduits[idx] = not _conduits[idx]
	var wheel := _couplers[index].get_node_or_null("coupler_wheel") as Node3D
	if wheel:
		var tween := create_tween()
		tween.tween_property(wheel, "rotation:y", wheel.rotation.y + PI * 0.5, 0.45).set_trans(Tween.TRANS_BACK)
	Audio.play_sfx_3d(&"relay_toggle", _couplers[index].global_position, -2.0)
	_save_couplers()
	_update_conduits()
	if not _conduits.has(false):
		complete_step(STEP_SET, &"couplers", "Main bus energized")
		Audio.play_sfx(&"power_restore", -4.0)
		_set_power_stage(1, true)
		show_effect(_door_a.global_position + Vector3(0, 1.5, 0))


func _save_couplers() -> void:
	GameState.set_puzzle_state(&"lab_couplers", _conduits.duplicate())


func _update_conduits() -> void:
	for i in 5:
		var on := _conduits[i]
		_conduit_fx[i].visible = on
		(_conduit_lamps[i] as MeshInstance3D).material_override = _lamp_on if on else _lamp_off


func _swing_lever(lever: Node3D) -> void:
	var handle := lever.get_node_or_null("lever_handle") as Node3D
	if handle == null:
		return
	var tween := create_tween()
	tween.tween_property(handle, "rotation:x", deg_to_rad(30), 0.2)
	tween.tween_property(handle, "rotation:x", deg_to_rad(-30), 0.4).set_delay(0.3)


func _pipe(a: Vector3, b: Vector3, radius: float) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = len
	cyl.radial_segments = 12
	mi.mesh = cyl
	mi.material_override = ScifiKit.material("sf_metal")
	add_child(mi)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)


# --- Optics lab: laser and mirror carts ----------------------------------------------------

func _build_optics_lab() -> void:
	for p in [Vector3(-8, 6.0, -8), Vector3(0, 6.0, -8), Vector3(8, 6.0, -8), Vector3(-6, 6.0, 3), Vector3(6, 6.0, 3)]:
		_light(2, p, 1.5, 11.0, p.x == 0.0)
	ScifiKit.place(self, "sf_emitter", Vector3(-13.3, 0, -10.0), 90.0)
	_laser = ScifiParts.Laser.new()
	_laser.direction = Vector3.RIGHT
	add_child(_laser)
	_laser.position = Vector3(-12.9, 1.0, -10.0)
	_receiver = ScifiKit.place(self, "sf_receiver", Vector3(8.0, 0, -13.3), 0.0)
	var rbody := StaticBody3D.new()
	rbody.collision_layer = ScifiParts.LASER_LAYER
	rbody.collision_mask = 0
	rbody.set_meta("receiver", _receiver)
	_receiver.add_child(rbody)
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(0.6, 0.6, 0.4)
	rcs.shape = rbox
	rcs.position = Vector3(0, 1.0, 0.1)
	rbody.add_child(rcs)
	ScifiKit.set_glow(_receiver, Color(0.2, 0.4, 0.5), 0.6)
	_laser.receiver_changed.connect(_on_receiver)
	# Beam blockers (the puzzle's constraints): a glass chamber and two server racks.
	ScifiKit.place(self, "sf_chamber", Vector3(-8.0, 0, -5.0), 0.0)
	ScifiKit.place(self, "sf_rack", Vector3(-4.0, 0, -4.0), 20.0)
	ScifiKit.place(self, "sf_rack", Vector3(0.0, 0, -2.0), -15.0)
	# Carts: A on row z=-10, C on row z=2 (mirror "S"), B on column x=8 (mirror "N").
	_make_cart(&"cart_a", "S", [Vector3(-8, 0, -10), Vector3(-4, 0, -10), Vector3(0, 0, -10), Vector3(4, 0, -10)], 0)
	_make_cart(&"cart_c", "S", [Vector3(-8, 0, 2), Vector3(-4, 0, 2), Vector3(0, 0, 2), Vector3(4, 0, 2)], 0)
	_make_cart(&"cart_b", "N", [Vector3(8, 0, -6), Vector3(8, 0, -2), Vector3(8, 0, 2)], 0)
	var note := ScifiParts.HoloNote.new()
	note.text = "OPTICS BENCH\nPush the mirror carts along their rails.\nThe beam must reach the receiver to open the control-room door."
	add_child(note)
	note.position = Vector3(-10.5, 0, 5.5)
	# Reward chamber: opens when the laser is routed.
	ScifiKit.place(self, "sf_chamber", Vector3(11.0, 0, 5.5), 0.0, 1.0, "")
	_reward_glass = Node3D.new()
	add_child(_reward_glass)
	var glass_body := StaticBody3D.new()
	_reward_glass.add_child(glass_body)
	var gcs := CollisionShape3D.new()
	var gcyl := CylinderShape3D.new()
	gcyl.radius = 0.8
	gcyl.height = 2.5
	gcs.shape = gcyl
	gcs.position = Vector3(11.0, 1.25, 5.5)
	glass_body.add_child(gcs)
	_door_b = ScifiParts.Door.new()
	_door_b.locked_text = "Sealed. Route the laser to the receiver."
	add_child(_door_b)
	_door_b.position = Vector3(-11.0, 0, -14.0)
	var arm := ScifiKit.place(self, "sf_arm", Vector3(11.5, 0, -11.0), -120.0)
	_arms.append(arm)
	ScifiKit.place(self, "sf_table", Vector3(-11.0, 0, -1.0), 90.0)
	ScifiKit.place(self, "sf_table", Vector3(11.0, 0, -7.0), 0.0)
	for x in [-11.5, -7.5, -3.5, 4.5]:
		ScifiKit.place(self, "sf_shelf", Vector3(x, 0, 7.4), 180.0)
	ScifiKit.place(self, "sf_rack", Vector3(13.4, 0, 6.0), -90.0)
	ScifiKit.place(self, "sf_rack", Vector3(13.4, 0, 4.0), -90.0)
	ScifiKit.place(self, "sf_chamber", Vector3(-12.5, 0, -12.5), 0.0)
	ScifiKit.place(self, "sf_crate", Vector3(4.0, 0, -13.0), 10.0)
	_ceiling_pipes(Vector3(-13.5, 5.6, -13), Vector3(13.5, 5.6, -13))
	_ceiling_pipes(Vector3(-13.5, 5.6, 7.4), Vector3(13.5, 5.6, 7.4))
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(5.0, 2.4)
	screen.mesh = quad
	screen.material_override = ScifiKit.material("sf_screen")
	add_child(screen)
	screen.position = Vector3(0, 3.6, 7.78)
	screen.rotation_degrees.y = 180.0
	_screens.append(screen)
	_screens.append(ScifiKit.place(self, "sf_console", Vector3(-12.6, 0, 3.0), 90.0))
	# The loose vent and the crates that reach it.
	ScifiKit.place(self, "sf_crate", Vector3(13.33, 0, -2.0), 0.0)
	ScifiKit.place(self, "sf_crate", Vector3(13.33, 0.9, -2.0), 0.0)
	# A single crate flush against the stack: two easy 0.9 m hops up to the vent.
	ScifiKit.place(self, "sf_crate", Vector3(13.33, 0, -1.08), 0.0)
	_vent = ScifiKit.place(self, "sf_grate", Vector3(13.82, 2.25, -2.0), -90.0, 0.95, "")
	_vent_body = StaticBody3D.new()
	add_child(_vent_body)
	var vcs := CollisionShape3D.new()
	var vbox := BoxShape3D.new()
	vbox.size = Vector3(0.3, 1.3, 1.3)
	vcs.shape = vbox
	vcs.position = Vector3(13.85, 2.85, -2.0)
	_vent_body.add_child(vcs)
	var scan_target := ScanTarget.new()
	scan_target.on_scan = _on_vent_scanned
	add_child(scan_target)
	scan_target.position = Vector3(13.6, 2.7, -2.0)
	_vent_interactable = Interactable.new()
	_vent_interactable.prompt = "Pry the loose vent open"
	_vent_interactable.radius = 1.8
	_vent_interactable.focus_offset = Vector3(0, 0, 0)
	_vent_interactable.enabled = false
	add_child(_vent_interactable)
	_vent_interactable.position = Vector3(13.5, 2.7, -2.0)
	_vent_interactable.interacted.connect(func(_p: Node) -> void: _open_vent(false))


func _make_cart(id: StringName, kind: String, slots: Array, start: int) -> void:
	var body := AnimatableBody3D.new()
	body.name = String(id)
	body.sync_to_physics = true
	add_child(body)
	var prop := ScifiKit.instance("sf_cart")
	body.add_child(prop)
	var mirror := prop.get_node_or_null("cart_mirror") as Node3D
	if mirror:
		mirror.rotation = Vector3(0, deg_to_rad(-45.0 if kind == "S" else 45.0), 0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.78, 0.36, 0.72)
	cs.shape = box
	cs.position = Vector3(0, 0.18, 0)
	body.add_child(cs)
	var mbody := StaticBody3D.new()
	mbody.collision_layer = ScifiParts.LASER_LAYER
	mbody.collision_mask = 0
	mbody.set_meta("mirror", kind)
	body.add_child(mbody)
	mbody.position = Vector3(0, 1.0, 0)
	var mcs := CollisionShape3D.new()
	var mbox := BoxShape3D.new()
	mbox.size = Vector3(0.5, 0.5, 0.5)
	mcs.shape = mbox
	mbody.add_child(mcs)
	for s: Vector3 in slots:
		var marker := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.14
		cyl.bottom_radius = 0.14
		cyl.height = 0.03
		marker.mesh = cyl
		marker.material_override = ScifiKit.material("sf_glow_orange")
		add_child(marker)
		marker.position = s + Vector3(0, 0.02, 0)
	# Rail segments (2 m each) from 1 m before the first slot to 1 m past the last.
	var a: Vector3 = slots[0]
	var b: Vector3 = slots[slots.size() - 1]
	var axis := (b - a).normalized()
	var along_x := absf(axis.x) > absf(axis.z)
	var count := int(ceil((a.distance_to(b) + 2.0) / 2.0))
	for i in count:
		ScifiKit.place(self, "sf_rail", a - axis + axis * (i * 2.0 + 1.0), 0.0 if along_x else 90.0, 1.0, "")
	var cart := {"id": id, "body": body, "slots": slots, "index": start, "dir": 1}
	var saved: Variant = GameState.get_puzzle_state(StringName("lab_%s" % id))
	if saved != null:
		cart["index"] = clampi(int(saved), 0, slots.size() - 1)
	body.position = slots[cart["index"]]
	var it := Interactable.new()
	it.prompt = "Push the mirror cart"
	it.radius = 1.6
	it.focus_offset = Vector3(0, 0.6, 0)
	body.add_child(it)
	it.interacted.connect(func(_p: Node) -> void: _push_cart(cart))
	_carts.append(cart)


func _push_cart(cart: Dictionary) -> void:
	var slots: Array = cart["slots"]
	var i: int = cart["index"]
	var d: int = cart["dir"]
	if i + d < 0 or i + d >= slots.size():
		d = -d
	i += d
	cart["index"] = i
	cart["dir"] = d
	GameState.set_puzzle_state(StringName("lab_%s" % cart["id"]), i)
	var body: AnimatableBody3D = cart["body"]
	Audio.play_sfx_3d(&"cart_move", body.global_position, -2.0)
	var tween := create_tween()
	tween.tween_property(body, "position", slots[i], 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_receiver(receiver: Node, lit: bool) -> void:
	if receiver != _receiver:
		return
	ScifiKit.set_glow(_receiver, Color(0.3, 0.95, 1.0) if lit else Color(0.2, 0.4, 0.5), 4.0 if lit else 0.6)
	if lit and not step_done(STEP_SET, &"laser"):
		Audio.play_sfx(&"laser_on", -2.0)
		complete_step(STEP_SET, &"laser", "Laser routed. The control-room door unlocks.")
		_set_power_stage(2, true)
		show_effect(_door_b.global_position + Vector3(0, 1.5, 0))


func _on_vent_scanned() -> void:
	if GameState.is_revealed(&"lab_vent"):
		return
	ScanHighlight.flash_node(_vent, Color(1.0, 0.85, 0.5))
	_vent_interactable.enabled = true
	Events.toast("That vent is loose.", "discovery")
	Audio.play_sfx(&"reveal", -4.0)


func _open_vent(instant: bool) -> void:
	GameState.mark_revealed(&"lab_vent")
	_vent_interactable.enabled = false
	_vent_body.queue_free()
	if instant:
		_vent.visible = false
		return
	Audio.play_sfx_3d(&"gate_open", _vent.global_position, -2.0)
	var tween := create_tween()
	tween.tween_property(_vent, "position", _vent.position + Vector3(-1.0, -2.2, 0.3), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_vent, "rotation:z", 1.4, 0.6)
	SaveSystem.request_save()


# --- Hidden laboratory ---------------------------------------------------------------------

func _build_hidden_lab() -> void:
	var chamber := ScifiKit.place(self, "sf_chamber", Vector3(22.0, 2.2, -5.0), 0.0)
	var glass_mat := (ScifiKit.material("sf_glass") as ShaderMaterial).duplicate() as ShaderMaterial
	glass_mat.set_shader_parameter("crack_amount", 0.8)
	glass_mat.set_shader_parameter("inner_glow", Color(0.5, 1.0, 0.4))
	glass_mat.set_shader_parameter("inner_glow_energy", 0.6)
	for mi: MeshInstance3D in [chamber] + chamber.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(s) == ScifiKit.material("sf_glass"):
				mi.set_surface_override_material(s, glass_mat)
	var seed_mesh := SphereMesh.new()
	seed_mesh.radius = 0.28
	seed_mesh.height = 0.5
	var seed := ScifiKit.energy_mesh(self, seed_mesh, Vector3(22.0, 3.6, -5.0), Color(0.4, 1.0, 0.35), Color(0.95, 1.0, 0.7), 2.4)
	seed.name = "GardenSeed"
	var seed_light := ScifiKit.light(self, Vector3(22.0, 3.6, -5.0), Color(0.5, 1.0, 0.4), 1.6, 6.0)
	seed_light.shadow_enabled = true
	ScifiKit.light(self, Vector3(20.0, 5.0, 1.0), Color(0.7, 0.45, 1.0), 0.9, 7.0)
	ScifiKit.place(self, "sf_table", Vector3(24.5, 2.2, 0.5), 90.0)
	_screens.append(ScifiKit.place(self, "sf_console", Vector3(19.2, 2.2, 1.5), 90.0))
	ScifiKit.place(self, "sf_rack", Vector3(25.4, 2.2, -6.8), -90.0)
	var note := ScifiParts.HoloNote.new()
	note.text = "EXPERIMENT 7 / SEED RESONANCE\nThe garden seed answered the field.\nWe opened a door we could not close."
	note.color = Color(0.6, 1.0, 0.55)
	add_child(note)
	note.position = Vector3(22.0, 2.2, -2.0)
	ScifiKit.sign(self, "RESTRICTED", Vector3(18.25, 4.6, -2.0), 90.0, 0.09, Color(1.0, 0.4, 0.3))


# --- Control room: terminal restart --------------------------------------------------------

func _build_control_room() -> void:
	for p in [Vector3(-11, 7.0, -30), Vector3(-1, 7.0, -30), Vector3(-6, 7.0, -36)]:
		_light(3, p, 1.8, 13.0, p.z == -36.0)
	_light(3, Vector3(-20, 5.0, -32), 1.2, 8.0)
	var positions := [Vector3(-12.0, 0, -34.0), Vector3(-8.5, 0, -37.0), Vector3(-3.5, 0, -37.0), Vector3(0.0, 0, -34.0)]
	var center := Vector3(-6.0, 0, -30.0)
	for i in 4:
		var p: Vector3 = positions[i]
		var yaw := rad_to_deg(atan2(center.x - p.x, center.z - p.z))
		var t := ScifiKit.place(self, "sf_terminal", p, yaw)
		ScifiKit.sign(t, TERMINAL_NAMES[i], Vector3(0, 2.0, 0), 0.0, 0.085, Color(0.9, 0.95, 1.0))
		var it := Interactable.new()
		it.prompt = "Bring %s online" % TERMINAL_NAMES[i]
		it.radius = 1.7
		it.focus_offset = Vector3(0, 0.9, -0.3)
		t.add_child(it)
		var entry := {"name": TERMINAL_NAMES[i], "node": t, "on": false}
		it.interacted.connect(func(_p: Node) -> void: _press_terminal(entry))
		_terminals.append(entry)
		_screens.append(t)
	var log_console := ScifiKit.place(self, "sf_console", Vector3(-6.0, 0, -27.6), 180.0)
	_screens.append(log_console)
	var note := ScifiParts.HoloNote.new()
	note.projector = false
	note.height = 2.7
	note.size = 0.07
	note.text = "SHUTDOWN LOG  ·  EXPERIMENT 7\n03:12  CORE ............. offline\n03:13  FIELD ............ offline\n03:14  CONTAINMENT ...... offline\n03:15  COOLANT .......... offline\nTo restart, bring the systems up in the reverse of the shutdown order."
	add_child(note)
	note.position = Vector3(-6.0, 0, -27.6)
	ScifiKit.place(self, "sf_projector", Vector3(2.0, 0, -27.5), 0.0)
	_build_blueprint_hologram(Vector3(2.0, 0.2, -27.5))
	_arms.append(ScifiKit.place(self, "sf_arm", Vector3(2.5, 0, -38.0), 200.0))
	ScifiKit.place(self, "sf_rack", Vector3(-15.2, 0, -25.2), 90.0)
	ScifiKit.place(self, "sf_rack", Vector3(-15.2, 0, -26.2), 90.0)
	_door_c = ScifiParts.Door.new()
	_door_c.locked_text = "Freight lift. No main power."
	add_child(_door_c)
	_door_c.position = Vector3(-16.0, 0, -32.0)
	_door_c.rotation_degrees.y = 90.0
	var lift := ScifiKit.place(self, "sf_lift", Vector3(-20.0, 0, -32.0), 90.0)
	_freight = Interactable.new()
	_freight.prompt = "Ride the freight lift down"
	_freight.radius = 2.2
	_freight.focus_offset = Vector3(0, 1.1, 0)
	_freight.robot_action = &""
	lift.add_child(_freight)
	_freight.interacted.connect(func(_p: Node) -> void: facility.teleport_to_checkpoint(&"reactor_entry"))
	ScifiKit.sign(self, "FREIGHT  ·  SUBLEVEL", Vector3(-16.3, 3.8, -32.0), -90.0, 0.08)


func _build_blueprint_hologram(at: Vector3) -> void:
	var robot := (load("res://assets/characters/pink_robot/pink_robot.glb") as PackedScene).instantiate() as Node3D
	add_child(robot)
	robot.position = at + Vector3(0, 0.15, 0)
	robot.scale = Vector3.ONE * 1.6
	var holo := ScifiKit.holo_material(Color(0.45, 0.85, 1.0), 0.25, 1.5)
	for mi: MeshInstance3D in robot.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = holo
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spin := create_tween().set_loops()
	spin.tween_property(robot, "rotation:y", TAU, 12.0).from(0.0)


func _press_terminal(entry: Dictionary) -> void:
	if step_done(STEP_SET, &"terminals") or entry["on"]:
		return
	var expected: String = TERMINAL_ORDER[_sequence.size()]
	var node: Node3D = entry["node"]
	if entry["name"] == expected:
		entry["on"] = true
		_sequence.append(entry["name"])
		ScifiKit.set_glow(node.get_node("terminal_button"), Color(0.3, 1.0, 0.5), 3.0)
		Audio.play_sfx_3d(&"terminal_beep", node.global_position, -2.0, 1.0 + _sequence.size() * 0.08)
		if _sequence.size() == TERMINAL_ORDER.size():
			_finish_restart()
		return
	# Wrong order: everything trips.
	Audio.play_sfx(&"error_buzz", -2.0)
	node.add_child(FxFactory.burst(Color(1.0, 0.6, 0.3), 20, 3.0, 0.08))
	node.get_child(node.get_child_count() - 1).position = Vector3(0, 1.0, -0.3)
	Events.toast("Restart sequence failed. All systems tripped.", "locked")
	_sequence.clear()
	for t: Dictionary in _terminals:
		t["on"] = false
		ScifiKit.set_glow((t["node"] as Node3D).get_node("terminal_button"), Color(1.0, 0.22, 0.15), 2.4)
	_flicker.amount = 0.95
	get_tree().create_timer(1.5).timeout.connect(func() -> void: _flicker.amount = 0.6)


func _finish_restart() -> void:
	Audio.play_sfx(&"power_restore", 0.0)
	complete_step(STEP_SET, &"terminals", "Main power restored")
	_set_power_stage(3, true)
	show_effect(Vector3(-6, 3, -33), 3.2)


# --- Power stages ---------------------------------------------------------------------------

func _set_power_stage(stage: int, animate: bool) -> void:
	_power_stage = maxi(_power_stage, stage)
	# Where main power is back, the white light replaces the flickering emergency red.
	for spot: Dictionary in _light_spots:
		if int(spot["stage"]) > _power_stage:
			continue
		var main: Light3D = spot["main"]
		(spot["red"] as Light3D).visible = false
		ScifiKit.set_glow(spot["lamp"], Color(1.0, 0.96, 0.9), 3.2)
		if not main.visible:
			main.visible = true
			if animate:
				main.light_energy = 0.0
				create_tween().tween_property(main, "light_energy", float(main.get_meta("energy")), 1.2)
	for screen in _screens:
		ScifiKit.set_power(screen, 1.0 if _power_stage >= 3 else 0.25)
	for block in _arch:
		ScifiKit.set_power(block, 1.0 if _room_stage(block.position) <= _power_stage else 0.08)
	if _power_stage >= 1:
		_door_a.open(not animate)
	if _power_stage >= 2:
		_door_b.open(not animate)
		if is_instance_valid(_reward_glass) and not _reward_glass.is_queued_for_deletion():
			_reward_glass.queue_free()
	if _power_stage >= 3:
		_door_c.open(not animate)
		_freight.enabled = true


## Which power step lights a room: 1 arrival/breaker, 2 optics + hidden lab, 3 control.
func _room_stage(p: Vector3) -> int:
	if p.z > 8.0:
		return 1
	if p.z > -14.0 or p.x > 14.0:
		return 2
	return 3


func _restore() -> void:
	var saved: Variant = GameState.get_puzzle_state(&"lab_couplers")
	_conduits.assign(saved if saved is Array and (saved as Array).size() == 5 else COUPLER_START.duplicate())
	if step_done(STEP_SET, &"couplers"):
		_conduits.assign([true, true, true, true, true])
	_update_conduits()
	_freight.enabled = false
	var stage := 0
	if step_done(STEP_SET, &"couplers"):
		stage = 1
	if step_done(STEP_SET, &"laser"):
		stage = 2
	if step_done(STEP_SET, &"terminals"):
		stage = 3
		for t: Dictionary in _terminals:
			t["on"] = true
			ScifiKit.set_glow((t["node"] as Node3D).get_node("terminal_button"), Color(0.3, 1.0, 0.5), 3.0)
	_set_power_stage(stage, false)
	if GameState.is_revealed(&"lab_vent"):
		_open_vent(true)


## Small helper node in the "scannable" group that forwards the scan wave to a callback.
class ScanTarget extends Node3D:
	var on_scan: Callable

	func _ready() -> void:
		add_to_group(&"scannable")

	func on_scanned(_origin: Vector3) -> void:
		if on_scan.is_valid():
			on_scan.call()

	func is_hidden_unrevealed() -> bool:
		return not GameState.is_revealed(&"lab_vent")
