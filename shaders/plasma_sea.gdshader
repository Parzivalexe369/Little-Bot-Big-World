shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// The alien reactor's plasma sea: slow rolling swells (vertex), domain-warped currents,
// bright incandescent veins between darker cooling crust, hot upwellings that pulse, and a
// glossy surface that catches the cavern lights. Mostly emissive, opaque.

uniform vec3 hot_color : source_color = vec3(0.55, 1.0, 0.8);
uniform vec3 mid_color : source_color = vec3(0.1, 0.62, 0.5);
uniform vec3 crust_color : source_color = vec3(0.015, 0.05, 0.05);
uniform float energy = 1.9;
uniform float wave_height = 0.6;
uniform float flow_speed = 0.035;
uniform float pulse = 0.0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_world;

float waves(vec2 p, float t) {
	return sin(p.x * 0.11 + t * 0.6) * 0.5 + sin(p.y * 0.13 - t * 0.45) * 0.35 + sin((p.x + p.y) * 0.21 + t * 0.9) * 0.15;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = waves(w.xz, TIME);
	VERTEX.y += h * wave_height;
	float e = 0.5;
	float hx = waves(w.xz + vec2(e, 0.0), TIME) - h;
	float hz = waves(w.xz + vec2(0.0, e), TIME) - h;
	NORMAL = normalize(vec3(-hx * wave_height / e, 1.0, -hz * wave_height / e));
	v_world = w;
}

void fragment() {
	vec2 p = v_world.xz * 0.018;
	float t = TIME * flow_speed;
	// Domain warp: currents that drift and fold.
	vec2 warp = vec2(texture(noise_tex, p * 0.7 + vec2(t, -t * 0.6)).r, texture(noise_tex, p * 0.7 + vec2(0.37 - t * 0.8, 0.19 + t)).r) - 0.5;
	vec2 q = p + warp * 0.9;
	float n1 = texture(noise_tex, q * 1.3 + vec2(t * 1.6, t)).r;
	float n2 = texture(noise_tex, q * 3.1 - vec2(t * 2.3, -t * 1.1)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	// Veins: thin bright lines where the noise crosses mid level.
	float vein = (1.0 - smoothstep(0.0, 0.02, abs(n - 0.5))) * smoothstep(0.35, 0.6, n2);
	float crust = smoothstep(0.4, 0.58, n2 * 0.55 + n1 * 0.45);
	float up = smoothstep(0.7, 0.9, n1) * (0.7 + 0.3 * sin(TIME * 1.3 + n2 * 9.0));
	vec3 col = mix(mid_color, crust_color, crust);
	col = mix(col, hot_color, max(vein * (1.0 - crust * 0.6), up));
	float glow = (0.22 + vein * 1.8 + up * 1.5) * (1.0 - crust * 0.85) * (1.0 + pulse);
	ALBEDO = col * 0.25;
	ROUGHNESS = mix(0.18, 0.7, crust);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = col * glow * energy;
}
