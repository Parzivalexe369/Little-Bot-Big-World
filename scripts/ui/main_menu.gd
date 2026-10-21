extends Node3D
## Main menu over a small living diorama: the robot hovers on a little dirt path in golden
## morning light, framed by giant flowers and grass, while the camera sways gently. The menu
## column sits on the left over a soft gradient and never covers the robot.

const ROBOT_POS := Vector3(0.6, 0.0, 0.0)
## Camera rest pose and drift (keeps the robot a little right of center, clear of the menu).
const CAM_BASE := Vector3(1.0, 0.85, 3.4)
const CAM_TARGET := Vector3(0.05, 0.75, -1.0)
## Menu column grid (in the 1920x1080 base layout).
const MARGIN_X := 140.0

var _camera: Camera3D
var _robot: RobotVisual
var _time := 0.0
var _fidget_timer := 7.0
var _look_timer := 3.0
var _buttons: VBoxContainer
var _continue: Button
var _new_game: Button
var _settings: SettingsPanel
var _confirm: PanelContainer
var _menu_panel: Control
var _summary: Label
var _height_noise := FastNoiseLite.new()


func _ready() -> void:
	GameState.in_gameplay = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.has_feature("web"):
		_start_web()
	else:
		_build_diorama()
		_build_ui()
	Audio.stop_all_ambient(1.0)
	Audio.play_music(&"menu", 2.5)
	Audio.set_ambient(&"meadow_base", 0.6, 3.0, -10.0)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"foliage_near_fade", 1.0)


func _process(delta: float) -> void:
	_time += delta
	# Slow, breathing camera drift; the robot always stays near the same spot on screen.
	var drift := Vector3(sin(_time * 0.11) * 0.35, sin(_time * 0.17) * 0.05, cos(_time * 0.11) * 0.12)
	var look := CAM_TARGET + Vector3(sin(_time * 0.07) * 0.08, 0.0, 0.0)
	_camera.look_at_from_position(CAM_BASE + drift, look)
	# Idle life: an occasional fidget, and now and then a curious look at the camera.
	_fidget_timer -= delta
	if _fidget_timer <= 0.0:
		_fidget_timer = randf_range(8.0, 13.0)
		_robot.play_action(&"Dodge_Left" if randf() < 0.5 else &"Dodge_Right", 0.6)
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(3.5, 7.0)
		_robot.look_at_point(_camera.global_position if randf() < 0.5 else null)


# --- Diorama ------------------------------------------------------------------------

## Browsers: the game's first frame runs in one go with the engine's start-up (about 11 s of
## its own on a first visit), and Chrome calls a page unresponsive after 15 s without a
## break. So the first frame draws only the menu; the diorama is built in the next one and
## its shaders compile a material per frame (ShaderWarmup) behind a plain backdrop that
## fades out once everything is drawn.
func _start_web() -> void:
	set_process(false)
	get_viewport().disable_3d = true
	var cover := _build_cover()
	_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	_build_diorama()
	set_process(true)
	await _reveal_diorama(cover)


func _build_cover() -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var cover := ColorRect.new()
	cover.color = Color(0.07, 0.08, 0.1)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cover)
	var note := Label.new()
	note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	note.offset_bottom = -90.0
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 22)
	note.modulate = Color(1, 1, 1, 0.75)
	note.visible = false
	note.name = "Note"
	cover.add_child(note)
	return cover


func _reveal_diorama(cover: ColorRect) -> void:
	var note := cover.get_node("Note") as Label
	var start := Time.get_ticks_msec()
	await ShaderWarmup.reveal_gradually(self, false, func(done: int, total: int) -> void:
		# Only a slow (first) visit shows it; with cached shaders this is over in a moment.
		if Time.get_ticks_msec() - start > 1500:
			note.visible = true
			note.text = "Preparing graphics...  %d / %d\nThe first visit takes a few minutes. Later visits start quickly." % [done, total])
	note.visible = false
	var tween := create_tween()
	tween.tween_property(cover, "color:a", 0.0, 0.8)
	tween.tween_callback(cover.get_parent().queue_free)


