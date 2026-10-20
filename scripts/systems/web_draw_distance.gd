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
## Sun shadow distance in browsers (one orthographic shadow map).
const SHADOW_RANGE := 30.0


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
			var attributes: int = mi.mesh.surface_get_format(s) & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS)
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


## Browsers: the facility's walls, floors and trims (ScifiKit blocks placed directly in an
## area) become one mesh per material and `group`, instead of one draw call per block; in the
## lab's arrival hall that is several hundred. Their panel shader maps in world space, so the
## look is unchanged. The originals are only hidden, so their collision stays. `group_of`
## (block -> int) keeps blocks apart that need their own shader settings later (the lab
## powers rooms on one by one). Returns {[material, group]: merged MeshInstance3D}.
static func merge_blocks(area: Node3D, group_of: Callable) -> Dictionary:
	var tools := {}
	var blocks: Array[MeshInstance3D] = []
	for child in area.get_children():
		var mi := child as MeshInstance3D
		# Named blocks are kept apart: scripts look them up.
		if mi == null or not mi.has_meta(&"block") or not mi.visible or not String(mi.name).begins_with("@"):
			continue
		var key := [mi.material_override, int(group_of.call(mi))]
		var st: SurfaceTool = tools.get(key)
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		for s in mi.mesh.get_surface_count():
			st.append_from(mi.mesh, s, mi.transform)
		blocks.append(mi)
	var merged := {}
	for key: Array in tools:
		var out := MeshInstance3D.new()
		out.name = "MergedBlocks"
		out.mesh = (tools[key] as SurfaceTool).commit()
		out.material_override = key[0]
		area.add_child(out)
		merged[key] = out
	for mi in blocks:
		mi.visible = false
	return merged


## Browsers: lamps and glowing devices (omni and spot lights) cast no shadows. An omni
## light's shadow redraws every caster near it six times, one per cube face, even while the
## lamp is off screen: in the garden the three such lights cost ~170-350 draw calls a frame.
static func no_local_shadows(root: Node) -> void:
	for node in root.find_children("*", "Light3D", true, false):
		if not node is DirectionalLight3D:
			(node as Light3D).shadow_enabled = false


## Touch-screen browsers: only `keep` (the robot) casts a sun shadow. The shadow map then
## redraws a few dozen robot parts instead of every nearby tree, rock and building (100-200
## draw calls in the garden), and the robot still sits on the ground.
static func only_shadows_from(root: Node, keep: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if not keep.is_ancestor_of(node):
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Browsers: parts smaller than `max_size` metres cast no shadows (bolts and trims inside a
## bigger silhouette; each part is a draw call in every shadow cascade).
static func no_tiny_shadows(root: Node, max_size: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh and (mi.global_transform * mi.get_aabb()).size.length() < max_size:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
