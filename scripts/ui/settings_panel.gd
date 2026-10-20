class_name SettingsPanel
extends PanelContainer
## Settings screen shared by the main menu and the pause menu. Every control writes straight
## to the Settings autoload and is applied/saved immediately.

signal closed

var _tabs: TabContainer
var _first_focus: Control
var _resolution: OptionButton
var _res_list: Array[Vector2i] = []


func _ready() -> void:
	theme_type_variation = &"CardPanel"
	custom_minimum_size = Vector2(760, 560)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Settings"
	root.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_build_audio()
	_build_controls()
	_build_graphics()
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(close)
	root.add_child(back)
	UiSounds.wire(self)


func open() -> void:
	visible = true
	if _first_focus:
		_first_focus.grab_focus.call_deferred()


func close() -> void:
	visible = false
	Settings.commit()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


func _page(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 16)
	_tabs.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	return box


func _row(parent: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(260, 0)
	row.add_child(label)
	parent.add_child(row)
	return row


func _slider(parent: Control, label_text: String, value: float, min_v: float, max_v: float, step: float, on_change: Callable, fmt := "%d%%", scale := 100.0) -> HSlider:
	var row := _row(parent, label_text)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(260, 24)
	row.add_child(slider)
	var readout := Label.new()
	readout.theme_type_variation = &"HintLabel"
	readout.custom_minimum_size = Vector2(70, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = fmt % (value * scale)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = fmt % (v * scale)
		on_change.call(v))
	if _first_focus == null:
		_first_focus = slider
	return slider


func _toggle(parent: Control, label_text: String, value: bool, on_change: Callable) -> CheckButton:
	var row := _row(parent, label_text)
	var check := CheckButton.new()
	check.button_pressed = value
	check.toggled.connect(func(v: bool) -> void: on_change.call(v))
	row.add_child(check)
	return check


func _build_audio() -> void:
	var page := _page("Audio")
	_slider(page, "Master volume", Settings.master_volume, 0.0, 1.0, 0.01, func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply_audio())
	_slider(page, "Music", Settings.music_volume, 0.0, 1.0, 0.01, func(v: float) -> void:
		Settings.music_volume = v
		Settings.apply_audio())
	_slider(page, "Sound effects", Settings.sfx_volume, 0.0, 1.0, 0.01, func(v: float) -> void:
		Settings.sfx_volume = v
		Settings.apply_audio()
		Audio.play_ui(&"ui_move"))
	_slider(page, "Ambience", Settings.ambient_volume, 0.0, 1.0, 0.01, func(v: float) -> void:
		Settings.ambient_volume = v
		Settings.apply_audio())


func _build_controls() -> void:
	var page := _page("Controls")
	_slider(page, "Look sensitivity", Settings.mouse_sensitivity, 0.2, 3.0, 0.05, func(v: float) -> void:
		Settings.mouse_sensitivity = v, "%.2fx", 1.0)
	_toggle(page, "Invert horizontal look", Settings.invert_x, func(v: bool) -> void: Settings.invert_x = v)
	_toggle(page, "Invert vertical look", Settings.invert_y, func(v: bool) -> void: Settings.invert_y = v)
	_toggle(page, "Camera follows movement", Settings.camera_assist, func(v: bool) -> void: Settings.camera_assist = v)
	var t_row := _row(page, "Touch controls")
	var touch := OptionButton.new()
	for i in Settings.TOUCH_MODES.size():
		touch.add_item(Settings.TOUCH_MODES[i], i)
	touch.select(Settings.touch_controls)
	touch.item_selected.connect(func(i: int) -> void: Settings.touch_controls = i)
	t_row.add_child(touch)
	_slider(page, "Touch button size", Settings.touch_size, 0.7, 1.5, 0.05, func(v: float) -> void:
		Settings.touch_size = v)
	var help := Label.new()
	help.theme_type_variation = &"HintLabel"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Move  WASD / Left stick      Look  Mouse / Right stick      Hop  Space / A\nInteract  E / X      Scan  Q / Y      Boost  Shift / RT      Journal  J / Back      Pause  Esc / Start\nTouch: left stick to move (push past its rim to boost), drag to look, pinch to zoom, tap a prompt to use it."
	page.add_child(help)


func _build_graphics() -> void:
	var page := _page("Graphics")
	var q_row := _row(page, "Quality")
	var quality := OptionButton.new()
	for i in Settings.QUALITY_NAMES.size():
		quality.add_item(Settings.QUALITY_NAMES[i], i)
	quality.select(Settings.quality)
	quality.item_selected.connect(func(i: int) -> void:
		Settings.quality = i
		Settings.commit())
	q_row.add_child(quality)
	_toggle(page, "Fullscreen", Settings.fullscreen, func(v: bool) -> void:
		Settings.fullscreen = v
		Settings.apply_display()
		_resolution.disabled = v)
	var r_row := _row(page, "Window size")
	_resolution = OptionButton.new()
	_res_list = Settings.available_resolutions()
	for i in _res_list.size():
		_resolution.add_item("%d x %d" % [_res_list[i].x, _res_list[i].y], i)
		if _res_list[i] == Settings.resolution:
			_resolution.select(i)
	_resolution.disabled = Settings.fullscreen
	_resolution.item_selected.connect(func(i: int) -> void:
		Settings.resolution = _res_list[i]
		Settings.apply_display())
	r_row.add_child(_resolution)
	_slider(page, "Render scale", Settings.render_scale, 0.4 if OS.has_feature("web") else 0.5, 1.0, 0.05, func(v: float) -> void:
		Settings.render_scale = v
		Settings.apply_display())
	_toggle(page, "V-Sync", Settings.vsync, func(v: bool) -> void:
		Settings.vsync = v
		Settings.apply_display())
	_slider(page, "Field of view", Settings.fov, 55.0, 95.0, 1.0, func(v: float) -> void:
		Settings.fov = v
		Settings.changed.emit(), "%d°", 1.0)
	var note := Label.new()
	note.theme_type_variation = &"HintLabel"
	note.text = "Quality affects shadows, grass density and ambient occlusion (applied on next area load for grass)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)
