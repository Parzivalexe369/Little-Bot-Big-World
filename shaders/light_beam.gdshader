shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Soft glowing beam: bright core, fading edges, gentle flowing shimmer.

uniform vec3 color : source_color = vec3(1.0, 0.9, 0.6);
uniform float intensity = 2.2;

void fragment() {
	float edge = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	float flow = 0.8 + 0.2 * sin(UV.y * 40.0 - TIME * 6.0);
	ALBEDO = color * edge * intensity * flow;
}
