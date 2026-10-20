extends SceneTree
## Dev tool: prints the node tree, animations and materials of an imported scene.
## Usage: godot --headless --path . --script res://tools/inspect_scene.gd -- res://path/to/scene.glb


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://assets/characters/pink_robot/pink_robot.glb" if args.is_empty() else args[0]
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Could not load %s" % path)
		quit(1)
		return
	var root := packed.instantiate()
	_print_tree(root, 0)
	var materials := {}
	_collect_materials(root, materials)
	print("MATERIALS: ", materials.keys())
	for player in root.find_children("*", "AnimationPlayer", true, false):
		var ap := player as AnimationPlayer
		print("ANIMATION PLAYER: ", ap.get_path(), " root=", ap.root_node)
		for anim_name in ap.get_animation_list():
			var anim := ap.get_animation(anim_name)
			print("  ANIM %s len=%.3f tracks=%d loop=%d" % [anim_name, anim.length, anim.get_track_count(), anim.loop_mode])
			if anim_name == ap.get_animation_list()[0]:
				for t in mini(anim.get_track_count(), 8):
					print("     track ", anim.track_get_path(t), " type=", anim.track_get_type(t))
	for sk in root.find_children("*", "Skeleton3D", true, false):
		var skel := sk as Skeleton3D
		var names: PackedStringArray = []
		for i in skel.get_bone_count():
			names.append(skel.get_bone_name(i))
		print("SKELETON ", skel.name, " bones=", skel.get_bone_count(), " ", names)
	root.free()
	quit()


func _print_tree(node: Node, depth: int) -> void:
	if depth > 6:
		return
	var extra := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		extra = " surfaces=%d" % (mi.mesh.get_surface_count() if mi.mesh else 0)
	if node is BoneAttachment3D:
		extra = " bone=" + (node as BoneAttachment3D).bone_name
	if node is Node3D:
		extra += " pos=" + str((node as Node3D).position.snapped(Vector3.ONE * 0.001))
	print("  ".repeat(depth), node.name, " <", node.get_class(), ">", extra)
	for child in node.get_children():
		_print_tree(child, depth + 1)


func _collect_materials(node: Node, out: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m:
					out[m.resource_name] = true
	for child in node.get_children():
		_collect_materials(child, out)
