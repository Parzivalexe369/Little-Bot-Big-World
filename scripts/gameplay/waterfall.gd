class_name Waterfall
extends Device
## A dry rock face that becomes a waterfall when its area is restored: a flowing ribbon,
## mist, a rising pool and the sound of water.

@export var active_flag: StringName = &"shrine_restored"
@export var height := 14.0
@export var width := 3.0
@export var pool_radius := 6.0
@export var pool_id := "shrine_pool"

var _ribbon: MeshInstance3D
var _ribbon_mat: ShaderMaterial
var _mist: GPUParticles3D
var _pool: MeshInstance3D
var _audio: AudioStreamPlayer3D
var _flow := 0.0


func _build() -> void:
	PropLibrary.place(self, "falls_rock", Vector3(0, 0, -2.6), 0.0, 1.0, true)
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _make_ribbon()
	_ribbon_mat = ShaderMaterial.new()
	_ribbon_mat.shader = preload("res://shaders/waterfall.gdshader")
	_ribbon_mat.set_shader_parameter("noise_tex", PropLibrary.NOISE_TEX)
	_ribbon_mat.set_shader_parameter("length_ratio", height / width)
	_ribbon.material_override = _ribbon_mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)
	_mist = FxFactory.ambient_motes(Color(0.85, 0.95, 1.0, 0.6), 40, Vector3(2.5, 1.0, 2.0), 0.6, 0.8, 2.5)
	_mist.position = Vector3(0, 0.8, 1.2)
	add_child(_mist)
	_audio = Audio.make_loop_3d(self, &"waterfall", -60.0, 6.0, 45.0)
	GameState.flag_changed.connect(_on_flag)


func _make_ribbon() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 16
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for r in rows + 1:
		var t := float(r) / rows
		var y := height * (1.0 - t)
		var z := -1.6 + sin(t * PI * 0.5) * 2.2 + t * t * 0.6
		for c in 3:
			var x := (c / 2.0 - 0.5) * width * (1.0 + t * 0.5)
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(c / 2.0, t * height / width))
	for r in rows:
		for c in 2:
			var a := r * 3 + c
			var b := a + 1
			var d := a + 3
			var e := d + 1
			for idx in [a, d, b, b, d, e]:
				st.set_uv(uvs[idx])
				st.set_normal(Vector3(0, 0.3, 1).normalized())
				st.add_vertex(verts[idx])
	return st.commit()


func _restore_state() -> void:
	_flow = 1.0 if GameState.has_flag(active_flag) else 0.0
	_apply_flow(_flow)


func _on_flag(flag: StringName, value: Variant) -> void:
	if flag == active_flag and value:
		var tween := create_tween()
		tween.tween_interval(2.0)
		tween.tween_method(_apply_flow, 0.0, 1.0, 5.0)


func _apply_flow(t: float) -> void:
	_flow = t
	_ribbon_mat.set_shader_parameter("flow", t)
	_ribbon.visible = t > 0.001
	_mist.emitting = t > 0.3
	if _audio:
		_audio.volume_db = lerpf(-60.0, -6.0, sqrt(t))
