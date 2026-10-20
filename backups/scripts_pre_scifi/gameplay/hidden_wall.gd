class_name HiddenWall
extends Device
## A section of ruin wall with a faint glyph only the scanner can see. Pressing the glyph
## lowers the wall into the ground, opening a hidden chamber.

@export var wall_width_scale := 1.0

var _wall: Node3D
var _glyph: MeshInstance3D
var _body: StaticBody3D
var _revealed := false
var _open := false


func _build() -> void:
	_wall = PropLibrary.place(self, "wall_full", Vector3.ZERO, 0.0, 1.0, false)
	_wall.scale = Vector3(wall_width_scale, 1.0, 1.0)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	add_child(_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0 * wall_width_scale, 3.6, 0.9)
	shape.shape = box
	shape.position = Vector3(0, 1.8, 0)
	_body.add_child(shape)
	_glyph = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.3
	torus.rings = 24
	torus.ring_segments = 6
	_glyph.mesh = torus
	_glyph.material_override = PropLibrary.material("energy")
	_glyph.position = Vector3(0, 1.45, 0.48)
	_glyph.rotation.x = PI * 0.5
	_glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glyph)
	interactable = make_interactable("Press the glyph", 1.8, Vector3(0, 1.45, 0.6))
	interactable.interacted.connect(_on_used)
	add_to_group(&"scannable")


func _restore_state() -> void:
	_open = GameState.has_flag(flag_name("open"))
	_revealed = _open or GameState.is_revealed(device_id)
	interactable.enabled = _revealed and not _open
	_glyph.visible = _revealed and not _open
	_glyph.set_instance_shader_parameter(&"power", 1.0)
	if _open:
		_wall.position.y = -3.8
		_wall.visible = false
		_body.process_mode = Node.PROCESS_MODE_DISABLED


func is_hidden_unrevealed() -> bool:
	return not _revealed and not _open


func on_scanned(_origin: Vector3) -> void:
	if _open:
		return
	if not _revealed:
		_revealed = true
		GameState.mark_revealed(device_id)
		_glyph.visible = true
		_glyph.scale = Vector3.ONE * 0.01
		var tween := create_tween()
		tween.tween_property(_glyph, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK)
		interactable.enabled = true
		Audio.play_sfx_3d(&"reveal", _glyph.global_position, 0.0)
	ScanHighlight.flash(_glyph)


func _on_used(_player: Node) -> void:
	if _open:
		return
	_open = true
	interactable.enabled = false
	GameState.set_flag(flag_name("open"), true)
	Audio.play_sfx_3d(&"door_rumble", global_position + Vector3.UP, 0.0)
	var tween := create_tween()
	tween.tween_property(_glyph, "scale", Vector3.ONE * 0.01, 0.3)
	tween.tween_property(_wall, "position:y", -3.8, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_wall.visible = false
		_body.process_mode = Node.PROCESS_MODE_DISABLED)
	var dust := FxFactory.burst(Color(0.8, 0.75, 0.62), 40, 2.0, 0.4)
	dust.position = Vector3(0, 0.5, 0.6)
	add_child(dust)
	SaveSystem.request_save(1.0)
