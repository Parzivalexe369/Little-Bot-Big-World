shader_type canvas_item;
// Full-screen HUD overlay: a restrained vignette (frames the shot without hiding anything)
// and a soft colored edge flash for feedback (pickups, bumps). Aspect-correct at any ratio.

uniform float vignette = 0.2;
uniform vec4 flash_color : source_color = vec4(0.5, 0.94, 1.0, 1.0);
uniform float flash = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	uv.x *= mix(1.0, aspect, 0.6);
	float d = length(uv);
	float v = smoothstep(0.42, 0.95, d) * vignette;
	float e = smoothstep(0.3, 0.85, d) * flash;
	float a = clamp(v + e * flash_color.a, 0.0, 1.0);
	vec3 col = mix(vec3(0.0), flash_color.rgb, e / max(v + e, 0.0001));
	COLOR = vec4(col, a);
}
