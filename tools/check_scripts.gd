extends SceneTree
## Dev tool: loads every GDScript in the project and reports which ones fail to compile.
## Usage: godot --headless --path . --script res://tools/check_scripts.gd


func _initialize() -> void:
	var failed: PackedStringArray = []
	var files := _collect("res://", [])
	for path: String in files:
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if script == null or not script.can_instantiate() and not path.ends_with("_data.gd"):
			if script == null or not (script as GDScript).is_abstract():
				failed.append(path)
	print("checked %d scripts, %d failed" % [files.size(), failed.size()])
	for f in failed:
		print("  FAILED: ", f)
	quit(1 if failed.size() > 0 else 0)


func _collect(dir_path: String, out: Array) -> Array:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not FileAccess.file_exists(full.path_join(".gdignore")) and name != "addons":
				_collect(full, out)
		elif name.ends_with(".gd") and full != get_script().resource_path:
			out.append(full)
		name = dir.get_next()
	return out
