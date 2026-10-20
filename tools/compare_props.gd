extends SceneTree
## Dev tool: compares the bounding box and triangle count of every prop between two GLBs,
## so geometry upgrades can be checked for changed dimensions (stepping stones, colliders).
## Usage: godot --headless --path . --script res://tools/compare_props.gd -- old.glb new.glb


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var old_info := _collect(args[0])
	var new_info := _collect(args[1])
	var worst := 0.0
	for prop_name: String in new_info:
		var n: Dictionary = new_info[prop_name]
		if not old_info.has(prop_name):
			print("NEW   %-22s tris=%6d size=%s" % [prop_name, n["tris"], n["aabb"].size])
			continue
		var o: Dictionary = old_info[prop_name]
		var oa: AABB = o["aabb"]
		var na: AABB = n["aabb"]
		var d := maxf((oa.position - na.position).abs().length(), (oa.end - na.end).abs().length())
		worst = maxf(worst, d / maxf(oa.size.length(), 0.01))
		print("%-28s tris %6d -> %6d  top %.3f -> %.3f  size %s -> %s" % [prop_name, o["tris"], n["tris"], oa.end.y, na.end.y, _v(oa.size), _v(na.size)])
	for prop_name: String in old_info:
		if not new_info.has(prop_name):
			print("MISSING ", prop_name)
	print("worst relative bounds change: %.3f" % worst)
	quit()


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _collect(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read " + path)
		return {}
	var root := doc.generate_scene(state)
	var out := {}
	_walk(root, "", out)
	root.free()
	return out


func _walk(node: Node, prefix: String, out: Dictionary) -> void:
	for child in node.get_children():
		var key := prefix + String(child.name)
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var mesh := (child as MeshInstance3D).mesh
			var tris := 0
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += idx.size() / 3
			out[key] = {"aabb": mesh.get_aabb(), "tris": tris}
		_walk(child, key + "/", out)
