shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Floating holographic interface panel: framed readouts (scrolling text rows, a live graph,
// a radial gauge), scanlines, a slow scan sweep, edge glow and the odd glitch flicker.
// tint (instance) sets the colour; power_level (instance) dims it.

instance uniform vec3 tint = vec3(0.45, 0.85, 1.0);
instance uniform float power_level = 1.0;
uniform float energy = 1.5;

float h(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// Glitch: rare horizontal tears.
	float tear = step(0.985, h(floor(t * 9.0))) * step(abs(uv.y - h(floor(t * 9.0) + 1.0)), 0.04);
	uv.x += tear * 0.03;
	float frame = 1.0 - smoothstep(0.0, 0.012, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	float corner = step(min(uv.x, 1.0 - uv.x), 0.08) * step(min(uv.y, 1.0 - uv.y), 0.08) * frame;
	// Text rows on the left two thirds.
	float row = floor((uv.y + t * 0.03) * 16.0);
	float rf = fract((uv.y + t * 0.03) * 16.0);
	float dash = step(h(row * 7.3 + floor(uv.x * 30.0) * 0.37), 0.7) * step(uv.x, 0.06 + h(row) * 0.5) * step(0.06, uv.x);
	float text = dash * step(0.3, rf) * step(rf, 0.7) * step(uv.y, 0.92) * step(0.08, uv.y);
	// Graph and gauge on the right.
	float gx = (uv.x - 0.62) / 0.32;
	float graph = 0.0;
	if (gx > 0.0 && gx < 1.0 && uv.y > 0.58 && uv.y < 0.9) {
		float gy = 0.74 + sin(gx * 14.0 + t * 2.0) * 0.06 * sin(t * 0.6 + gx * 4.0);
		graph = 1.0 - smoothstep(0.0, 0.01, abs(uv.y - gy));
		graph += step(fract(gx * 8.0), 0.03) * 0.15;
	}
	vec2 gc = (uv - vec2(0.78, 0.3)) * vec2(1.0, 1.0);
	float gr = length(gc);
	float ga = atan(gc.y, gc.x) / 6.2832 + 0.5;
	float gauge = (1.0 - smoothstep(0.0, 0.008, abs(gr - 0.13))) * step(ga, 0.35 + 0.3 * fract(t * 0.07));
	gauge += (1.0 - smoothstep(0.0, 0.006, abs(gr - 0.09))) * 0.4;
	float scan = 0.82 + 0.18 * sin(uv.y * 420.0 + t * 5.0);
	float sweep = (1.0 - smoothstep(0.0, 0.05, abs(fract(t * 0.18) - uv.y))) * 0.35;
	float fl = 1.0 - 0.3 * step(0.93, h(floor(t * 24.0)));
	float level = (text * 0.8 + graph + gauge + frame * 0.8 + corner + sweep + 0.06) * scan * fl;
	ALBEDO = tint * level * energy * power_level;
}