func _build_diorama() -> void:
	var env := WorldEnvironment.new()
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var atmo := AtmosphereController.new()
	add_child(atmo)
	atmo.setup(env, sun)
	# Golden morning: a low, warm side light with long shadows, a soft warm haze, gentle
	# light shafts and restrained saturation.
	sun.rotation_degrees = Vector3(-30, 62, 0)
	atmo.set_restoration(&"meadow", 1.0)
	atmo.set_override({
		"sun": Color(1.0, 0.8, 0.56), "sun_energy": 2.3, "ambient": Color(0.62, 0.68, 0.76),
		"ambient_energy": 0.75, "fog": Color(0.95, 0.88, 0.74), "fog_density": 0.0045,
		"sky_top": Color(0.42, 0.6, 0.86), "sky_horizon": Color(1.0, 0.88, 0.72),
		"glow": Color(1.0, 0.8, 0.55), "clouds": 0.32, "saturation": 1.06,
		"vol_fog": 0.005, "shafts": 1.6,
	}, 1.0)
	RenderingServer.global_shader_parameter_set(&"restore_levels", Vector4(1, 1, 1, 1))
	RenderingServer.global_shader_parameter_set(&"player_position", Vector3(0, -100, 0))
	var focus := Node3D.new()
	add_child(focus)
	atmo.focus = focus
	atmo.snap()

	_height_noise.seed = 11
	_height_noise.frequency = 0.07
	_build_ground()

	_robot = RobotVisual.new()
	add_child(_robot)
	_robot.position = ROBOT_POS + Vector3(0, _height_at(ROBOT_POS.x, ROBOT_POS.z), 0)
	_robot.rotation.y = deg_to_rad(198)
	_robot.set_locomotion(0.0, 0.0)
	_robot.enable_character_lighting()

	_build_grass()
	_build_garden()
	add_child(FxFactory.ambient_motes(Color(1.0, 0.92, 0.7, 0.8), 70, Vector3(6, 2.2, 6), 0.05, 0.06))
	# Plants in front of the camera normally dissolve so they never hide the robot during
	# play; on this still shot that dither reads as noise, so it is off while the menu is up.
	RenderingServer.global_shader_parameter_set(&"foliage_near_fade", 0.0)

	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.far = 400.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Subtle depth of field: the robot is crisp, the far garden and the nearest blades soften.
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 6.0
	cam_attr.dof_blur_far_transition = 7.0
	cam_attr.dof_blur_near_enabled = true
	cam_attr.dof_blur_near_distance = 1.7
	cam_attr.dof_blur_near_transition = 1.0
	cam_attr.dof_blur_amount = 0.07
	_camera.attributes = cam_attr
	add_child(_camera)
	_camera.make_current()
	_camera.look_at_from_position(CAM_BASE, CAM_TARGET)


## The little dirt path the robot waits on, winding back into the garden.
func _path_weight(x: float, z: float) -> float:
	var center := ROBOT_POS.x + sin((z + 2.0) * 0.16) * 1.6 - z * 0.05
	var across := 1.0 - smoothstep(0.45, 1.15, absf(x - center))
	return across * (1.0 - smoothstep(-0.2, 1.4, z))


## Gentle mounds away from the robot; flat where it stands.
func _height_at(x: float, z: float) -> float:
	var d := Vector2(x - ROBOT_POS.x, z - ROBOT_POS.z).length()
	return _height_noise.get_noise_2d(x, z) * 0.35 * smoothstep(2.0, 9.0, d) - _path_weight(x, z) * 0.04


