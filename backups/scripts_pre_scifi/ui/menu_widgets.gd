class_name MenuWidgets
extends RefCounted
## Drawn widgets for the main menu: a softly lit mint primary button, minimal secondary
## items with an animated hover indicator, and a small botanical divider. Hover and keyboard
## or gamepad focus look the same (the UI sounds helper moves focus to the hovered button).

const CREAM := Color(0.99, 0.96, 0.9)
const MINT := Color(0.58, 0.96, 0.8)
const FONT_TITLE := preload("res://assets/fonts/Fredoka.ttf")
const FONT_TEXT := preload("res://assets/fonts/Nunito.ttf")


## A variable-font instance at a given weight (and optional letter spacing).
static func font(base: FontFile, weight: int, spacing := 0, width := 100) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	var axes := {ts.name_to_tag("wght"): weight}
	if base == FONT_TITLE:
		axes[ts.name_to_tag("wdth")] = width
	fv.variation_opentype = axes
	if spacing != 0:
		fv.set_spacing(TextServer.SPACING_GLYPH, spacing)
	return fv


static func _clear_styles(b: Button, margins: Vector4) -> StyleBoxEmpty:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = margins.x
	empty.content_margin_top = margins.y
	empty.content_margin_right = margins.z
	empty.content_margin_bottom = margins.w
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(state, empty)
	return empty


## Primary action: rounded, faintly mint-tinted glass with a soft glow that brightens on hover.
class PrimaryButton extends Button:
	var _t := 0.0
	var _press := 0.0
	var _box := StyleBoxFlat.new()
	var _glow: Array[StyleBoxFlat] = []

	func _init(label: String) -> void:
		for i in 3:
			var g := StyleBoxFlat.new()
			g.set_corner_radius_all(16 + (i + 1) * 5)
			g.anti_aliasing = true
			_glow.append(g)
		text = label
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(380, 66)
		MenuWidgets._clear_styles(self, Vector4(28, 10, 64, 12))
		add_theme_font_override("font", MenuWidgets.font(MenuWidgets.FONT_TEXT, 750, 1))
		add_theme_font_size_override("font_size", 27)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			add_theme_color_override(c, MenuWidgets.CREAM)
		add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
		add_theme_constant_override("shadow_offset_y", 1)
		_box.set_corner_radius_all(16)
		_box.set_border_width_all(1)
		_box.anti_aliasing = true
		button_down.connect(func() -> void: _press = 1.0)

	func _process(delta: float) -> void:
		var goal := 1.0 if (has_focus() or is_hovered()) and not disabled else 0.0
		var prev := _t
		_t = move_toward(_t, goal, delta * 6.0)
		_press = move_toward(_press, 0.0, delta * 5.0)
		if not is_equal_approx(prev, _t) or _press > 0.0 or _t > 0.0:
			queue_redraw()

	func _draw() -> void:
		var m := MenuWidgets.MINT
		var e := _t * _t * (3.0 - 2.0 * _t)
		var r := Rect2(Vector2.ZERO, size)
		# Soft outer glow (a few feathered rings).
		for i in 3:
			_glow[i].bg_color = Color(m.r, m.g, m.b, (0.035 + 0.05 * e) * (1.0 - i * 0.3))
			draw_style_box(_glow[i], r.grow((i + 1) * 5.0))
		_box.bg_color = Color(m.r * 0.5, m.g * 0.62, m.b * 0.56, 0.2 + 0.14 * e - 0.08 * _press)
		_box.border_color = Color(m.r, m.g, m.b, 0.42 + 0.45 * e)
		draw_style_box(_box, r)
		# Top sheen line, like light catching the rim of a glass pill.
		draw_line(Vector2(18, 1.5), Vector2(size.x - 18, 1.5), Color(1, 1, 1, 0.12 + 0.12 * e), 1.0, true)
		# Chevron on the right that nudges forward on hover.
		var cx := size.x - 34.0 + e * 5.0
		var cy := size.y * 0.5
		var col := Color(m.r, m.g, m.b, 0.75 + 0.25 * e)
		draw_polyline(PackedVector2Array([Vector2(cx - 5, cy - 8), Vector2(cx + 3, cy), Vector2(cx - 5, cy + 8)]), col, 2.4, true)


## Secondary item: just text; on hover a mint dot and soft gradient slide in from the left.
class MenuItem extends Button:
	var _t := 0.0
	var _style: StyleBoxEmpty

	func _init(label: String) -> void:
		text = label
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(380, 50)
		_style = MenuWidgets._clear_styles(self, Vector4(28, 6, 20, 8))
		add_theme_font_override("font", MenuWidgets.font(MenuWidgets.FONT_TEXT, 650, 1))
		add_theme_font_size_override("font_size", 25)
		add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.02, 0.35))
		add_theme_constant_override("shadow_offset_y", 1)
		add_theme_constant_override("shadow_outline_size", 7)
		_apply_color()

	func _apply_color() -> void:
		var c := MenuWidgets.CREAM
		var col := Color(c.r, c.g, c.b, 0.74 + 0.26 * _t)
		for name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			add_theme_color_override(name, col)

	func _process(delta: float) -> void:
		var goal := 1.0 if (has_focus() or is_hovered()) and not disabled else 0.0
		if is_equal_approx(_t, goal):
			return
		_t = move_toward(_t, goal, delta * 7.0)
		var e := _t * _t * (3.0 - 2.0 * _t)
		_style.content_margin_left = 28.0 + 10.0 * e
		_apply_color()
		queue_redraw()

	func _draw() -> void:
		var e := _t * _t * (3.0 - 2.0 * _t)
		if e <= 0.001:
			return
		var m := MenuWidgets.MINT
		# Gradient wash fading to the right.
		var steps := 12
		var w := size.x * 0.85
		for i in steps:
			var a := (1.0 - float(i) / steps) * 0.1 * e
			draw_rect(Rect2(i * w / steps, 4, w / steps + 1, size.y - 8), Color(m.r, m.g, m.b, a))
		draw_circle(Vector2(12.0 + 4.0 * e, size.y * 0.5), 3.5 * e, Color(m.r, m.g, m.b, e))


## A short hairline ending in a tiny two-leaf sprout (quiet botanical accent).
class Sprout extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(120, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var m := MenuWidgets.MINT
		var y := size.y * 0.62
		var line_col := Color(MenuWidgets.CREAM.r, MenuWidgets.CREAM.g, MenuWidgets.CREAM.b, 0.32)
		draw_line(Vector2(2, y), Vector2(70, y), line_col, 1.0, true)
		var base := Vector2(82, y)
		draw_line(base, base + Vector2(0, -11), Color(m.r, m.g, m.b, 0.85), 1.6, true)
		_leaf(base + Vector2(0, -8), Vector2(-9, -6), m)
		_leaf(base + Vector2(0, -11), Vector2(9, -7), m)

	func _leaf(at: Vector2, tip: Vector2, m: Color) -> void:
		var pts := PackedVector2Array()
		var n := Vector2(-tip.y, tip.x).normalized() * 3.2
		for i in 9:
			var t := float(i) / 8.0
			pts.append(at + tip * t + n * sin(t * PI))
		for i in range(8, -1, -1):
			var t := float(i) / 8.0
			pts.append(at + tip * t - n * sin(t * PI) * 0.35)
		draw_colored_polygon(pts, Color(m.r, m.g, m.b, 0.85))
