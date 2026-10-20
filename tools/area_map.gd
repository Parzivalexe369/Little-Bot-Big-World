extends SceneTree
## Dev tool: renders a shaded top-down map of a world region to PNG, for guides.
## North (-Z, the direction of the journey) is up, +X is right.
## Usage: godot --headless --path . --script res://tools/area_map.gd -- x0 z0 x1 z1 px_per_m out.png


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var x0 := float(a[0])
	var z0 := float(a[1])
	var x1 := float(a[2])
	var z1 := float(a[3])
	var s := float(a[4])
	var terrain := WorldTerrain.new()
	if not terrain._load_cache():
		terrain._generate_grid()
	var w := int((x1 - x0) * s)
	var h := int((z1 - z0) * s)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	# Light from the upper left of the map (north-west), like a printed relief map.
	var light := Vector3(-0.55, 0.75, -0.4).normalized()
	var ponds: Array = []
	for pond: Dictionary in WorldLayout.PONDS:
		ponds.append([pond["center"], float(pond["radius"]) + 1.6, WorldTerrain.pond_level(pond["id"])])
	for py in h:
		for px in w:
			var x := x0 + (px + 0.5) / s
			var z := z0 + (py + 0.5) / s
			var p := Vector2(x, z)
			var hgt := WorldTerrain.height_at_world(x, z)
			var n := WorldTerrain.normal_at_world(x, z)
			var d := _data(x, z)
			var c := Color(0.52, 0.64, 0.4).lerp(Color(0.6, 0.6, 0.66), d.a * 0.55)
			c = c.lerp(Color(0.86, 0.76, 0.58), smoothstep(0.15, 0.6, d.r))
			c = c.lerp(Color(0.42, 0.44, 0.34), d.g * 0.6)
			c = c.lerp(Color(0.6, 0.58, 0.55), smoothstep(0.3, 0.5, 1.0 - n.y))
			var water := false
			for pond: Array in ponds:
				if p.distance_to(pond[0]) < pond[1] and hgt < pond[2]:
					water = true
			if water:
				c = Color(0.36, 0.62, 0.8)
			else:
				var shade := clampf(n.dot(light), 0.0, 1.0)
				c = c * (0.5 + shade * 0.62)
				# Faint 2 m contours.
				var f := fposmod(hgt, 2.0)
				if f < 0.12 / maxf(n.y, 0.3):
					c = c.darkened(0.12)
			# Out-of-bounds hills: muted.
			if WorldTerrain._playable_sdf_fast(p, WorldTerrain.path_query_fast(p).x) > 0.5:
				c = c.lerp(Color(c.get_luminance(), c.get_luminance(), c.get_luminance()), 0.55).darkened(0.18)
			img.set_pixel(px, py, c)
	img.save_png(a[5])
	print("saved ", a[5], " ", w, "x", h)
	quit()


## Bilinear sample of the terrain's per-vertex data (path, wet, forest, garden).
func _data(x: float, z: float) -> Color:
	var fx := x - WorldLayout.MIN_X
	var fz := z - WorldLayout.MIN_Z
	var ix := clampi(floori(fx), 0, WorldTerrain._width - 2)
	var iz := clampi(floori(fz), 0, WorldTerrain._depth - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var w := WorldTerrain._width
	var c00 := WorldTerrain._data_a[iz * w + ix]
	var c10 := WorldTerrain._data_a[iz * w + ix + 1]
	var c01 := WorldTerrain._data_a[(iz + 1) * w + ix]
	var c11 := WorldTerrain._data_a[(iz + 1) * w + ix + 1]
	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), tz)
