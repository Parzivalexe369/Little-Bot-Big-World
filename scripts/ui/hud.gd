class_name Hud
extends CanvasLayer
## In-game HUD: objective with progress, energy counter with the current area's fragments,
## a world-anchored interaction prompt, scanner ring, toasts, area title cards, discovery
## cards, one-time control hints, cinematic letterbox, plus presentation feedback (subtle
## vignette, edge flashes, energy sparks that fly into the counter).
## Layout is anchored to a safe margin, so it holds at any resolution or aspect ratio.

const TOAST_TIME := 3.2
const MARGIN := 44.0
const CREAM := Color(0.97, 0.94, 0.87)
const MUTED := Color(0.74, 0.76, 0.8)
const ENERGY := Color(0.5, 0.94, 1.0)
const GOLD := Color(1.0, 0.84, 0.52)
const FX_SHADER := preload("res://shaders/hud_screen_fx.gdshader")

var player: Player:
	set(value):
		player = value
		if player and not player.bonked.is_connected(_on_bonked):
			player.bonked.connect(_on_bonked)
## Forces a specific prompt (e.g. "Wake up" before the robot is awake). Empty clears it.
var forced_prompt := ""

var _root: Control
var _fx_rect: ColorRect
var _fx_mat: ShaderMaterial
var _objective_panel: PanelContainer
var _objective_label: Label
var _objective_bar: HudBar
var _objective_count: Label
var _progress_row: HBoxContainer
var _energy_box: PanelContainer
var _energy_label: Label
var _energy_total: Label
var _energy_icon: EnergyIcon
var _area_label: Label
var _area_bar: HudBar
var _prompt_panel: PanelContainer
var _prompt_key: Label
var _prompt_key_panel: PanelContainer
var _prompt_lock: LockIcon
var _prompt_text: Label
var _prompt_marker: PromptMarker
var _scan: ScanIndicator
var _scan_box: Control
var _toasts: VBoxContainer
var _banner: Control
var _banner_title: Label
var _banner_sub: Label
var _discovery: PanelContainer
var _discovery_title: Label
var _discovery_text: Label
var _hint_panel: PanelContainer
var _hint_label: RichTextLabel
var _save_label: Label
var _letter_top: ColorRect
var _letter_bottom: ColorRect
var _shown_hints: Dictionary = {}
var _objective_fade_timer := 0.0
var _hud_visible := true
var _prompt_target: Interactable
var _prompt_pos := Vector2.ZERO
var _prompt_snap := true
var _area := &""
var _area_timer := 0.0
var _caption_font: Font
var _flash := 0.0
var _count_re := RegEx.create_from_string("\\s*\\(\\d+/\\d+\\)")


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_caption_font = _spaced_font(_root.get_theme_font("font", "CaptionLabel"), 2)
	_build_screen_fx()
	_build_letterbox()
	_build_objective()
	_build_energy()
	_build_prompt()
	_build_scan()
	_build_toasts()
	_build_banner()
	_build_discovery()
	_build_hint()
	GameState.fragment_collected.connect(_on_fragment)
	Quests.objective_changed.connect(_on_objective_changed)
	Quests.objective_progress.connect(func(_id: StringName, text: String) -> void: _set_objective(text, false))
	Quests.objective_completed.connect(_on_objective_completed)
	Events.notify.connect(show_toast)
	Events.area_banner.connect(show_area_banner)
	Events.discovery_shown.connect(show_discovery)
	SaveSystem.saved.connect(_on_saved)
	_set_objective(Quests.current_text(), false)
	_energy_label.text = str(GameState.energy())


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


func _process(delta: float) -> void:
	if player:
		_scan.ratio = player.scan_ready_ratio
		_scan.key_text = InputGlyphs.label("scan")
		_update_prompt(delta)
		_area_timer -= delta
		if _area_timer <= 0.0:
			_area_timer = 0.5
			_update_area()
	if _objective_fade_timer > 0.0 and _hud_visible:
		_objective_fade_timer -= delta
		if _objective_fade_timer <= 0.0:
			var tween := create_tween()
			tween.tween_property(_objective_panel, "modulate:a", 0.6, 1.5)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.2, 0.0)
		_fx_mat.set_shader_parameter("flash", _flash)


# --- Layout ---------------------------------------------------------------------

func _build_screen_fx() -> void:
	_fx_rect = ColorRect.new()
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = FX_SHADER
	_fx_rect.material = _fx_mat
	_root.add_child(_fx_rect)


