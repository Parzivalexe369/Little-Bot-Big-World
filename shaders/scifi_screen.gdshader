shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Console/terminal screens: dark glass with a glowing interface: scrolling text rows, a
// live waveform and a status bar. power (instance) dims it; tint sets its colour (from code).

instance uniform float power_level = 1.0;
instance uniform vec3 tint = vec3(0.35, 0.9, 1.0);
uniform float energy = 2.2;

float h(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// Text rows: dashes of varying length scrolling slowly upward.
	float row = floor((uv.y + t * 0.04) * 14.0);
	float col_id = floor(uv.x * 22.0);
	float dash = step(h(row * 13.1 + col_id * 0.7), 0.62) * step(uv.x, 0.15 + h(row) * 0.55);
	float in_row = step(0.25, fract((uv.y + t * 0.04) * 14.0)) * step(fract((uv.y + t * 0.04) * 14.0), 0.7);
	float text = dash * in_row * step(uv.y, 0.62);
	// Waveform in the lower band.
	float wave_y = 0.8 + sin(uv.x * 24.0 + t * 3.0) * 0.05 * sin(t * 0.7 + uv.x * 3.0);
	float wave = (1.0 - smoothstep(0.0, 0.012, abs(uv.y - wave_y))) * step(0.68, uv.y);
	// Status bar.
	float bar = step(0.93, uv.y) * step(uv.x, 0.3 + 0.6 * fract(t * 0.05));
	float frame_line = (1.0 - smoothstep(0.0, 0.01, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y))));
	float scan = 0.85 + 0.15 * sin(uv.y * 300.0 + t * 8.0);
	float glow = (text * 0.9 + wave + bar * 0.7 + frame_line * 0.5) * scan;
	ALBEDO = vec3(0.01, 0.015, 0.02);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	EMISSION = tint * (glow + 0.05) * energy * power_level;
}
