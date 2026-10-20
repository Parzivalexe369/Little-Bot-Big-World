extends SceneTree
## Dev tool: verifies vertex colors / UVs survived the props.glb import.


func _initialize() -> void:
	var packed := load("res://assets/environment/props.glb") as PackedScene
	var root := packed.instantiate()
	for prop_name in ["daisy_a", "grass_a", "rock_moss_a", "root_gate"]:
		var node := root.get_node_or_null(prop_name)
		if node == null:
			print(prop_name, " MISSING")
			continue
		var mi := node as MeshInstance3D
		var arrays := mi.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var gmax := 0.0
		var amax := 0.0
		var rmin := 1.0
		for c in colors:
			gmax = maxf(gmax, c.g)
			amax = maxf(amax, c.a)
			rmin = minf(rmin, c.r)
		print(prop_name, " surfaces=", mi.mesh.get_surface_count(), " colors=", colors.size(), " uvs=", uvs.size(), " sway_max=", gmax, " petal_max=", amax, " ao_min=", rmin, " children=", node.get_child_count(), " aabb=", mi.mesh.get_aabb())
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			print("   mat ", s, " ", m.resource_name if m else "none")
	print("total roots: ", root.get_child_count())
	root.free()
	quit()
