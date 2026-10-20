class_name JournalPanel
extends PanelContainer
## The robot's journal: current goal, energy found per area and discoveries made.

signal closed

var _goal: Label
var _areas: VBoxContainer
var _discoveries: VBoxContainer
var _close_button: Button


func _ready() -> void:
	theme_type_variation = &"CardPanel"
	custom_minimum_size = Vector2(1100, 640)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Journal"
	root.add_child(title)
	_goal = Label.new()
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.theme_type_variation = &"HintLabel"
	root.add_child(_goal)
	root.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	columns.add_child(left)
	var cap1 := Label.new()
	cap1.theme_type_variation = &"CaptionLabel"
	cap1.text = "ENERGY FRAGMENTS"
	left.add_child(cap1)
	_areas = VBoxContainer.new()
	_areas.add_theme_constant_override("separation", 14)
	left.add_child(_areas)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var cap2 := Label.new()
	cap2.theme_type_variation = &"CaptionLabel"
	cap2.text = "DISCOVERIES"
	right.add_child(cap2)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_discoveries = VBoxContainer.new()
	_discoveries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_discoveries.add_theme_constant_override("separation", 10)
	scroll.add_child(_discoveries)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(200, 0)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close_button.pressed.connect(close)
	root.add_child(_close_button)
	UiSounds.wire(self)


func open() -> void:
	refresh()
	visible = true
	_close_button.grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("journal") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


func refresh() -> void:
	_goal.text = "Current goal: " + Quests.current_text()
	for child in _areas.get_children():
		child.queue_free()
	for child in _discoveries.get_children():
		child.queue_free()
	for area: StringName in GameData.ALL_AREA_IDS:
		if GameData.is_facility_area(area) and not GameData.area_unlocked(area):
			continue
		var total: int = GameData.FRAGMENTS_PER_AREA[area]
		var have := GameState.area_fragment_count(area)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = GameData.area_name(area) if GameState.has_flag(StringName("visited_%s" % area)) or area == &"meadow" else "???"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count := Label.new()
		count.text = "%d / %d" % [have, total]
		count.theme_type_variation = &"HintLabel"
		row.add_child(count)
		box.add_child(row)
		var bar := ProgressBar.new()
		bar.max_value = total
		bar.value = have
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		box.add_child(bar)
		_areas.add_child(box)
	var total_label := Label.new()
	total_label.theme_type_variation = &"HintLabel"
	total_label.text = "Total energy: %d / %d" % [GameState.energy(), GameData.total_fragments()]
	_areas.add_child(total_label)
	for entry: Dictionary in GameData.DISCOVERIES:
		var found := GameState.has_discovery(entry["id"])
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		var t := Label.new()
		t.text = entry["title"] if found else "Undiscovered"
		t.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6) if found else Color(0.6, 0.62, 0.66))
		card.add_child(t)
		var d := Label.new()
		d.theme_type_variation = &"HintLabel"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.text = entry["text"] if found else "Somewhere in %s." % GameData.area_name(entry["area"])
		card.add_child(d)
		_discoveries.add_child(card)
