class_name AtmosphereController
extends Node
## Owns the WorldEnvironment and sun. Smoothly blends lighting, fog and sky between
## per-area moods as the robot travels, and brightens each area as it is restored.

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const NOISE_TEX := preload("res://materials/noise_tex.tres")

## Mood per area: dormant values, plus a restored variant blended by restoration level.
const MOODS := {
	&"meadow": {
		"sun": Color(1.0, 0.91, 0.76), "sun_energy": 1.35, "ambient": Color(0.62, 0.7, 0.78), "ambient_energy": 0.75,
		"fog": Color(0.74, 0.82, 0.86), "fog_density": 0.003, "sky_top": Color(0.34, 0.56, 0.86),
		"sky_horizon": Color(0.84, 0.87, 0.85), "glow": Color(1.0, 0.86, 0.62), "clouds": 0.45, "saturation": 0.92,
		"vol_fog": 0.004, "shafts": 1.0,
		"restored": {"sun_energy": 1.5, "fog_density": 0.0018, "saturation": 1.04, "sky_top": Color(0.3, 0.56, 0.92),
			"vol_fog": 0.0025},
	},
	&"forest": {
		"sun": Color(0.92, 0.95, 0.8), "sun_energy": 0.85, "ambient": Color(0.36, 0.5, 0.46), "ambient_energy": 0.6,
		"fog": Color(0.38, 0.48, 0.44), "fog_density": 0.011, "sky_top": Color(0.3, 0.45, 0.5),
		"sky_horizon": Color(0.5, 0.6, 0.55), "glow": Color(0.9, 1.0, 0.8), "clouds": 0.6, "saturation": 0.88,
		"vol_fog": 0.012, "shafts": 1.6,
		"restored": {"sun_energy": 1.1, "fog_density": 0.006, "saturation": 1.04, "fog": Color(0.42, 0.56, 0.52),
			"vol_fog": 0.009},
	},
	&"shrine": {
		"sun": Color(1.0, 0.82, 0.6), "sun_energy": 1.3, "ambient": Color(0.7, 0.64, 0.58), "ambient_energy": 0.7,
		"fog": Color(0.84, 0.76, 0.66), "fog_density": 0.0038, "sky_top": Color(0.42, 0.52, 0.78),
		"sky_horizon": Color(0.96, 0.84, 0.68), "glow": Color(1.0, 0.75, 0.5), "clouds": 0.4, "saturation": 0.88,
		"vol_fog": 0.005, "shafts": 1.2,
		"restored": {"sun_energy": 1.45, "saturation": 1.04, "fog_density": 0.0024, "vol_fog": 0.0035},
	},
	&"garden": {
		"sun": Color(1.0, 0.94, 0.98), "sun_energy": 1.15, "ambient": Color(0.68, 0.68, 0.76), "ambient_energy": 0.75,
		"fog": Color(0.72, 0.7, 0.8), "fog_density": 0.0038, "sky_top": Color(0.36, 0.38, 0.78),
		"sky_horizon": Color(0.86, 0.8, 0.92), "glow": Color(0.95, 0.8, 1.0), "clouds": 0.35, "saturation": 0.86,
		"vol_fog": 0.006, "shafts": 1.1,
		"restored": {"sun_energy": 1.3, "saturation": 1.03, "fog_density": 0.0024, "sky_horizon": Color(0.92, 0.84, 0.94),
			"vol_fog": 0.004},
	},
}

var environment: Environment
var camera_attributes: CameraAttributesPractical
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var focus: Node3D

var _current := {}
var _restore := {&"meadow": 0.0, &"forest": 0.0, &"shrine": 0.0, &"garden": 0.0}
var _override_weight := 0.0
var _override := {}
var _sky_sent := {}


func setup(world_environment: WorldEnvironment, sun_light: DirectionalLight3D) -> void:
	sun = sun_light
	environment = Environment.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_noise", NOISE_TEX)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.7
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.5
	environment.ssao_light_affect = 0.15
	# Bounce light: sunlit grass tints the undersides of rocks and trunks.
	environment.ssil_radius = 5.0
	environment.ssil_intensity = 0.9
	environment.ssil_sharpness = 0.98
	environment.ssil_normal_rejection = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 1.15
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(1, 0.6)
	environment.set_glow_level(2, 0.9)
	environment.set_glow_level(3, 0.7)
	environment.set_glow_level(4, 0.4)
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.25
	environment.fog_aerial_perspective = 0.2
	environment.fog_sky_affect = 0.25
	environment.fog_height = 12.0
	environment.fog_height_density = 0.0
	# Volumetric fog carries the sun shafts through the canopy and halos round practical lights.
	environment.volumetric_fog_albedo = Color(0.92, 0.94, 0.96)
	environment.volumetric_fog_anisotropy = 0.45
	environment.volumetric_fog_length = 90.0
	environment.volumetric_fog_detail_spread = 2.0
	environment.volumetric_fog_ambient_inject = 0.15
	environment.volumetric_fog_sky_affect = 0.0
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.volumetric_fog_temporal_reprojection_amount = 0.9
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.04
	environment.adjustment_color_correction = _grade_texture()
	world_environment.environment = environment
	camera_attributes = CameraAttributesPractical.new()
	camera_attributes.dof_blur_far_distance = 110.0
	camera_attributes.dof_blur_far_transition = 90.0
	camera_attributes.dof_blur_amount = 0.05
	world_environment.camera_attributes = camera_attributes

	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.4
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	# Tighter near cascades keep contact shadows under the robot and props crisp.
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_fade_start = 0.85
	if OS.has_feature("web"):
		# Browsers: two cascades (each one redraws every shadow caster), the near one ~9 m.
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.2
	_current = MOODS[&"meadow"].duplicate()
	apply_quality()
	Settings.changed.connect(apply_quality)