## Ground built from the game's own terrain material (photoscanned layers, grass cover).
func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 32.0
	var cell := 0.5
	var n := int(half * 2.0 / cell)
	for iz in n:
		for ix in n:
			var x0 := -half + ix * cell
			var z0 := -half + iz * cell - 10.0
			var quad := [Vector2(x0, z0), Vector2(x0 + cell, z0), Vector2(x0 + cell, z0 + cell), Vector2(x0, z0 + cell)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = quad[idx]
				var h := _height_at(p.x, p.y)
				var nx := _height_at(p.x - 0.25, p.y) - _height_at(p.x + 0.25, p.y)
				var nz := _height_at(p.x, p.y - 0.25) - _height_at(p.x, p.y + 0.25)
				st.set_normal(Vector3(nx, 0.5, nz).normalized())
				st.set_color(Color(_path_weight(p.x, p.y), 0.0, 0.0, 0.0))
				st.set_uv2(Vector2.ZERO)
				st.add_vertex(Vector3(p.x, h, p.y))
	var mat := ShaderMaterial.new()
	mat.shader = WorldTerrain.TERRAIN_SHADER
	mat.set_shader_parameter("noise_tex", WorldTerrain.NOISE_TEX)
	mat.set_shader_parameter("layer_albedo", WorldTerrain.LAYER_ALBEDO)
	mat.set_shader_parameter("layer_normal", WorldTerrain.LAYER_NORMAL)
	mat.set_shader_parameter("layer_arm", WorldTerrain.LAYER_ARM)
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = mat
	add_child(ground)


func _build_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cam_xz := Vector2(CAM_BASE.x, CAM_BASE.z)
	var robot_xz := Vector2(ROBOT_POS.x, ROBOT_POS.z)
	var lists := {"grass_a": [], "grass_b": [], "grass_tall": []}
	for i in 1500:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 22.0 + 0.8
		var p := robot_xz + Vector2(cos(a), sin(a)) * r + Vector2(0, -4.0)
		# Keep the path, the robot's spot and the camera's line of sight clear.
		if _path_weight(p.x, p.y) > 0.3 or p.distance_to(robot_xz) < 0.8 or p.distance_to(cam_xz) < 1.6:
			continue
		# Thin a view corridor down the path so the garden beyond shows through.
		if p.y < -0.8 and _path_weight(p.x, p.y + 0.0) > 0.0 and rng.randf() < 0.8:
			continue
		var corridor := absf(p.x - (ROBOT_POS.x + sin((p.y + 2.0) * 0.16) * 1.6 - p.y * 0.05))
		if p.y < -1.0 and corridor < 2.6 and rng.randf() < 0.7:
			continue
		if Geometry2D.get_closest_point_to_segment(p, robot_xz, cam_xz).distance_to(p) < 0.85 and p.y > robot_xz.y - 0.3:
			continue
		var kind := "grass_tall" if r > 7.0 and rng.randf() < 0.18 else ("grass_a" if rng.randf() < 0.55 else "grass_b")
		var s := rng.randf_range(0.7, 1.3) * (rng.randf_range(1.2, 2.2) if kind == "grass_tall" else 1.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		(lists[kind] as Array).append(Transform3D(basis, Vector3(p.x, _height_at(p.x, p.y) - 0.04, p.y)))
	for kind: String in lists:
		var xforms: Array = lists[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropLibrary.mesh(kind)
		mm.instance_count = xforms.size()
		for j in xforms.size():
			mm.set_instance_transform(j, xforms[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = PropLibrary.material("grass_tall" if kind == "grass_tall" else "grass")
		add_child(mmi)


## Hand-placed garden: giant flowers on the right and behind, a few on the left behind the menu.
func _build_garden() -> void:
	var placements := [
		# Right side of the frame
		["daisy_a", Vector3(2.7, 0, -1.9), 20.0, 0.95], ["daisy_pink", Vector3(3.5, 0, -0.3), 140.0, 0.8],
		["tulip_a", Vector3(2.2, 0, 0.9), 60.0, 0.7], ["sunflower", Vector3(4.6, 0, -5.0), 200.0, 0.9],
		["dandelion_a", Vector3(6.0, 0, -3.0), 10.0, 0.85], ["bluebell_a", Vector3(1.7, 0, -2.6), 300.0, 0.9],
		["daisy_b", Vector3(5.2, 0, -8.5), 90.0, 1.0], ["tulip_a", Vector3(3.2, 0, -7.0), 250.0, 0.9],
		# Behind the robot, far and soft
		["daisy_a", Vector3(-0.6, 0, -9.0), 30.0, 1.1], ["sunflower", Vector3(1.4, 0, -14.0), 120.0, 1.1],
		["daisy_pink", Vector3(-3.0, 0, -12.0), 70.0, 1.0], ["dandelion_a", Vector3(2.6, 0, -11.0), 0.0, 1.0],
		# Left, behind the menu (darkened by the gradient, adds depth)
		["daisy_b", Vector3(-2.6, 0, -3.2), 210.0, 0.9], ["tulip_a", Vector3(-4.2, 0, -1.0), 30.0, 0.8],
		["bluebell_a", Vector3(-1.8, 0, -5.4), 100.0, 0.9],
	]
	for item: Array in placements:
		var at: Vector3 = item[1]
		at.y = _height_at(at.x, at.z)
		PropLibrary.place(self, item[0], at, item[2], item[3], false)
	PropLibrary.place(self, "mushroom_cluster", Vector3(1.85, _height_at(1.85, -0.9), -0.9), 20.0, 0.75, false)
	PropLibrary.place(self, "mushroom_red_small", Vector3(4.2, _height_at(4.2, -2.6), -2.6), 160.0, 0.35, false)
	PropLibrary.place(self, "rock_moss_a", Vector3(3.8, _height_at(3.8, -6.0) - 0.4, -6.0), 40.0, 0.7, false)
	PropLibrary.place(self, "rock_a", Vector3(-1.2, _height_at(-1.2, -1.6) - 0.1, -1.6), 70.0, 0.35, false)
	PropLibrary.place(self, "pebble_cluster", Vector3(0.1, _height_at(0.1, 0.5), 0.5), 0.0, 0.8, false)


# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := ShaderMaterial.new()
	grad.shader = preload("res://shaders/menu_vignette.gdshader")
	shade.material = grad
	root.add_child(shade)

	_menu_panel = VBoxContainer.new()
	_menu_panel.anchor_top = 0.5
	_menu_panel.anchor_bottom = 0.5
	_menu_panel.offset_left = MARGIN_X
	_menu_panel.offset_right = MARGIN_X + 640.0
	_menu_panel.offset_top = -330
	_menu_panel.offset_bottom = 360
	_menu_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	(_menu_panel as VBoxContainer).add_theme_constant_override("separation", 0)
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu_panel)

	var title := Label.new()
	title.text = "Little Bot,\nBig World"
	title.add_theme_font_override("font", MenuWidgets.font(MenuWidgets.FONT_TITLE, 600, 1))
	title.add_theme_font_size_override("font_size", 104)
	title.add_theme_constant_override("line_spacing", -22)
	title.add_theme_color_override("font_color", MenuWidgets.CREAM)
	title.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.03, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 14)
	_menu_panel.add_child(title)

	var tagline := Label.new()
	tagline.text = "A tiny robot. An enormous, sleeping garden."
	tagline.add_theme_font_override("font", MenuWidgets.font(MenuWidgets.FONT_TEXT, 500, 1))
	tagline.add_theme_font_size_override("font_size", 25)
	tagline.add_theme_color_override("font_color", Color(0.97, 0.94, 0.88, 0.78))
	tagline.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.3))
	tagline.add_theme_constant_override("shadow_offset_y", 1)
	tagline.add_theme_constant_override("shadow_outline_size", 6)
	_menu_panel.add_child(_indent(tagline, 6.0))

	var sprout := MenuWidgets.Sprout.new()
	_menu_panel.add_child(_spacer(26))
	_menu_panel.add_child(_indent(sprout, 6.0))
	_menu_panel.add_child(_spacer(30))

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_menu_panel.add_child(_buttons)
	var summary := SaveSystem.read_summary()
	_continue = MenuWidgets.PrimaryButton.new("Continue")
	_continue.pressed.connect(_on_continue)
	_continue.visible = not summary.is_empty()
	_buttons.add_child(_continue)
	_summary = Label.new()
	_summary.add_theme_font_override("font", MenuWidgets.font(MenuWidgets.FONT_TEXT, 500, 1))
	_summary.add_theme_font_size_override("font_size", 17)
	_summary.add_theme_color_override("font_color", Color(0.97, 0.94, 0.88, 0.66))
	_summary.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.02, 0.4))
	_summary.add_theme_constant_override("shadow_outline_size", 5)
	if not summary.is_empty():
		var minutes := int(float(summary["play_time"]) / 60.0)
		_summary.text = "%s  ·  %d energy  ·  %dh %02dm" % [GameData.area_name(summary["area"]), summary["energy"], minutes / 60, minutes % 60]
	_summary.visible = not summary.is_empty()
	var summary_box := _indent(_summary, 28.0)
	summary_box.visible = _summary.visible
	_buttons.add_child(summary_box)
	if _summary.visible:
		_buttons.add_child(_spacer(12))
	_new_game = _item("New Game", _on_new_game)
	_item("Settings", _on_settings)
	# A browser tab cannot be closed by the game (quitting would only freeze the page).
	if not OS.has_feature("web"):
		_item("Quit", func() -> void: get_tree().quit())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_settings = SettingsPanel.new()
	_settings.visible = false
	center.add_child(_settings)
	_settings.closed.connect(_show_menu)
	_confirm = _build_confirm()
	center.add_child(_confirm)
	UiSounds.wire(root)
	_intro([title, tagline, sprout, _buttons])
	(_continue if _continue.visible else _new_game).grab_focus.call_deferred()


