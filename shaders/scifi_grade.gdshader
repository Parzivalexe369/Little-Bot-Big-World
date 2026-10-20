shader_type canvas_item;
// Cinematic grade for the sci-fi areas (drawn under the HUD): split toning (separate tints
// for shadows and highlights), a gentle contrast curve, saturation, vignette, fine film grain
// and a hint of chromatic aberration toward the frame edges. Values come from the area mood.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec3 shadow_tint : source_color = vec3(0.95, 1.0, 1.05);
uniform vec3 highlight_tint : source_color = vec3(1.04, 1.0, 0.96);
uniform float contrast = 1.06;
uniform float saturation = 1.0;
uniform float vignette = 0.3;
uniform float grain = 0.025;
uniform float aberration = 0.0012;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 off = c * aberration * r2 * 6.0;
	vec3 col = vec3(texture(screen_texture, uv + off).r, texture(screen_texture, uv).g, texture(screen_texture, uv - off).b);
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.08, 0.75, l));
	// Contrast around mid grey with a soft toe and shoulder.
	vec3 x = clamp(col, 0.0, 1.0);
	vec3 curved = x * x * (3.0 - 2.0 * x);
	col = mix(col, mix(col, curved, 1.0), clamp(contrast - 1.0, 0.0, 1.0) * 2.0);
	col = mix(vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), col, saturation);
	col *= 1.0 - vignette * smoothstep(0.12, 0.62, r2 * 1.7);
	float n = fract(sin(dot(floor(FRAGCOORD.xy) + fract(TIME * 7.13) * 917.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * grain;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
