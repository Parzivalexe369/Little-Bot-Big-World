shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Falling water ribbon: scrolling streaks, foamy edges, revealed from the top as it starts.

uniform float flow : hint_range(0.0, 1.0) = 1.0;
uniform float length_ratio = 4.7;
uniform vec3 water_color : source_color = vec3(0.55, 0.78, 0.9);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

void fragment() {
	float v = UV.y;
	float total = length_ratio;
	float reveal = 1.0 - smoothstep(flow * total - 0.6, flow * total, v);
	vec2 uv = vec2(UV.x * 1.5, v * 0.6 - TIME * 1.6);
	float n = texture(noise_tex, uv).r;
	float n2 = texture(noise_tex, uv * 2.3 + vec2(0.3, -TIME * 0.7)).r;
	float streak = smoothstep(0.35, 0.75, n * 0.7 + n2 * 0.5);
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	vec3 col = mix(water_color, foam_color, streak * 0.7 + (1.0 - edge) * 0.4);
	ALBEDO = col;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	EMISSION = foam_color * streak * 0.15;
	ALPHA = clamp((0.55 + streak * 0.4) * edge * reveal, 0.0, 1.0);
}
