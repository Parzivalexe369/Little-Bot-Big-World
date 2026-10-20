shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;
// Dimensional portal / spatial distortion disc: swirls what is behind it (screen texture),
// tints toward the portal color near the middle, with a bright rim and drifting sparks.
// Use on a quad/disc mesh; `open` (0..1) grows it from nothing.

uniform vec3 portal_color : source_color = vec3(0.7, 0.45, 1.0);
uniform vec3 rim_color : source_color = vec3(0.95, 0.85, 1.0);
uniform float swirl = 3.0;
uniform float strength = 0.08;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
instance uniform float open = 1.0;

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float radius = open;
	if (r > radius) {
		discard;
	}
	float rr = r / max(radius, 0.001);
	float ang = atan(c.y, c.x) + swirl * (1.0 - rr) + TIME * 0.8;
	float n = texture(noise_tex, vec2(ang * 0.3, rr * 0.8 - TIME * 0.2)).r;
	vec2 dir = vec2(cos(ang), sin(ang)) * rr * 0.5;
	vec2 offset = (dir - c) * strength * (1.0 - rr) * 2.0 + vec2(n - 0.5) * 0.01;
	vec3 behind = textureLod(screen_texture, SCREEN_UV + offset, 1.5).rgb;
	vec3 col = mix(behind, portal_color * (0.6 + n * 0.8), smoothstep(0.2, 0.95, 1.0 - rr) * 0.75);
	float rim = smoothstep(0.82, 1.0, rr) * (0.7 + n * 0.6);
	ALBEDO = col + rim_color * rim * 2.0;
	ALPHA = 1.0;
}
