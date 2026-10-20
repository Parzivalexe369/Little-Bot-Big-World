shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded, shadows_disabled;
// Overlay applied to scanned objects: pulsing rim glow that fades out.

uniform vec3 color : source_color = vec3(0.4, 0.95, 1.0);
uniform float strength = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.7 + 0.3 * sin(TIME * 8.0);
	ALBEDO = color * (rim * 1.4 + 0.12) * strength * pulse;
}