func _build_letterbox() -> void:
	_letter_top = ColorRect.new()
	_letter_top.color = Color(0, 0, 0, 1)
	_letter_top.anchor_right = 1.0
	_letter_top.offset_bottom = 0.0
	_letter_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_letter_top)
	_letter_bottom = ColorRect.new()
	_letter_bottom.color = Color(0, 0, 0, 1)
	_letter_bottom.anchor_top = 1.0
	_letter_bottom.anchor_right = 1.0
	_letter_bottom.anchor_bottom = 1.0
	_letter_bottom.offset_top = 0.0
	_letter_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_letter_bottom)


func _build_objective() -> void:
	_objective_panel = PanelContainer.new()
	_objective_panel.add_theme_stylebox_override("panel", _fade_style(_objective_panel, false, Vector4(22, 14, 90, 16)))
	_objective_panel.position = Vector2(MARGIN - 22.0, MARGIN - 14.0)
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_objective_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_objective_panel.add_child(box)
	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 8)
	box.add_child(cap_row)
	var diamond := Diamond.new()
	diamond.color = ENERGY
	diamond.custom_minimum_size = Vector2(10, 18)
	cap_row.add_child(diamond)
	cap_row.add_child(_caption("CURRENT GOAL", MUTED))
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.custom_minimum_size = Vector2(440, 0)
	_objective_label.add_theme_font_size_override("font_size", 23)
	_objective_label.add_theme_constant_override("shadow_offset_y", 2)
	_objective_label.add_theme_constant_override("shadow_outline_size", 6)
	_objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	box.add_child(_objective_label)
	_progress_row = HBoxContainer.new()
	_progress_row.add_theme_constant_override("separation", 10)
	box.add_child(_progress_row)
	_objective_bar = HudBar.new()
	_objective_bar.custom_minimum_size = Vector2(190, 14)
	_objective_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_row.add_child(_objective_bar)
	_objective_count = Label.new()
	_objective_count.add_theme_font_size_override("font_size", 16)
	_objective_count.add_theme_color_override("font_color", MUTED)
	_progress_row.add_child(_objective_count)


func _build_energy() -> void:
	_energy_box = PanelContainer.new()
	_energy_box.add_theme_stylebox_override("panel", _fade_style(_energy_box, true, Vector4(90, 12, 22, 14)))
	_energy_box.anchor_left = 1.0
	_energy_box.anchor_right = 1.0
	_energy_box.offset_right = -(MARGIN - 22.0)
	_energy_box.offset_top = MARGIN - 12.0
	_energy_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_energy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_energy_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_energy_box.add_child(col)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_energy_icon = EnergyIcon.new()
	_energy_icon.custom_minimum_size = Vector2(36, 46)
	row.add_child(_energy_icon)
	_energy_label = Label.new()
	_energy_label.theme_type_variation = &"EnergyLabel"
	_energy_label.add_theme_font_size_override("font_size", 40)
	_energy_label.text = "0"
	row.add_child(_energy_label)
	_energy_total = Label.new()
	_energy_total.add_theme_font_size_override("font_size", 19)
	_energy_total.add_theme_color_override("font_color", MUTED)
	_energy_total.text = "/ %d" % GameData.total_fragments()
	_energy_total.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_energy_total)
	var area_row := HBoxContainer.new()
	area_row.alignment = BoxContainer.ALIGNMENT_END
	area_row.add_theme_constant_override("separation", 10)
	col.add_child(area_row)
	_area_label = _caption("", MUTED)
	area_row.add_child(_area_label)
	_area_bar = HudBar.new()
	_area_bar.custom_minimum_size = Vector2(96, 12)
	_area_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	area_row.add_child(_area_bar)
	_save_label = Label.new()
	_save_label.add_theme_font_size_override("font_size", 16)
	_save_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78))
	_save_label.text = "✓  Saved"
	_save_label.anchor_left = 1.0
	_save_label.anchor_right = 1.0
	_save_label.offset_left = -240
	_save_label.offset_right = -MARGIN
	_save_label.offset_top = MARGIN + 92.0
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_save_label.modulate.a = 0.0
	_root.add_child(_save_label)