func _item(text: String, action: Callable) -> Button:
	var b := MenuWidgets.MenuItem.new(text)
	b.pressed.connect(action)
	_buttons.add_child(b)
	return b


func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## Wraps a control with a left inset so text optically lines up with the title's stems.
func _indent(node: Control, left: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(left))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(node)
	return m


## Staggered fade-and-rise as the menu appears.
func _intro(nodes: Array) -> void:
	for i in nodes.size():
		var node: CanvasItem = nodes[i]
		node.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.35 + i * 0.14)
		tween.tween_property(node, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _build_confirm() -> PanelContainer:
	var panel := PanelContainer.new()
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.04, 0.06, 0.05, 0.86)
	card.set_corner_radius_all(18)
	card.border_color = Color(MenuWidgets.MINT.r, MenuWidgets.MINT.g, MenuWidgets.MINT.b, 0.5)
	card.border_width_top = 2
	card.content_margin_left = 36
	card.content_margin_right = 36
	card.content_margin_top = 28
	card.content_margin_bottom = 28
	card.shadow_color = Color(0, 0, 0, 0.3)
	card.shadow_size = 24
	panel.add_theme_stylebox_override("panel", card)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	var label := Label.new()
	label.text = "Start a new journey?\nYour current progress will be replaced."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", MenuWidgets.font(MenuWidgets.FONT_TEXT, 600))
	label.add_theme_font_size_override("font_size", 24)
	box.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var yes := MenuWidgets.PrimaryButton.new("Start new game")
	yes.custom_minimum_size = Vector2(280, 60)
	yes.pressed.connect(_start_new)
	row.add_child(yes)
	var no := MenuWidgets.MenuItem.new("Keep my progress")
	no.name = "Cancel"
	no.custom_minimum_size = Vector2(260, 60)
	no.pressed.connect(_show_menu)
	row.add_child(no)
	return panel


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _confirm.visible:
		_show_menu()


func _show_menu() -> void:
	_settings.visible = false
	_confirm.visible = false
	_menu_panel.visible = true
	(_continue if _continue.visible else _new_game).grab_focus.call_deferred()


func _on_continue() -> void:
	SceneRouter.continue_game()


func _on_new_game() -> void:
	if SaveSystem.has_save():
		_menu_panel.visible = false
		_confirm.visible = true
		(_confirm.find_child("Cancel", true, false) as Button).grab_focus.call_deferred()
	else:
		_start_new()


func _start_new() -> void:
	SceneRouter.start_new_game()


func _on_settings() -> void:
	_menu_panel.visible = false
	_settings.open()
