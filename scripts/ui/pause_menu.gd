class_name PauseMenu
extends CanvasLayer
## Pause overlay: resume, journal, restart from checkpoint, settings, main menu, quit.

signal restart_requested

var _dim: ColorRect
var _menu: PanelContainer
var _settings: SettingsPanel
var _journal: JournalPanel
var _travel: TravelPanel
var _resume: Button
var _open := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.03, 0.04, 0.06, 0.55)
	add_child(_dim)
	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = preload("res://shaders/ui_blur.gdshader")
	blur.material = blur_mat
	_dim.add_child(blur)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu = PanelContainer.new()
	_menu.theme_type_variation = &"CardPanel"
	_menu.custom_minimum_size = Vector2(440, 0)
	center.add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"HintLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.name = "Subtitle"
	box.add_child(sub)
	_resume = _button(box, "Resume", close)
	_button(box, "Journal", _show_journal)
	_button(box, "Travel", _show_travel)
	_button(box, "Restart from checkpoint", func() -> void:
		close()
		restart_requested.emit())
	_button(box, "Settings", _show_settings)
	_button(box, "Save and return to menu", func() -> void:
		SaveSystem.save_game()
		close()
		SceneRouter.go_to_menu())
	# A browser tab cannot be closed by the game (quitting would only freeze the page).
	if not OS.has_feature("web"):
		_button(box, "Quit game", func() -> void:
			SaveSystem.save_game()
			get_tree().quit())
	_settings = SettingsPanel.new()
	_settings.visible = false
	center.add_child(_settings)
	_settings.closed.connect(_back_to_menu)
	_journal = JournalPanel.new()
	_journal.visible = false
	center.add_child(_journal)
	_journal.closed.connect(_back_to_menu)
	_travel = TravelPanel.new()
	_travel.visible = false
	center.add_child(_travel)
	_travel.closed.connect(_back_to_menu)
	_travel.travel_requested.connect(func(area: StringName) -> void:
		close()
		SceneRouter.travel_to(area))
	UiSounds.wire(self)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func is_open() -> bool:
	return _open


func open(show_journal: bool = false) -> void:
	if _open:
		return
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_menu.find_child("Subtitle", true, false) as Label).text = "%s  ·  %d / %d energy" % [GameData.area_name(GameState.current_area), GameState.energy(), GameData.total_fragments()]
	Audio.play_ui(&"ui_open", -4.0)
	if show_journal:
		_show_journal()
	else:
		_back_to_menu()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_settings.visible = false
	_journal.visible = false
	_travel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_ui(&"ui_back", -6.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")) and _menu.visible:
		get_viewport().set_input_as_handled()
		close()


func _show_settings() -> void:
	_menu.visible = false
	_settings.open()


func _show_journal() -> void:
	_menu.visible = false
	_journal.open()


func _show_travel() -> void:
	_menu.visible = false
	_travel.open()


func _back_to_menu() -> void:
	_menu.visible = true
	_settings.visible = false
	_journal.visible = false
	_travel.visible = false
	_resume.grab_focus.call_deferred()