func _build_prompt() -> void:
	_prompt_marker = PromptMarker.new()
	_prompt_marker.size = Vector2(28, 28)
	_prompt_marker.modulate.a = 0.0
	_prompt_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt_marker)
	_prompt_panel = PanelContainer.new()
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.05, 0.06, 0.09, 0.74)
	pill.set_corner_radius_all(22)
	pill.border_color = Color(1, 1, 1, 0.08)
	pill.set_border_width_all(1)
	pill.content_margin_left = 8
	pill.content_margin_right = 18
	pill.content_margin_top = 7
	pill.content_margin_bottom = 7
	pill.shadow_color = Color(0, 0, 0, 0.25)
	pill.shadow_size = 8
	_prompt_panel.add_theme_stylebox_override("panel", pill)
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.modulate.a = 0.0
	_root.add_child(_prompt_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_prompt_panel.add_child(row)
	_prompt_key_panel = _keycap()
	row.add_child(_prompt_key_panel)
	_prompt_key = _prompt_key_panel.get_child(0) as Label
	_prompt_lock = LockIcon.new()
	_prompt_lock.custom_minimum_size = Vector2(30, 30)
	_prompt_lock.visible = false
	row.add_child(_prompt_lock)
	_prompt_text = Label.new()
	_prompt_text.text = ""
	_prompt_text.add_theme_font_size_override("font_size", 21)
	_prompt_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prompt_text)


func _build_scan() -> void:
	_scan_box = VBoxContainer.new()
	(_scan_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_scan_box as VBoxContainer).add_theme_constant_override("separation", 6)
	_scan_box.anchor_left = 1.0
	_scan_box.anchor_right = 1.0
	_scan_box.anchor_top = 1.0
	_scan_box.anchor_bottom = 1.0
	_scan_box.offset_left = -MARGIN - 96.0
	_scan_box.offset_right = -MARGIN
	_scan_box.offset_top = -MARGIN - 112.0
	_scan_box.offset_bottom = -MARGIN
	_scan_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scan_box)
	_scan = ScanIndicator.new()
	_scan.custom_minimum_size = Vector2(78, 78)
	_scan.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan_box.add_child(_scan)
	var label := _caption("SCAN", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scan_box.add_child(label)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_left = MARGIN
	_toasts.offset_top = -MARGIN - 230.0
	_toasts.offset_bottom = -MARGIN
	_toasts.offset_right = MARGIN + 620.0
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 150
	_banner.offset_left = -560
	_banner.offset_right = 560
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	(_banner as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_banner as VBoxContainer).add_theme_constant_override("separation", 6)
	_root.add_child(_banner)
	var sub_row := HBoxContainer.new()
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_row.add_theme_constant_override("separation", 14)
	_banner.add_child(sub_row)
	sub_row.add_child(_rule(90))
	_banner_sub = _caption("", Color(0.97, 0.94, 0.87, 0.85))
	_banner_sub.add_theme_font_size_override("font_size", 18)
	sub_row.add_child(_banner_sub)
	sub_row.add_child(_rule(90))
	_banner_title = Label.new()
	_banner_title.theme_type_variation = &"TitleLabel"
	_banner_title.add_theme_font_size_override("font_size", 64)
	_banner_title.add_theme_constant_override("shadow_outline_size", 12)
	_banner_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.3))
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)


func _build_discovery() -> void:
	_discovery = PanelContainer.new()
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.06, 0.07, 0.1, 0.8)
	card.set_corner_radius_all(14)
	card.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	card.border_width_top = 2
	card.content_margin_left = 26
	card.content_margin_right = 26
	card.content_margin_top = 18
	card.content_margin_bottom = 20
	card.shadow_color = Color(0, 0, 0, 0.3)
	card.shadow_size = 16
	_discovery.add_theme_stylebox_override("panel", card)
	_discovery.anchor_left = 1.0
	_discovery.anchor_right = 1.0
	_discovery.anchor_top = 0.5
	_discovery.anchor_bottom = 0.5
	_discovery.offset_left = -MARGIN - 480.0
	_discovery.offset_right = -MARGIN
	_discovery.offset_top = -110
	_discovery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discovery.modulate.a = 0.0
	_root.add_child(_discovery)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_discovery.add_child(box)
	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 8)
	box.add_child(cap_row)
	var star := ToastIcon.new()
	star.kind = "discovery"
	star.custom_minimum_size = Vector2(18, 18)
	cap_row.add_child(star)
	cap_row.add_child(_caption("DISCOVERY", GOLD))
	_discovery_title = Label.new()
	_discovery_title.theme_type_variation = &"HeaderLabel"
	box.add_child(_discovery_title)
	_discovery_text = Label.new()
	_discovery_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_discovery_text.custom_minimum_size = Vector2(420, 0)
	_discovery_text.add_theme_font_size_override("font_size", 20)
	box.add_child(_discovery_text)
	var foot := _caption("ADDED TO JOURNAL", MUTED)
	foot.add_theme_font_size_override("font_size", 13)
	box.add_child(foot)


