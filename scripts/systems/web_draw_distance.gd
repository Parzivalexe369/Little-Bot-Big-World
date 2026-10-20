class_name WebDrawDistance
extends RefCounted
## Browsers only: every object drawn costs a WebGL draw call, and distant level objects made up
## most of the garden's ~2,500 a frame (a sleeping robot alone is 190 parts, drawn from the far
## side of the meadow). Each level object without a draw distance gets one that grows with its
## overall size, judged per object so a many-part robot disappears as a whole; energy
## fragments stay visible from further away, and bolt-sized parts cast no shadows.

const MIN_RANGE := 45.0
const MAX_RANGE := 160.0
const FRAGMENT_RANGE := 120.0
const TINY_PART := 0.5


static func apply(levels: Node, min_range := MIN_RANGE) -> void:
	for level: Node in levels.get_children():
		for obj: Node in level.get_children():
			_apply_object(obj, min_range)


static func _apply_object(obj: Node, min_range: float) -> void:
	var parts: Array[GeometryInstance3D] = []
	if obj is GeometryInstance3D:
		parts.append(obj as GeometryInstance3D)
	for g in obj.find_children("*", "GeometryInstance3D", true, false):
		parts.append(g as GeometryInstance3D)
	var todo: Array[GeometryInstance3D] = []
	var box := AABB()
	for g in parts:
		var part_box := g.global_transform * g.get_aabb()
		if part_box.size.length() < TINY_PART:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if g.visibility_range_end > 0.0:
			continue
		box = part_box if todo.is_empty() else box.merge(part_box)
		todo.append(g)
	if todo.is_empty():
		return
	var view_range := clampf(20.0 + box.size.length() * 8.0, min_range, MAX_RANGE)
	if obj is EnergyFragment:
		view_range = maxf(view_range, FRAGMENT_RANGE)
	for g in todo:
		g.visibility_range_end = view_range
		g.visibility_range_end_margin = view_range * 0.1


## Browsers: bakes a static many-part model (parts that never move relative to `root`) into
## one mesh per material, one draw call each instead of one per part. Materials are kept as
## they are, so animated materials (glowing eyes) still work.
static func merge_static(root: Node3D) -> void:
	var inv := root.global_transform.affine_inverse()
	var tools := {}
	var parts: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return
		parts.append(mi)
	if parts.size() < 2:
		return
	for mi in parts:
		# Skinned parts are drawn in their skeleton's space (the skeleton is in its rest pose).
		var space := mi.global_transform
		if mi.skin != null and mi.has_node(mi.skeleton):
			space = (mi.get_node(mi.skeleton) as Node3D).global_transform
		var xf := inv * space
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			# Surfaces merge only with the same material and vertex attributes.
			var attributes: int = mi.mesh.surface_get_format(s) & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_COLOR)
			var key := [mat, attributes]
			var st: SurfaceTool = tools.get(key)
			if st == null:
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
			st.append_from(mi.mesh, s, xf)
	var merged := ArrayMesh.new()
	for key: Array in tools:
		(tools[key] as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, key[0])
	var out := MeshInstance3D.new()
	out.name = "MergedModel"
	out.mesh = merged
	root.add_child(out)
	for mi in parts:
		mi.queue_free()


## Browsers: parts smaller than `max_size` metres cast no shadows (bolts and trims inside a
## bigger silhouette; each part is a draw call in every shadow cascade).
static func no_tiny_shadows(root: Node, max_size: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh and (mi.global_transform * mi.get_aabb()).size.length() < max_size:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
