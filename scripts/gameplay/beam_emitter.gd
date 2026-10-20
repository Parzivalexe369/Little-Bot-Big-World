class_name BeamEmitter
extends Device
## A sun crystal set in stone that casts a beam of light forward (local -Z).
## The beam reflects off BeamMirrors and wakes BeamReceivers it touches.

const MAX_BOUNCES := 6
const MAX_LENGTH := 70.0

@export var beam_color := Color(1.0, 0.86, 0.55)
@export var prop_name := "sun_emitter"
## Only shine once this flag is set (empty = always).
@export var requires_flag: StringName = &""
@export var lens_height := 1.5

var _segments: Array[MeshInstance3D] = []
var _impact: GPUParticles3D
var _lit := false
var _query: PhysicsRayQueryParameters3D


func _build() -> void:
	var prop := PropLibrary.place(self, prop_name, Vector3.ZERO, 180.0, 1.0, true)
	prop.name = "Prop"
	for i in MAX_BOUNCES + 1:
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 1.0
		cyl.radial_segments = 8
		cyl.rings = 1
		seg.mesh = cyl
		seg.material_override = BeamSegments.beam_material(beam_color)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.top_level = true
		seg.visible = false
		add_child(seg)
		_segments.append(seg)
	_impact = FxFactory.sparkles(beam_color, 14, 0.25, 0.1)
	_impact.top_level = true
	add_child(_impact)
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = 1 | (1 << 6)
	_query.collide_with_areas = false
	if requires_flag != &"":
		GameState.flag_changed.connect(func(_f: StringName, _v: Variant) -> void: _update_lit())
	_update_lit()


func _update_lit() -> void:
	_lit = requires_flag == &"" or GameState.has_flag(requires_flag)
	PropLibrary.set_power(get_node("Prop"), 1.0 if _lit else 0.0)
	if not _lit:
		for seg in _segments:
			seg.visible = false
		_impact.emitting = false


func _physics_process(_delta: float) -> void:
	if not _lit:
		return
	var origin := global_position + Vector3.UP * lens_height - global_basis.z * 0.9
	var dir := -global_basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var space := get_world_3d().direct_space_state
	var used := 0
	var end_point := origin
	for bounce in MAX_BOUNCES + 1:
		_query.from = origin
		_query.to = origin + dir * MAX_LENGTH
		var hit := space.intersect_ray(_query)
		var stop := origin + dir * MAX_LENGTH
		var collider: Object = null
		if not hit.is_empty():
			stop = hit["position"]
			collider = hit["collider"]
		BeamSegments.place_segment(_segments[used], origin, stop)
		_segments[used].visible = true
		used += 1
		end_point = stop
		if collider == null:
			break
		var owner_node := _find_owner(collider as Node)
		if owner_node is BeamReceiver:
			(owner_node as BeamReceiver).receive_beam(get_physics_process_delta_time())
			break
		if owner_node is BeamMirror:
			var mirror := owner_node as BeamMirror
			var n := mirror.mirror_normal()
			if dir.dot(n) >= 0.0:
				break
			dir = dir.bounce(n)
			dir.y = 0.0
			dir = dir.normalized()
			origin = stop + dir * 0.05
			continue
		break
	for i in range(used, _segments.size()):
		_segments[i].visible = false
	_impact.global_position = end_point
	_impact.emitting = true


func _find_owner(node: Node) -> Node:
	while node != null:
		if node is BeamMirror or node is BeamReceiver:
			return node
		node = node.get_parent()
	return null
