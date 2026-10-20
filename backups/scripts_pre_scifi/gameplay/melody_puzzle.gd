class_name MelodyPuzzle
extends Device
## Three singing crystals and a melody stone. "Listen" at the stone plays a short tune:
## each crystal glows and sings in turn while the stone's glyphs light in the same order.
## Touch the crystals in that order to wake the linked resonator. Mistakes just reset softly.

## Crystal positions relative to this node (local XZ) and their glyph shapes / colors.
const CRYSTALS := [
	{"pos": Vector2(-4.5, -3.0), "glyph": "circle", "color": Color(0.45, 0.95, 1.0), "note": &"note_low"},
	{"pos": Vector2(0.0, -5.5), "glyph": "triangle", "color": Color(1.0, 0.75, 0.4), "note": &"note_mid"},
	{"pos": Vector2(4.5, -3.0), "glyph": "square", "color": Color(0.95, 0.55, 0.95), "note": &"note_high"},
]
const SEQUENCE := [1, 0, 2, 1]

@export var target_path: NodePath

var _crystals: Array[Node3D] = []
var _gems: Array[Node3D] = []
var _glyphs: Array[MeshInstance3D] = []
var _stone_glyphs: Array[MeshInstance3D] = []
var _progress := 0
var _playing := false
var _solved := false


func _build() -> void:
	var stone := PropLibrary.place(self, "melody_stone", Vector3.ZERO, 0.0, 1.0, true)
	stone.name = "Stone"
	interactable = make_interactable("Listen", 2.0, Vector3(0, 1.0, 0))
	interactable.robot_action = &""
	interactable.interacted.connect(func(_p: Node) -> void: play_melody())
	for i in SEQUENCE.size():
		var g := MeshInstance3D.new()
		g.mesh = _glyph_mesh(CRYSTALS[SEQUENCE[i]]["glyph"], 0.16)
		g.material_override = _glyph_material(CRYSTALS[SEQUENCE[i]]["color"])
		g.position = Vector3(-0.75 + i * 0.5, 1.5, 0.34)
		if CRYSTALS[SEQUENCE[i]]["glyph"] == "circle":
			g.rotation.x = PI * 0.5
		stone.add_child(g)
		g.set_instance_shader_parameter(&"power", 0.15)
		_stone_glyphs.append(g)
	for i in CRYSTALS.size():
		var info: Dictionary = CRYSTALS[i]
		var root := Node3D.new()
		root.name = "Crystal%d" % i
		add_child(root)
		var p: Vector2 = info["pos"]
		root.position = Vector3(p.x, 0, p.y)
		WorldTerrain.snap_node(root)
		var prop := PropLibrary.place(root, "singing_crystal", Vector3.ZERO, randf() * 360.0, 1.0, true)
		var gem := prop.get_node_or_null("singing_gem") as Node3D
		_crystals.append(root)
		_gems.append(gem)
		var glyph := MeshInstance3D.new()
		glyph.mesh = _glyph_mesh(info["glyph"], 0.35)
		glyph.material_override = _glyph_material(info["color"])
		glyph.position = Vector3(0, 3.6, 0)
		if info["glyph"] == "circle":
			glyph.rotation.x = PI * 0.5
		root.add_child(glyph)
		_glyphs.append(glyph)
		var it := make_interactable("Touch the crystal", 1.6, Vector3(0, 1.2, 0), root)
		it.interacted.connect(_on_crystal.bind(i))
	add_to_group(&"scannable")


func _restore_state() -> void:
	_solved = GameState.has_flag(flag_name("solved"))
	for i in _gems.size():
		_set_gem(i, 1.0 if _solved else 0.2)


func _glyph_mesh(kind: String, size: float) -> Mesh:
	match kind:
		"circle":
			var t := TorusMesh.new()
			t.inner_radius = size * 0.6
			t.outer_radius = size
			t.rings = 20
			t.ring_segments = 6
			return t
		"triangle":
			var p := PrismMesh.new()
			p.size = Vector3(size * 1.8, size * 1.6, size * 0.3)
			return p
		_:
			var b := BoxMesh.new()
			b.size = Vector3(size * 1.4, size * 1.4, size * 0.3)
			return b


func _glyph_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PropLibrary.DEVICE
	m.set_shader_parameter("glow_color", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter("glow_energy", 3.0)
	return m


func _set_gem(i: int, level: float) -> void:
	if _gems[i]:
		PropLibrary.set_power(_gems[i], level)
	_glyphs[i].set_instance_shader_parameter(&"power", level)


func on_scanned(_origin: Vector3) -> void:
	for g in _gems:
		ScanHighlight.flash_node(g)


func play_melody() -> void:
	if _playing:
		return
	_playing = true
	_progress = 0
	for i in SEQUENCE.size():
		var c: int = SEQUENCE[i]
		_stone_glyphs[i].set_instance_shader_parameter(&"power", 1.0)
		await _sing(c, 0.75)
		_stone_glyphs[i].set_instance_shader_parameter(&"power", 0.15 if not _solved else 1.0)
		await get_tree().create_timer(0.15).timeout
	_playing = false


func _sing(i: int, hold: float) -> void:
	Audio.play_sfx_3d(CRYSTALS[i]["note"], _crystals[i].global_position + Vector3.UP * 2.0, 0.0, 1.0, 0.0)
	_set_gem(i, 1.0)
	var gem := _gems[i]
	if gem:
		var tween := create_tween()
		tween.tween_property(gem, "scale", Vector3.ONE * 1.12, 0.12)
		tween.tween_property(gem, "scale", Vector3.ONE, 0.3)
	await get_tree().create_timer(hold).timeout
	if not _solved:
		_set_gem(i, 0.2)


func _on_crystal(_player: Node, i: int) -> void:
	if _playing:
		return
	_sing(i, 0.5)
	if _solved:
		return
	if SEQUENCE[_progress] == i:
		_stone_glyphs[_progress].set_instance_shader_parameter(&"power", 1.0)
		_progress += 1
		if _progress >= SEQUENCE.size():
			_solve()
	else:
		_progress = 0
		Audio.play_sfx(&"denied", -6.0)
		for g in _stone_glyphs:
			g.set_instance_shader_parameter(&"power", 0.15)
		Events.toast("The tune fades. Listen at the stone again.", "info")


func _solve() -> void:
	_solved = true
	GameState.set_flag(flag_name("solved"), true)
	await get_tree().create_timer(0.6).timeout
	Audio.play_sfx(&"puzzle_solved", 0.0)
	for i in _gems.size():
		_set_gem(i, 1.0)
	var target := get_node_or_null(target_path)
	if target and target.has_method("activate"):
		target.call("activate", true)
