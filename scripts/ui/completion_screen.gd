class_name CompletionScreen
extends CanvasLayer
## Shown after the Crystal Heart is restored: a quiet thank-you, stats, and the choice to
## keep exploring the now-living world or return to the menu.

signal continue_exploring

var _panel: PanelContainer
var _stats: Label
var _keep: Button


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.45)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"CardPanel"
	_panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_panel.add_child(box)
	var cap := Label.new()
	cap.theme_type_variation = &"CaptionLabel"
	cap.text = "THE WORLD IS AWAKE"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	box.add_child(cap)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 54)
	title.text = "Little Bot, Big World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var msg := Label.new()
	msg.text = "Light runs through the old machines again. The meadow blooms, the forest glows,\nthe shrine sings, and the crystals remember their colors."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(msg)
	box.add_child(HSeparator.new())
	_stats = Label.new()
	_stats.theme_type_variation = &"HintLabel"
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_keep = Button.new()
	_keep.text = "Keep exploring"
	_keep.custom_minimum_size = Vector2(260, 0)
	_keep.pressed.connect(_on_keep)
	row.add_child(_keep)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(260, 0)
	menu.pressed.connect(func() -> void:
		visible = false
		get_tree().paused = false
		SceneRouter.go_to_menu())
	row.add_child(menu)
	UiSounds.wire(self)


func open() -> void:
	var minutes := int(GameState.play_time / 60.0)
	_stats.text = "Energy fragments  %d / %d        Discoveries  %d / %d        Time  %dh %02dm" % [
		GameState.energy(), GameData.total_fragments(), GameState.discoveries.size(), GameData.DISCOVERIES.size(),
		minutes / 60, minutes % 60]
	visible = true
	_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, 1.2)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_keep.grab_focus.call_deferred()


func _on_keep() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	continue_exploring.emit()
