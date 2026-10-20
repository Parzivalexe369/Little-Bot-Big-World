class_name ScanIndicator
extends Control
## Scanner ability ring: a radar glyph in the middle, a cooldown sweep while recharging, a
## soft breathing glow when ready, and the key as a small cap on the ring's edge.

const ACCENT := Color(0.5, 0.94, 1.0)

var ratio := 1.0:
	set(value):
		var was_ready := ratio >= 1.0
		ratio = clampf(value, 0.0, 1.0)
		if ratio >= 1.0 and not was_ready:
			_ready_flash = 1.0
		queue_redraw()
var key_text := "Q"
var _ready_flash := 0.0
var _cap := StyleBoxFlat.new()


func _ready() -> void:
	_cap.set_corner_radius_all(5)
	_cap.border_color = Color(0.66, 0.62, 0.55)
	_cap.border_width_bottom = 2


func _process(delta: float) -> void:
	if _ready_flash > 0.0:
		_ready_flash = maxf(_ready_flash - delta * 2.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var ready := ratio >= 1.0
	var breathe := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0025)
	# Glow + backing disc.
	if ready:
		draw_circle(c, r + 6.0 + _ready_flash * 6.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.06 + 0.05 * breathe + 0.25 * _ready_flash))
	draw_circle(c, r + 2.0, Color(0.04, 0.05, 0.08, 0.72))
	draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.1), 3.0, true)
	if ready:
		draw_arc(c, r, 0.0, TAU, 64, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6 + 0.25 * breathe), 3.0, true)
	else:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * ratio, 64, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95), 3.5, true)
	# Radar glyph: a dot and two arcs.
	var glyph := Color(0.97, 0.94, 0.87, 0.95 if ready else 0.4)
	var gc := c + Vector2(0, r * 0.18)
	draw_circle(gc, 3.2, glyph)
	draw_arc(gc, r * 0.32, -PI * 0.78, -PI * 0.22, 16, glyph, 2.5, true)
	draw_arc(gc, r * 0.56, -PI * 0.75, -PI * 0.25, 20, Color(glyph.r, glyph.g, glyph.b, glyph.a * 0.75), 2.5, true)
	# Key cap on the lower-right edge.
	var font := get_theme_default_font()
	var fs := 15
	var ts := font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var cap_size := Vector2(maxf(ts.x + 12.0, 24.0), 22.0)
	var cap_pos := c + Vector2(r * 0.62, r * 0.62) - cap_size * 0.5
	_cap.bg_color = Color(0.97, 0.94, 0.87, 1.0 if ready else 0.7)
	draw_style_box(_cap, Rect2(cap_pos, cap_size))
	draw_string(font, cap_pos + Vector2((cap_size.x - ts.x) * 0.5, cap_size.y * 0.5 + fs * 0.33), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.09, 0.12))
