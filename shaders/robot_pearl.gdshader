shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Pearl-white shell: warm white base with a faint pearlescent hue shift toward grazing
// angles (pink to soft lilac, echoing the armor), clear coat, subtle molded-plastic drift.

uniform vec3 base_color : source_color = vec3(0.9, 0.9, 0.92);
uniform vec3 pearl_tint_a : source_color = vec3(1.0, 0.9, 0.94);
uniform vec3 pearl_tint_b : source_color = vec3(0.88, 0.9, 1.0);
uniform float pearl_amount : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.2;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float t = pow(1.0 - facing, 1.5);
	vec3 pearl = mix(pearl_tint_a, pearl_tint_b, smoothstep(0.25, 0.9, t + sin(v_local.y * 14.0 + v_local.x * 9.0) * 0.08));
	ALBEDO = base_color * mix(vec3(1.0), pearl, pearl_amount * (0.4 + 0.6 * t));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = 0.07;
	RIM = 0.2;
	RIM_TINT = 0.7;
}