func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.05, 0.06, 0.09, 0.66)
	pill.set_corner_radius_all(20)
	pill.content_margin_left = 22
	pill.content_margin_right = 22
	pill.content_margin_top = 8
	pill.content_margin_bottom = 8
	_hint_panel.add_theme_stylebox_override("panel", pill)
	_hint_panel.anchor_left = 0.5
	_hint_panel.anchor_right = 0.5
	_hint_panel.anchor_top = 1.0
	_hint_panel.anchor_bottom = 1.0
	_hint_panel.offset_top = -MARGIN - 20.0
	_hint_panel.offset_bottom = -MARGIN - 20.0
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.modulate.a = 0.0
	_root.add_child(_hint_panel)
	_hint_label = RichTextLabel.new()
	_hint_label.bbcode_enabled = true
	_hint_label.fit_content = true
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint_label.scroll_active = false
	_hint_label.add_theme_font_size_override("normal_font_size", 19)
	_hint_label.add_theme_font_size_override("bold_font_size", 19)
	_hint_label.add_theme_color_override("default_color", CREAM)
	_hint_panel.add_child(_hint_label)


# --- Small builders -------------------------------------------------------------

func _spaced_font(base: Font, spacing: int) -> Font:
	if base == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = base
	fv.set_spacing(TextServer.SPACING_GLYPH, spacing)
	return fv


func _caption(text: String, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"CaptionLabel"
	if _caption_font:
		l.add_theme_font_override("font", _caption_font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.text = text
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _rule(width: float) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.97, 0.94, 0.87, 0.45)
	line.custom_minimum_size = Vector2(width, 1)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Cream key cap with a darker bottom edge, so it reads as a physical key.
func _keycap() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.87)
	style.set_corner_radius_all(7)
	style.border_color = Color(0.66, 0.62, 0.55)
	style.border_width_bottom = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(34, 32)
	var key := Label.new()
	key.theme_type_variation = &"KeyLabel"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(key)
	return panel


## Soft dark backdrop that fades out toward the screen's interior and at the top and
## bottom (no hard box edges). Drawn as a vertex-colored grid behind the panel's content.
func _fade_style(panel: Control, from_right: bool, margins: Vector4) -> StyleBoxEmpty:
	panel.draw.connect(_draw_fade.bind(panel, from_right))
	var style := StyleBoxEmpty.new()
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	return style


func _draw_fade(panel: Control, from_right: bool) -> void:
	var s := panel.size
	var xs := [0.0, 0.5, 1.0]
	var x_alpha := [0.62, 0.42, 0.0]
	var ys := [0.0, 0.25, 0.75, 1.0]
	var y_alpha := [0.0, 1.0, 1.0, 0.0]
	for xi in 2:
		for yi in 3:
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var u: float = xs[xi + corner.x]
				var v: float = ys[yi + corner.y]
				var a: float = x_alpha[xi + corner.x] * y_alpha[yi + corner.y]
				pts.append(Vector2((1.0 - u) * s.x if from_right else u * s.x, v * s.y))
				cols.append(Color(0.03, 0.04, 0.06, a))
			panel.draw_polygon(pts, cols)


# --- Public API ---------------------------------------------------------------

func set_hud_visible(value: bool, duration: float = 0.5) -> void:
	_hud_visible = value
	if value:
		_objective_fade_timer = 9.0
	var tween := create_tween().set_parallel(true)
	for node: CanvasItem in [_objective_panel, _energy_box, _scan_box, _prompt_panel, _prompt_marker]:
		var shown := 1.0 if node != _prompt_panel and node != _prompt_marker else 0.0
		tween.tween_property(node, "modulate:a", shown if value else 0.0, duration)


func set_letterbox(on: bool, duration: float = 0.8) -> void:
	var h := 90.0 if on else 0.0
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_letter_top, "offset_bottom", h, duration)
	tween.tween_property(_letter_bottom, "offset_top", -h, duration)


