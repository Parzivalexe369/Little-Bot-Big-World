class_name WaterBodies
extends Node3D
## Ponds and the ravine stream. Pond surfaces are solid for the robot (it hovers across
## them, leaving ripples) while the camera passes through. The stream sits deep in the
## ravine, guarded by the bridge's safety rails.

const WATER_SHADER := preload("res://shaders/water.gdshader")

var material: ShaderMaterial


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("noise_tex", PropLibrary.NOISE_TEX)
	for pond: Dictionary in WorldLayout.PONDS:
		_build_pond(pond)
	_build_stream()


func _build_pond(pond: Dictionary) -> void:
	var c: Vector2 = pond["center"]
	var r: float = pond["radius"]
	var level := WorldTerrain.pond_level(pond["id"])
	var mesh := CylinderMesh.new()
	mesh.top_radius = r + 2.2
	mesh.bottom_radius = r + 2.2
	mesh.height = 0.02
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.name = "Pond_" + String(pond["id"])
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c.x, level, c.y)
	add_child(mi)
	mi.set_instance_shader_parameter("edge_radius", r + 2.2)
	# Low mist hanging over the water (visible when volumetric fog is on).
	_add_mist(Vector3(c.x, level + 0.6, c.y), Vector3(r * 2.4, 1.8, r * 2.4), 0.09)
	# The robot skims over the water: a thin collider on the player-only layer.
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 7
	body.collision_mask = 0
	body.position = Vector3(c.x, level - 0.05, c.y)
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r + 1.0
	cyl.height = 0.1
	shape.shape = cyl
	body.add_child(shape)
	var audio := Audio.make_loop_3d(mi, &"water_lap", -14.0, 5.0, 28.0)
	if audio:
		audio.position = Vector3.ZERO


func _build_stream() -> void:
	var pts := WorldLayout.RAVINE_POINTS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var level := -1.0 - WorldLayout.RAVINE_DEPTH + 0.55
	var half := WorldLayout.RAVINE_HALF_WIDTH - 1.0
	var samples: Array[Vector2] = []
	for i in pts.size() - 1:
		var steps := int(pts[i].distance_to(pts[i + 1]) / 2.0) + 1
		for s in steps:
			samples.append(pts[i].lerp(pts[i + 1], float(s) / steps))
	samples.append(pts[pts.size() - 1])
	var dist := 0.0
	for i in samples.size() - 1:
		var a := samples[i]
		var b := samples[i + 1]
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		var a0 := Vector3(a.x + n.x * half, level, a.y + n.y * half)
		var a1 := Vector3(a.x - n.x * half, level, a.y - n.y * half)
		var b0 := Vector3(b.x + n.x * half, level, b.y + n.y * half)
		var b1 := Vector3(b.x - n.x * half, level, b.y - n.y * half)
		var d2 := dist + a.distance_to(b)
		for v: Array in [[a0, Vector2(0, dist)], [b0, Vector2(0, d2)], [a1, Vector2(1, dist)], [a1, Vector2(1, dist)], [b0, Vector2(0, d2)], [b1, Vector2(1, d2)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(v[0])
		dist = d2
	var mi := MeshInstance3D.new()
	mi.name = "Stream"
	mi.mesh = st.commit()
	var stream_mat := material.duplicate() as ShaderMaterial
	stream_mat.set_shader_parameter("flow", Vector2(0.0, 0.5))
	mi.material_override = stream_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Mist pooling in the ravine along the stream.
	for i in range(0, samples.size() - 1, 8):
		var a := samples[i]
		var b := samples[mini(i + 8, samples.size() - 1)]
		var holder_mist := _add_mist(Vector3((a.x + b.x) * 0.5, level + 1.2, (a.y + b.y) * 0.5),
			Vector3(WorldLayout.RAVINE_HALF_WIDTH * 2.0, 3.0, a.distance_to(b) + 6.0), 0.07)
		holder_mist.rotation.y = atan2(b.x - a.x, b.y - a.y)
	var mid := WorldLayout.BRIDGE_START.lerp(WorldLayout.BRIDGE_END, 0.5)
	var holder := Node3D.new()
	add_child(holder)
	holder.position = Vector3(mid.x, level, mid.y)
	Audio.make_loop_3d(holder, &"stream", -8.0, 8.0, 50.0)


func _add_mist(center: Vector3, size: Vector3, density: float) -> FogVolume:
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fog.size = size
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = Color(0.9, 0.94, 0.95)
	fm.height_falloff = 0.6
	fm.edge_fade = 0.8
	fog.material = fm
	fog.position = center
	add_child(fog)
	return fog
