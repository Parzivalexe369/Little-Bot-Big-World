shader_type canvas_item;
// Main menu backdrop: a soft, warm-dark wash on the left behind the text that fades out
// before the robot (the scene stays visible through it), plus a whisper of vignette.
// Aspect-aware, so the fade ends at the same place relative to the menu column.

uniform vec3 tint : source_color = vec3(0.035, 0.05, 0.04);
uniform float strength = 0.62;
uniform float fade_end = 0.54;   // fraction of the screen width where the wash is gone
uniform float vignette = 0.16;

void fragment() {
	vec2 uv = UV;
	// Ease-out falloff from the left edge: dense behind the text, feathered toward the scene.
	float x = clamp(uv.x / fade_end, 0.0, 1.0);
	float wash = pow(1.0 - x, 1.7);
	// Slightly denser toward the bottom-left where the menu items sit.
	wash *= mix(0.82, 1.0, smoothstep(0.15, 0.85, uv.y));
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 c = (uv - vec2(0.55, 0.5)) * vec2(mix(1.0, aspect, 0.5), 1.0);
	float vig = smoothstep(0.45, 1.05, length(c) * 1.25);
	COLOR = vec4(tint, clamp(wash * strength + vig * vignette, 0.0, 0.8));
}