func show_toast(text: String, kind: String = "info") -> void:
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var panel := PanelContainer.new()
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	pill.set_corner_radius_all(18)
	pill.content_margin_left = 12
	pill.content_margin_right = 18
	pill.content_margin_top = 7
	pill.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", pill)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon := ToastIcon.new()
	icon.kind = kind
	icon.custom_minimum_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	row.add_child(label)
	holder.modulate.a = 0.0
	holder.add_theme_constant_override("margin_left", -24)
	_toasts.add_child(holder)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tween := holder.create_tween()
	tween.tween_property(holder, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_method(func(v: float) -> void: holder.add_theme_constant_override("margin_left", int(v)), -24.0, 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(TOAST_TIME)
	tween.tween_property(holder, "modulate:a", 0.0, 0.6)
	tween.tween_callback(holder.queue_free)


func show_area_banner(area_id: StringName) -> void:
	var index := GameData.AREA_IDS.find(area_id)
	_banner_sub.text = ["I", "II", "III", "IV"][maxi(index, 0)] if index >= 0 else ""
	_banner_title.text = GameData.area_name(area_id)
	_banner.offset_top = 165
	var tween := create_tween()
	tween.tween_property(_banner, "modulate:a", 1.0, 1.2)
	tween.parallel().tween_property(_banner, "offset_top", 150.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.6)
	tween.tween_property(_banner, "modulate:a", 0.0, 1.6)


func show_discovery(discovery_id: StringName) -> void:
	var entry := GameData.discovery(discovery_id)
	if entry.is_empty():
		return
	_discovery_title.text = entry["title"]
	_discovery_text.text = entry["text"]
	_discovery.offset_left = -MARGIN - 440.0
	var tween := create_tween()
	tween.tween_property(_discovery, "modulate:a", 1.0, 0.5)
	tween.parallel().tween_property(_discovery, "offset_left", -MARGIN - 480.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(5.5)
	tween.tween_property(_discovery, "modulate:a", 0.0, 0.8)


## Shows a control hint once per id, e.g. ("move", "[b]WASD[/b] move   [b]Mouse[/b] look").
func show_hint(id: String, bbcode: String, duration: float = 6.0) -> void:
	if _shown_hints.has(id):
		return
	_shown_hints[id] = true
	_hint_label.text = "[center]%s[/center]" % bbcode
	var tween := create_tween()
	tween.tween_property(_hint_panel, "modulate:a", 1.0, 0.5)
	tween.tween_interval(duration)
	tween.tween_property(_hint_panel, "modulate:a", 0.0, 0.8)


func has_shown_hint(id: String) -> bool:
	return _shown_hints.has(id)


# --- Updates --------------------------------------------------------------------

func _update_prompt(delta: float) -> void:
	var target: Interactable = player.interactor.current if player and player.input_enabled else null
	var text := ""
	var locked := false
	if forced_prompt != "":
		text = forced_prompt
		target = null
	elif target != null and _hud_visible:
		text = target.get_prompt()
		locked = target.locked
	else:
		target = null
	var visible_now := text != ""
	_prompt_key.text = InputGlyphs.label("interact")
	_prompt_key_panel.visible = not locked
	_prompt_lock.visible = locked
	if visible_now:
		_prompt_text.text = text
		_prompt_text.modulate = Color(1, 1, 1, 0.7) if locked else Color(1, 1, 1, 1)
	if target != _prompt_target:
		_prompt_target = target
		_prompt_snap = true
	# Anchor the prompt just above the focused object; fall back to the lower middle.
	var view := _root.get_viewport_rect().size
	var anchor := Vector2(view.x * 0.5, view.y - MARGIN - 120.0)
	var on_object := false
	var cam := get_viewport().get_camera_3d()
	if target != null and cam != null:
		var world_point := target.get_focus_point()
		if not cam.is_position_behind(world_point):
			anchor = cam.unproject_position(world_point)
			on_object = true
	var panel_size := _prompt_panel.get_combined_minimum_size()
	var goal := anchor - Vector2(panel_size.x * 0.5, panel_size.y + (34.0 if on_object else 0.0))
	goal.x = clampf(goal.x, MARGIN, view.x - MARGIN - panel_size.x)
	goal.y = clampf(goal.y, MARGIN + 120.0, view.y - MARGIN - panel_size.y - 70.0)
	if _prompt_snap:
		_prompt_pos = goal
		_prompt_snap = false
	else:
		_prompt_pos = _prompt_pos.lerp(goal, 1.0 - exp(-delta * 16.0))
	_prompt_panel.position = _prompt_pos
	_prompt_panel.size = panel_size
	_prompt_marker.position = anchor - _prompt_marker.size * 0.5
	_prompt_marker.locked = locked
	var target_alpha := 1.0 if visible_now else 0.0
	_prompt_panel.modulate.a = move_toward(_prompt_panel.modulate.a, target_alpha, delta * 6.0)
	_prompt_marker.modulate.a = move_toward(_prompt_marker.modulate.a, target_alpha if on_object else 0.0, delta * 6.0)


func _update_area() -> void:
	var best := GameState.current_area
	if not GameData.FRAGMENTS_PER_AREA.has(best):
		return
	var total: int = GameData.FRAGMENTS_PER_AREA[best]
	var got := GameState.area_fragment_count(best)
	if best != _area:
		_area = best
		var tween := create_tween()
		_area_label.modulate.a = 0.0
		tween.tween_property(_area_label, "modulate:a", 1.0, 0.6)
	_area_label.text = "%s  %d/%d" % [GameData.area_name(best).to_upper().trim_prefix("THE "), got, total]
	_area_bar.segments = total
	_area_bar.ratio = float(got) / float(total)


func _set_objective(text: String, highlight: bool) -> void:
	_objective_panel.visible = text != ""
	var progress := Quests.current_progress()
	_progress_row.visible = progress.y > 0
	# The bar shows the count, so "(1/3)" in the sentence would just repeat it.
	_objective_label.text = _count_re.sub(text, "", true) if progress.y > 0 else text
	if progress.y > 0:
		_objective_bar.segments = progress.y if progress.y <= 12 else 0
		_objective_bar.ratio = clampf(float(progress.x) / float(progress.y), 0.0, 1.0)
		_objective_count.text = "%d / %d" % [mini(progress.x, progress.y), progress.y]
	if not _hud_visible:
		return
	if highlight:
		_objective_panel.modulate.a = 1.0
		var tween := create_tween()
		_objective_panel.position.x = MARGIN - 42.0
		tween.tween_property(_objective_panel, "position:x", MARGIN - 22.0, 0.5).set_trans(Tween.TRANS_BACK)
	else:
		_objective_panel.modulate.a = maxf(_objective_panel.modulate.a, 0.9)
	_objective_fade_timer = 9.0


func _on_objective_changed(_id: StringName, text: String) -> void:
	_set_objective(text, true)


func _on_objective_completed(_id: StringName) -> void:
	Audio.play_sfx(&"objective", -6.0)


func _on_fragment(_id: StringName, total: int) -> void:
	_spawn_sparks(total)
	_flash_screen(Color(0.5, 0.94, 1.0, 1.0), 0.32)
	_area_timer = 0.0
	if Quests.current_progress().y > 0:
		_set_objective(Quests.current_text(), false)


## Small glowing sparks fly from the robot to the energy counter; the count ticks on arrival.
func _spawn_sparks(total: int) -> void:
	var cam := get_viewport().get_camera_3d()
	var from := _root.get_viewport_rect().size * 0.5
	if cam and player and not cam.is_position_behind(player.global_position):
		from = cam.unproject_position(player.global_position + Vector3.UP * 0.4)
	var to := _energy_icon.get_global_rect().get_center()
	var count := 7
	for i in count:
		var spark := Spark.new()
		spark.size = Vector2(18, 18)
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(spark)
		var ctrl := from.lerp(to, 0.35) + Vector2(randf_range(-160, 160), randf_range(-200, -40))
		var duration := randf_range(0.5, 0.75)
		spark.position = from - spark.size * 0.5
		var tween := spark.create_tween()
		tween.tween_interval(i * 0.035)
		tween.tween_method(func(t: float) -> void:
			var a := from.lerp(ctrl, t)
			var b := ctrl.lerp(to, t)
			spark.position = a.lerp(b, t) - spark.size * 0.5
			spark.scale = Vector2.ONE * lerpf(1.0, 0.55, t), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(spark.queue_free)
	var arrive := create_tween()
	arrive.tween_interval(0.55)
	arrive.tween_callback(func() -> void:
		_energy_label.text = str(total)
		_energy_box.pivot_offset = _energy_box.size * Vector2(0.85, 0.4))
	arrive.tween_property(_energy_box, "scale", Vector2.ONE * 1.12, 0.1)
	arrive.tween_property(_energy_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
	arrive.parallel().tween_method(func(v: float) -> void: _energy_icon.pulse = v, 1.0, 0.0, 0.9)


func _flash_screen(color: Color, amount: float) -> void:
	_fx_mat.set_shader_parameter("flash_color", color)
	_flash = maxf(_flash, amount)
	_fx_mat.set_shader_parameter("flash", _flash)


func _on_bonked(_contact: Vector3) -> void:
	_flash_screen(Color(1.0, 0.62, 0.35, 1.0), 0.45)


func _on_saved() -> void:
	var tween := create_tween()
	tween.tween_property(_save_label, "modulate:a", 0.9, 0.3)
	tween.tween_interval(1.2)
	tween.tween_property(_save_label, "modulate:a", 0.0, 0.8)


# --- Drawn widgets ----------------------------------------------------------------

## Thin progress bar; with segments > 0 it is split into pips.
class HudBar extends Control:
	var ratio := 0.0:
		set(value):
			ratio = clampf(value, 0.0, 1.0)
			queue_redraw()
	var segments := 0:
		set(value):
			segments = value
			queue_redraw()

	func _draw() -> void:
		var h := 4.0
		var y := (size.y - h) * 0.5
		if segments <= 0:
			draw_rect(Rect2(0, y, size.x, h), Color(1, 1, 1, 0.16))
			draw_rect(Rect2(0, y, size.x * ratio, h), Color(0.5, 0.94, 1.0, 0.95))
			return
		var gap := 3.0
		var w := (size.x - gap * (segments - 1)) / segments
		var filled := int(round(ratio * segments))
		for i in segments:
			var c := Color(0.5, 0.94, 1.0, 0.95) if i < filled else Color(1, 1, 1, 0.16)
			draw_rect(Rect2(i * (w + gap), y, w, h), c)


class Diamond extends Control:
	var color := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.7, 0), c + Vector2(0, r), c + Vector2(-r * 0.7, 0)]), color)


class LockIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1.0, 0.78, 0.6, 0.95)
		draw_arc(c + Vector2(0, -3), 6.0, PI, TAU, 16, col, 2.5, true)
		draw_rect(Rect2(c + Vector2(-8, -2), Vector2(16, 12)), col)


