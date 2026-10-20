extends SceneTree
## Dev tool: renders a top-down hillshade map of the generated terrain with layout overlays.
## Usage: godot --headless --path . --script res://tools/terrain_preview.gd


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var terrain := WorldTerrain.new()
	terrain._generate_grid()
	print("grid generated in ", Time.get_ticks_msec() - t0, " ms")
	var w := WorldTerrain._width
	var d := WorldTerrain._depth
	var img := Image.create(w, d, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.5, 0.8, -0.3).normalized()
	var min_h := INF
	var max_h := -INF
	for h in WorldTerrain._heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
	for iz in d:
		for ix in w:
			var i := iz * w + ix
			var h := WorldTerrain._heights[i]
			var n := terrain._grid_normal(ix, iz)
			var shade := clampf(n.dot(light), 0.0, 1.0)
			var t := inverse_lerp(min_h, max_h, h)
			var a := WorldTerrain._data_a[i]
			var b := WorldTerrain._data_b[i]
			var base := Color(0.45, 0.6, 0.25).lerp(Color(0.2, 0.32, 0.15), a.b).lerp(Color(0.6, 0.6, 0.75), a.a).lerp(Color(0.62, 0.6, 0.45), b.x)
			base = base.lerp(Color(0.7, 0.55, 0.38), a.r)
			base = base.lerp(Color(0.3, 0.45, 0.7), a.g * 0.8)
			if 1.0 - n.y > 0.4:
				base = base.lerp(Color(0.5, 0.48, 0.45), 0.7)
			var c := base * (0.35 + shade * 0.8) * (0.8 + t * 0.4)
			# contour lines every 2 m
			if fmod(absf(h), 2.0) < 0.12:
				c = c.darkened(0.25)
			img.set_pixel(ix, iz, c)
	var out := ProjectSettings.globalize_path("res://docs/reference/terrain_map.png")
	img.save_png(out)
	print("height range ", min_h, " .. ", max_h)
	print("saved ", out)
	quit()
