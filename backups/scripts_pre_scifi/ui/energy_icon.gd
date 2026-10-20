class_name EnergyIcon
extends Control
## A small glowing crystal glyph drawn in code (matches the in-world energy fragments).

var pulse := 0.0:
	set(value):
		pulse = value
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var h := size.y * 0.46
	var w := size.x * 0.26
	var glow := Color(0.45, 0.93, 1.0, 0.18 + 0.25 * pulse)
	draw_circle(c, h * (1.05 + 0.3 * pulse), glow)
	var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, -h * 0.15), c + Vector2(0, h), c + Vector2(-w, -h * 0.15)])
	draw_colored_polygon(pts, Color(0.55, 0.95, 1.0))
	var facet := PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, -h * 0.15), c + Vector2(0, h * 0.1)])
	draw_colored_polygon(facet, Color(0.85, 1.0, 1.0))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(1, 1, 1, 0.8), 1.5, true)
