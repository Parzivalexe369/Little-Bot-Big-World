shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Accretion disk around the quantum lab's singularity: spiral streams of glowing matter,
// hot violet-white at the inner edge cooling to blue at the rim, brighter on the side
// turning toward the viewer. `spin` is advanced from code so it stops when time is frozen.

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float inner = 0.2;
uniform float outer = 0.5;
uniform vec3 hot : source_color = vec3(1.0, 0.92, 1.0);
uniform vec3 warm : source_color = vec3(0.95, 0.45, 0.85);
uniform vec3 cool : source_color = vec3(0.3, 0.38, 1.0);
uniform float energy = 1.4;
uniform float spin = 0.0;

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c);
	if (r < inner * 0.9 || r > outer) {
		discard;
	}
	float t = clamp((r - inner) / (outer - inner), 0.0, 1.0);
	float a = atan(c.y, c.x);
	float arm = a + log(max(r, 0.01)) * 3.5 + spin / (r * 6.0 + 0.4);
	float n1 = texture(noise_tex, vec2(arm * 0.159 * 2.0, r * 2.2)).r;
	float n2 = texture(noise_tex, vec2(arm * 0.159 * 5.0 + 0.3, r * 6.0 - spin * 0.05)).r;
	float streams = smoothstep(0.3, 0.8, n1 * 0.6 + n2 * 0.4);
	vec3 col = mix(hot, warm, smoothstep(0.0, 0.35, t));
	col = mix(col, cool, smoothstep(0.35, 1.0, t));
	float bright = pow(1.0 - t, 1.6) * (0.35 + streams * 1.1);
	bright *= smoothstep(0.0, 0.04, r - inner * 0.9) * (1.0 - smoothstep(0.82, 1.0, t));
	float doppler = 0.55 + 0.45 * (0.5 + 0.5 * sin(a));
	ALBEDO = col * bright * doppler * energy;
}
