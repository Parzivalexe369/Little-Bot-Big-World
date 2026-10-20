shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Expanding scanner shell: bright at the silhouette, almost invisible head-on.

uniform vec3 color : source_color = vec3(0.35, 0.95, 1.0);
uniform float fade = 1.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - facing, 3.0);
	float bands = 0.6 + 0.4 * sin(UV.y * 120.0);
	ALBEDO = color;
	ALPHA = 1.0;
	EMISSION = vec3(0.0);
	ALBEDO = color * rim * bands * fade * 0.9;
}
