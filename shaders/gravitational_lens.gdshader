shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;
// A singularity seen from far away: a camera-facing disc that bends the image behind it
// toward its centre (gravitational lensing, strongest near the event horizon), a thin bright
// photon ring, and a black core. The bending fades to nothing at the disc edge, so the disc
// has no visible border.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float horizon = 0.1;
uniform float lens = 0.9;
uniform vec3 ring_color : source_color = vec3(1.0, 0.82, 0.95);
uniform float ring_energy = 1.4;

void vertex() {
	// Billboard that keeps the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c);
	if (r > 0.5) {
		discard;
	}
	vec2 dir = c / max(r, 0.0001);
	float fade = 1.0 - smoothstep(0.25, 0.5, r);
	float defl = lens * horizon * horizon / max(r, horizon * 0.9) * fade;
	// UV to screen scale of this disc.
	float s = length(fwidth(SCREEN_UV)) / max(length(fwidth(UV)), 0.00001);
	vec2 off = -dir * defl * s;
	vec3 behind = textureLod(screen_texture, SCREEN_UV + off, 0.0).rgb;
	float ring = exp(-pow((r - horizon * 1.12) / (horizon * 0.06), 2.0));
	float glow = exp(-max(r - horizon, 0.0) / (horizon * 0.5)) * 0.25;
	vec3 col = behind + ring_color * (ring + glow) * ring_energy;
	float hole = 1.0 - smoothstep(horizon * 0.96, horizon * 1.02, r);
	ALBEDO = mix(col, vec3(0.0), hole);
}
