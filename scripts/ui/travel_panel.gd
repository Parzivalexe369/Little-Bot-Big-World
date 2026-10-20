class_name TravelPanel
extends PanelContainer
## Area select: every area the robot has reached, in journey order. Picking one travels to its
## entry checkpoint (switching between the garden world and the facility when needed).

signal closed
signal travel_requested(area_id: StringName)

var _list: VBoxContainer
var _close_button: Button


func _ready() -> void:
	theme_type_variation = &"CardPanel"
	custom_minimum_size = Vector2(720, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Travel"
	root.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"HintLabel"
	hint.text = "Return to any area you have reached. You arrive at its first checkpoint."
	root.add_child(hint)
	root.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	root.add_child(_list)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(200, 0)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close_button.pressed.connect(close)
	root.add_child(_close_button)


func open() -> void:
	refresh()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var first: Button = null
	var index := 0
	for area: StringName in GameData.ALL_AREA_IDS:
		index += 1
		var unlocked := GameData.area_unlocked(area)
		var here := area == GameState.current_area
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var count := "%d / %d energy" % [GameState.area_fragment_count(area), GameData.FRAGMENTS_PER_AREA[area]]
		if unlocked:
			b.text = "%d.  %s      %s%s" % [index, GameData.area_name(area), count, "   (you are here)" if here else ""]
		else:
			b.text = "%d.  ???" % index
		b.disabled = not unlocked
		b.pressed.connect(func() -> void: travel_requested.emit(area))
		_list.add_child(b)
		if unlocked and first == null and not here:
			first = b
	UiSounds.wire(self)
	(first if first else _close_button).grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()
