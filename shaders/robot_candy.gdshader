shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Glossy candy-coated plastic: a facing/edge color ramp (the Blender "Layer Weight -> Color
// Ramp" shell material) under a clear coat with a faint orange-peel texture, a soft warm
// sheen where light wraps round the curve, and a gentle rim so the robot reads against
// busy backgrounds. Used for the pink armor (and the NPC's yellow shell).

uniform vec3 face_color : source_color = vec3(1.0, 0.21, 0.62);
uniform vec3 edge_color : source_color = vec3(0.77, 0.05, 0.53);
uniform float ramp_power = 1.6;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.3;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_gloss : hint_range(0.0, 1.0) = 0.06;
uniform float rim_glow : hint_range(0.0, 1.0) = 0.12;
uniform float sheen_amount : hint_range(0.0, 1.0) = 0.35;
uniform float peel_strength : hint_range(0.0, 1.0) = 0.25;
// Extra brightness while boosting / powered (driven from code per instance).
instance uniform float energy_boost = 0.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), u.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), u.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - facing, ramp_power);
	vec3 col = mix(face_color, edge_color, edge);
	// Very slight tonal drift across the surface, as on real molded plastic.
	float drift = vnoise3(v_local * 9.0);
	col *= 0.97 + drift * 0.06;
	ALBEDO = col;
	ROUGHNESS = roughness_value + (drift - 0.5) * 0.04;
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_gloss;
	// Orange peel: a tiny normal wobble that breaks up reflections the way paint does.
	if (peel_strength > 0.0) {
		vec3 p = v_local * 260.0;
		vec3 g = vec3(vnoise3(p + vec3(0.5, 0.0, 0.0)) - vnoise3(p - vec3(0.5, 0.0, 0.0)),
			vnoise3(p + vec3(0.0, 0.5, 0.0)) - vnoise3(p - vec3(0.0, 0.5, 0.0)),
			vnoise3(p + vec3(0.0, 0.0, 0.5)) - vnoise3(p - vec3(0.0, 0.0, 0.5)));
		vec3 g_view = (VIEW_MATRIX * MODEL_MATRIX * vec4(g, 0.0)).xyz;
		NORMAL = normalize(NORMAL + g_view * 0.035 * peel_strength);
	}
	// Rim keeps the silhouette readable; a little stronger while powered up.
	float rim = pow(1.0 - facing, 4.0);
	EMISSION = face_color * rim * (rim_glow + energy_boost * 0.25);
	// Light-dependent sheen where light grazes the curve (built-in rim lighting).
	RIM = sheen_amount;
	RIM_TINT = 0.55;
}
