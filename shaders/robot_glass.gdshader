shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Dark face visor: mostly see-through when viewed head-on (so the eye display shows),
// mirror-like at grazing angles. Mirrors the Fresnel mix used in the Blender material.

uniform vec3 tint : source_color = vec3(0.012, 0.013, 0.016);
uniform float head_on_alpha : hint_range(0.0, 1.0) = 0.32;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.96;
uniform float fresnel_power = 2.2;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = pow(1.0 - facing, fresnel_power);
	ALBEDO = tint;
	METALLIC = 0.0;
	ROUGHNESS = 0.035;
	// A real visor reflects like glass (~4%), not a mirror; Fresnel does the rest.
	SPECULAR = 0.55;
	CLEARCOAT = 0.6;
	CLEARCOAT_ROUGHNESS = 0.02;
	ALPHA = mix(head_on_alpha, edge_alpha, f);
}
