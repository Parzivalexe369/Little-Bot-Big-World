extends SceneTree
## Dev tool: top-down map of terrain, path, boundary wall contour and every gameplay object
## placed in the level scenes. Usage: godot --headless --path . --script res://tools/layout_map.gd

const SCALE := 2  # pixels per meter
const COLORS := {
	"energy_fragment": Color(0.3, 0.95, 1.0), "checkpoint": Color(0.4, 1.0, 0.4), "flag_trigger": Color(1, 1, 0.3),
	"discovery_spot": Color(1.0, 0.8, 0.4), "old_robot": Color(1.0, 0.6, 0.2),
}


func _initialize() -> void:
	var terrain := WorldTerrain.new()
	if not terrain._load_cache():
		terrain._generate_grid()
	var w := WorldTerrain._width
	var d := WorldTerrain._depth
	var img := Image.create(w * SCALE, d * SCALE, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.5, 0.8, -0.3).normalized()
	for iz in d:
		for ix in w:
			var i := iz * w + ix
			var n := terrain._grid_normal(ix, iz)
			var shade := clampf(n.dot(light), 0.0, 1.0)
			var a := WorldTerrain._data_a[i]
			var c := Color(0.42, 0.55, 0.3).lerp(Color(0.7, 0.58, 0.42), a.r).lerp(Color(0.3, 0.45, 0.75), a.g)
			c = c * (0.4 + shade * 0.7)
			img.fill_rect(Rect2i(ix * SCALE, iz * SCALE, SCALE, SCALE), c)
	# Boundary contour.
	for iz in range(0, d, 1):
		for ix in range(0, w, 1):
			var x := WorldLayout.MIN_X + ix
			var z := WorldLayout.MIN_Z + iz
			var f := WorldBoundary.field(x, z)
			if absf(f) < 0.6:
				img.fill_rect(Rect2i(ix * SCALE, iz * SCALE, SCALE, SCALE), Color(1, 0.15, 0.15))
	for path in ["res://scenes/levels/meadow.tscn", "res://scenes/levels/mushroom_forest.tscn",
			"res://scenes/levels/forgotten_shrine.tscn", "res://scenes/levels/crystal_garden.tscn"]:
		var state := (load(path) as PackedScene).get_state()
		for i in state.get_node_count():
			var inst := state.get_node_instance(i)
			if inst == null:
				continue
			var kind := inst.resource_path.get_file().get_basename()
			var pos := Vector3.ZERO
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) == &"position":
					pos = state.get_node_property_value(i, p)
			var col: Color = COLORS.get(kind, Color(1, 0.3, 1))
			var px := int((pos.x - WorldLayout.MIN_X) * SCALE)
			var pz := int((pos.z - WorldLayout.MIN_Z) * SCALE)
			var r := 3 if kind == "energy_fragment" else 5
			img.fill_rect(Rect2i(px - r, pz - r, r * 2, r * 2), Color(0, 0, 0))
			img.fill_rect(Rect2i(px - r + 1, pz - r + 1, r * 2 - 2, r * 2 - 2), col)
	var out := ProjectSettings.globalize_path("res://docs/reference/layout_map.png")
	img.save_png(out)
	print("saved ", out)
	quit()