## Pulsing ring that marks the focused object in the world.
class PromptMarker extends Control:
	var locked := false

	func _process(_delta: float) -> void:
		if modulate.a > 0.01:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var t := Time.get_ticks_msec() * 0.001
		var col := Color(1.0, 0.78, 0.6) if locked else Color(0.5, 0.94, 1.0)
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		draw_circle(c, 3.0, Color(col.r, col.g, col.b, 0.95))
		draw_arc(c, 8.0 + pulse * 3.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.75 - pulse * 0.4), 2.0, true)


class ToastIcon extends Control:
	var kind := "info"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		match kind:
			"energy":
				var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.55, 0), c + Vector2(0, r), c + Vector2(-r * 0.55, 0)])
				draw_circle(c, r, Color(0.5, 0.94, 1.0, 0.18))
				draw_colored_polygon(pts, Color(0.6, 0.96, 1.0))
			"save":
				draw_circle(c, r, Color(0.6, 1.0, 0.7, 0.2))
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.45, 0), c + Vector2(-r * 0.1, r * 0.35), c + Vector2(r * 0.5, -r * 0.35)]), Color(0.7, 1.0, 0.78), 2.5, true)
			"locked":
				draw_arc(c + Vector2(0, -r * 0.25), r * 0.4, PI, TAU, 12, Color(1.0, 0.75, 0.55), 2.0, true)
				draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.2), Vector2(r * 1.1, r * 0.8)), Color(1.0, 0.75, 0.55))
			"discovery":
				var star := PackedVector2Array()
				for i in 10:
					var a := -PI * 0.5 + i * PI / 5.0
					var rr := r if i % 2 == 0 else r * 0.45
					star.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(star, Color(1.0, 0.84, 0.52))
			_:
				draw_circle(c, r * 0.4, Color(0.97, 0.94, 0.87, 0.85))


class Spark extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, size.x * 0.5, Color(0.5, 0.94, 1.0, 0.25))
		draw_circle(c, size.x * 0.22, Color(0.85, 1.0, 1.0, 0.95))
