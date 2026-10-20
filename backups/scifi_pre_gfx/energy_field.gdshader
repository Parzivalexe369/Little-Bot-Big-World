shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Flowing energy: reactor plasma, energy bridges, hazard arcs and laser cores. Two
// scrolling noise layers drive a color ramp; intensity, flow direction and "charge"
// (0..1, e.g. a core's fill level as a height cutoff) are driven from code.

uniform vec3 color_a : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 color_b : source_color = vec3(0.9, 0.98, 1.0);
uniform float intensity = 2.0;
uniform vec2 flow = vec2(0.0, 0.6);
uniform float noise_scale = 1.4;
uniform float fresnel_boost = 1.2;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
instance uniform float charge = 1.0;
// Local-space height range that "charge" fills (for core columns); fill_height <= 0 disables.
uniform float fill_bottom = 0.0;
uniform float fill_height = 0.0;
instance uniform float pulse = 0.0;

varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float fres = pow(1.0 - facing, 1.6);
	vec2 uv = vec2(atan(v_local.z, v_local.x) * 0.6 + v_local.y * 0.1, v_local.y) * noise_scale;
	float n1 = texture(noise_tex, uv * 0.6 + TIME * flow).r;
	float n2 = texture(noise_tex, uv * 1.3 - TIME * flow * 1.7 + vec2(0.3, 0.1)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float bands = smoothstep(0.45, 0.75, n);
	vec3 col = mix(color_a, color_b, bands);
	float level = (0.35 + bands * 0.9 + fres * fresnel_boost) * intensity * (1.0 + pulse);
	float vis = 1.0;
	if (fill_height > 0.0) {
		float h = (v_local.y - fill_bottom) / fill_height;
		vis = 1.0 - smoothstep(charge - 0.015, charge + 0.015, h);
		// Bright meniscus at the fill line.
		level += (1.0 - smoothstep(0.0, 0.03, abs(h - charge))) * 2.0 * step(0.001, charge);
	} else {
		vis = charge;
	}
	ALBEDO = col * level * vis;
}
