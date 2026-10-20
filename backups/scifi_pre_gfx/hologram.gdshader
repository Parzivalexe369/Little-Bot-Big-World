shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Holograms: displays, interface panels, and "out of phase" objects in the quantum lab.
// Fresnel-weighted glow, drifting scanlines, a slow sweep band, occasional dropouts and
// a gentle flicker. `fill` controls how solid the faces look (low = wireframe-like ghost).

uniform vec3 holo_color : source_color = vec3(0.35, 0.85, 1.0);
uniform float energy = 1.4;
uniform float fill : hint_range(0.0, 1.0) = 0.35;
uniform float scanline_density = 90.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.15;
uniform float edge_glow = 1.6;
instance uniform float visibility = 1.0;

varying vec3 v_world;
varying vec3 v_local;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float fres = pow(1.0 - facing, 2.0);
	float lines = 0.6 + 0.4 * sin(v_world.y * scanline_density - TIME * 6.0);
	float sweep = smoothstep(0.0, 0.08, 0.08 - abs(fract(v_world.y * 0.35 - TIME * 0.25) - 0.5));
	float t = floor(TIME * 20.0);
	float fl = 1.0 - flicker * step(0.92, fract(sin(t * 91.7) * 4375.85));
	// Local-space box edges glow (reads as a projected wireframe on boxes).
	vec3 a = abs(fract(v_local * 2.0 + 0.5) - 0.5);
	float edge = 1.0 - smoothstep(0.0, 0.03, min(min(a.x + a.y, a.y + a.z), a.x + a.z));
	float level = (fill * lines + fres * edge_glow + sweep * 0.6 + edge * 0.5) * fl * visibility;
	ALBEDO = holo_color * level * energy;
}
