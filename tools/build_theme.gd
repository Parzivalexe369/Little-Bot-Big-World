extends SceneTree
## Dev tool: builds res://resources/ui_theme.tres (the project-wide UI theme).
## Usage: godot --headless --path . --script res://tools/build_theme.gd

const INK := Color(0.07, 0.08, 0.11, 0.86)
const INK_SOFT := Color(0.07, 0.08, 0.11, 0.62)
const CREAM := Color(0.97, 0.94, 0.87)
const MUTED := Color(0.72, 0.74, 0.78)
const ACCENT := Color(0.5, 0.95, 0.9)
const ENERGY := Color(0.45, 0.93, 1.0)


func _initialize() -> void:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Variable Text", "Segoe UI", "Noto Sans", "Helvetica Neue", "Arial"])
	font.font_weight = 400
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var bold := SystemFont.new()
	bold.font_names = font.font_names
	bold.font_weight = 650
	var display := SystemFont.new()
	display.font_names = PackedStringArray(["Segoe UI Variable Display", "Segoe UI", "Noto Sans", "Helvetica Neue", "Arial"])
	display.font_weight = 600
	theme.default_font = font
	theme.default_font_size = 22

	# Panels
	theme.set_stylebox("panel", "PanelContainer", _box(INK, 16, 22, 18, Color(1, 1, 1, 0.07)))
	theme.set_stylebox("panel", "Panel", _box(INK, 16, 0, 0, Color(1, 1, 1, 0.07)))
	theme.set_type_variation("SoftPanel", "PanelContainer")
	theme.set_stylebox("panel", "SoftPanel", _box(INK_SOFT, 12, 16, 10, Color(1, 1, 1, 0.05)))
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", _box(Color(0.1, 0.11, 0.15, 0.92), 18, 28, 24, Color(1, 1, 1, 0.09)))

	# Labels
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_constant("shadow_outline_size", "Label", 4)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", display)
	theme.set_font_size("font_size", "TitleLabel", 78)
	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_font("font", "HeaderLabel", bold)
	theme.set_font_size("font_size", "HeaderLabel", 30)
	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_font("font", "CaptionLabel", bold)
	theme.set_font_size("font_size", "CaptionLabel", 15)
	theme.set_color("font_color", "CaptionLabel", MUTED)
	theme.set_type_variation("HintLabel", "Label")
	theme.set_font_size("font_size", "HintLabel", 18)
	theme.set_color("font_color", "HintLabel", MUTED)
	theme.set_type_variation("EnergyLabel", "Label")
	theme.set_font("font", "EnergyLabel", display)
	theme.set_font_size("font_size", "EnergyLabel", 34)
	theme.set_color("font_color", "EnergyLabel", Color(0.86, 0.98, 1.0))
	theme.set_type_variation("KeyLabel", "Label")
	theme.set_font("font", "KeyLabel", bold)
	theme.set_font_size("font_size", "KeyLabel", 18)
	theme.set_color("font_color", "KeyLabel", Color(0.08, 0.09, 0.12))
	theme.set_color("font_shadow_color", "KeyLabel", Color(0, 0, 0, 0))

	# RichTextLabel
	theme.set_color("default_color", "RichTextLabel", CREAM)
	theme.set_font("bold_font", "RichTextLabel", bold)

	# Buttons
	var normal := _box(Color(1, 1, 1, 0.04), 12, 22, 12, Color(1, 1, 1, 0.08))
	var hover := _box(Color(0.97, 0.94, 0.87, 0.14), 12, 22, 12, Color(0.97, 0.94, 0.87, 0.35))
	var pressed := _box(Color(0.5, 0.95, 0.9, 0.22), 12, 22, 12, ACCENT)
	var focus := _box(Color(0, 0, 0, 0), 12, 22, 12, ACCENT)
	focus.border_width_left = 2
	focus.border_width_right = 2
	focus.border_width_top = 2
	focus.border_width_bottom = 2
	var disabled := _box(Color(1, 1, 1, 0.02), 12, 22, 12, Color(1, 1, 1, 0.04))
	for type in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("hover_pressed", type, pressed)
		theme.set_stylebox("focus", type, focus)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_color("font_color", type, CREAM)
		theme.set_color("font_hover_color", type, Color(1, 1, 1))
		theme.set_color("font_pressed_color", type, Color(1, 1, 1))
		theme.set_color("font_focus_color", type, Color(1, 1, 1))
		theme.set_color("font_disabled_color", type, Color(0.6, 0.6, 0.64, 0.6))
		theme.set_font_size("font_size", type, 24)
	theme.set_type_variation("MenuButtonBig", "Button")
	theme.set_font("font", "MenuButtonBig", bold)
	theme.set_font_size("font_size", "MenuButtonBig", 28)

	# Sliders
	var slider_bg := _box(Color(1, 1, 1, 0.12), 6, 0, 0, Color(0, 0, 0, 0))
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	var slider_fill := _box(Color(0.5, 0.95, 0.9, 0.85), 6, 0, 0, Color(0, 0, 0, 0))
	slider_fill.content_margin_top = 4
	slider_fill.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	theme.set_icon("grabber", "HSlider", _dot_icon(22, CREAM))
	theme.set_icon("grabber_highlight", "HSlider", _dot_icon(24, Color(1, 1, 1)))

	# Progress bars (journal)
	theme.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.1), 5, 0, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("fill", "ProgressBar", _box(ENERGY, 5, 0, 0, Color(0, 0, 0, 0)))
	theme.set_color("font_color", "ProgressBar", CREAM)

	# Tabs
	theme.set_stylebox("tab_selected", "TabContainer", _box(Color(1, 1, 1, 0.1), 10, 18, 8, Color(1, 1, 1, 0.12)))
	theme.set_stylebox("tab_unselected", "TabContainer", _box(Color(1, 1, 1, 0.0), 10, 18, 8, Color(0, 0, 0, 0)))
	theme.set_stylebox("tab_hovered", "TabContainer", _box(Color(1, 1, 1, 0.06), 10, 18, 8, Color(0, 0, 0, 0)))
	theme.set_stylebox("tab_focus", "TabContainer", focus)
	theme.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0), 0, 6, 14, Color(0, 0, 0, 0)))
	theme.set_color("font_selected_color", "TabContainer", CREAM)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_color("font_hovered_color", "TabContainer", Color(1, 1, 1))
	theme.set_font_size("font_size", "TabContainer", 22)

	# Popup menus (OptionButton lists)
	theme.set_stylebox("panel", "PopupMenu", _box(Color(0.1, 0.11, 0.15, 0.98), 10, 8, 8, Color(1, 1, 1, 0.1)))
	theme.set_stylebox("hover", "PopupMenu", _box(Color(0.5, 0.95, 0.9, 0.2), 8, 8, 4, Color(0, 0, 0, 0)))
	theme.set_color("font_color", "PopupMenu", CREAM)
	theme.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))
	theme.set_font_size("font_size", "PopupMenu", 22)

	# Scroll bars
	theme.set_stylebox("scroll", "VScrollBar", _box(Color(1, 1, 1, 0.05), 6, 4, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber", "VScrollBar", _box(Color(1, 1, 1, 0.25), 6, 4, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(1, 1, 1, 0.4), 6, 4, 0, Color(0, 0, 0, 0)))

	# Separators
	theme.set_stylebox("separator", "HSeparator", _line(Color(1, 1, 1, 0.12)))
	theme.set_constant("separation", "HSeparator", 18)
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 12)

	var err := ResourceSaver.save(theme, "res://resources/ui_theme.tres")
	print("theme saved: ", error_string(err))
	quit()


func _box(color: Color, radius: int, margin_h: int, margin_v: int, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.anti_aliasing = true
	return sb


func _line(color: Color) -> StyleBoxLine:
	var sl := StyleBoxLine.new()
	sl.color = color
	sl.thickness = 1
	return sl


func _dot_icon(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)