func apply_quality() -> void:
	var q := Settings.quality_params()
	sun.directional_shadow_max_distance = minf(q["shadow_distance"], 45.0) if OS.has_feature("web") else q["shadow_distance"]
	environment.ssao_enabled = q["ssao"]
	environment.glow_enabled = q["glow"]
	environment.ssr_enabled = q["ssr"]
	environment.ssil_enabled = q["ssil"]
	var ssil_q: int = q["ssil_quality"]
	RenderingServer.environment_set_ssil_quality(ssil_q as RenderingServer.EnvironmentSSILQuality, true, 0.5, 2 if ssil_q == 0 else 4, 50.0, 300.0)
	environment.volumetric_fog_enabled = q["fog_volumetric"]
	camera_attributes.dof_blur_far_enabled = q["dof"]
	RenderingServer.directional_shadow_atlas_set_size(q["shadow_size"], true)
	var filter: int = q["shadow_filter"]
	RenderingServer.directional_soft_shadow_filter_set_quality(filter as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter as RenderingServer.ShadowQuality)


## Gentle per-channel grade: slightly cooler, deeper shadows and warm highlight roll-off.
## (A restrained S-curve, not a teal-orange look.)
static func _grade_texture() -> GradientTexture1D:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
	g.colors = PackedColorArray([Color(0.0, 0.004, 0.012), Color(0.165, 0.174, 0.188), Color(0.502, 0.5, 0.494),
		Color(0.836, 0.826, 0.806), Color(1.0, 0.988, 0.96)])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


func set_restoration(area: StringName, level: float) -> void:
	_restore[area] = clampf(level, 0.0, 1.0)


## Temporarily pushes the mood toward custom values (used by cinematics). weight 0..1.
func set_override(values: Dictionary, weight: float) -> void:
	_override = values
	_override_weight = clampf(weight, 0.0, 1.0)


func _process(delta: float) -> void:
	if environment == null or focus == null:
		return
	var p := Vector2(focus.global_position.x, focus.global_position.z)
	var weights := WorldLayout.area_weights(p)
	var target := _blend_moods(weights)
	if _override_weight > 0.0:
		for key: String in _override:
			if target.has(key):
				target[key] = _lerp_value(target[key], _override[key], _override_weight)
	var k := 1.0 - exp(-delta * 1.2)
	for key: String in target:
		_current[key] = _lerp_value(_current.get(key, target[key]), target[key], k)
	_apply(_current)


func snap() -> void:
	if focus == null:
		return
	var p := Vector2(focus.global_position.x, focus.global_position.z)
	_current = _blend_moods(WorldLayout.area_weights(p))
	_apply(_current)


func _blend_moods(weights: Dictionary) -> Dictionary:
	var out := {}
	for area: StringName in MOODS:
		var w: float = weights.get(area, 0.0)
		if w <= 0.0001:
			continue
		var mood: Dictionary = MOODS[area].duplicate()
		var restored: Dictionary = mood["restored"]
		var r: float = _restore[area]
		for key: String in restored:
			mood[key] = _lerp_value(mood[key], restored[key], r)
		for key: String in mood:
			if key == "restored":
				continue
			var v: Variant = mood[key]
			if out.has(key):
				out[key] = _add_value(out[key], v, w)
			else:
				out[key] = _scale_value(v, w)
	return out


func _apply(m: Dictionary) -> void:
	sun.light_color = m["sun"]
	sun.light_energy = m["sun_energy"]
	environment.ambient_light_color = m["ambient"]
	environment.ambient_light_energy = m["ambient_energy"]
	environment.fog_light_color = m["fog"]
	environment.fog_density = m["fog_density"]
	environment.adjustment_saturation = m["saturation"]
	environment.volumetric_fog_density = m["vol_fog"]
	sun.light_volumetric_fog_energy = m["shafts"]
	_sky_param("top_color", m["sky_top"])
	_sky_param("horizon_color", m["sky_horizon"])
	_sky_param("ground_color", (m["fog"] as Color).darkened(0.25))
	_sky_param("sun_glow_color", m["glow"])
	_sky_param("cloud_coverage", m["clouds"])


## Sky values are only re-sent when they change visibly: each change re-renders the sky's
## reflection map, and the mood blend nudges them a little every frame.
func _sky_param(param: String, value: Variant) -> void:
	var last: Variant = _sky_sent.get(param)
	if last != null and _nearly(last, value):
		return
	_sky_sent[param] = value
	sky_material.set_shader_parameter(param, value)


static func _nearly(a: Variant, b: Variant) -> bool:
	if a is Color:
		var ca := a as Color
		var cb := b as Color
		return absf(ca.r - cb.r) < 0.003 and absf(ca.g - cb.g) < 0.003 and absf(ca.b - cb.b) < 0.003 and absf(ca.a - cb.a) < 0.003
	return absf(float(a) - float(b)) < 0.002


func _lerp_value(a: Variant, b: Variant, t: float) -> Variant:
	if a is Color:
		return (a as Color).lerp(b, t)
	return lerpf(a, b, t)


func _scale_value(v: Variant, w: float) -> Variant:
	if v is Color:
		var c := v as Color
		return Color(c.r * w, c.g * w, c.b * w, 1.0)
	return float(v) * w


func _add_value(acc: Variant, v: Variant, w: float) -> Variant:
	if acc is Color:
		var a := acc as Color
		var c := v as Color
		return Color(a.r + c.r * w, a.g + c.g * w, a.b + c.b * w, 1.0)
	return float(acc) + float(v) * w
