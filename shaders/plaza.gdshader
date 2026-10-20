shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Shrine plaza paving: concentric rings of worn stone slabs. Each slab samples the stone scan
// (Poly Haven CC0) with its own offset and rotation, has chamfered edges (normal tilt + AO
// toward the joints), slight per-slab tone and settling; moss grows in the joints and a carved
// rune ring lights up when the shrine is restored.

#include "res://shaders/includes/world_common.gdshaderinc"

uniform vec3 stone_a : source_color = vec3(0.66, 0.64, 0.58);
uniform vec3 stone_b : source_color = vec3(0.56, 0.55, 0.5);
uniform vec3 grout : source_color = vec3(0.28, 0.36, 0.2);
uniform vec3 rune_color : source_color = vec3(0.45, 0.95, 1.0);
uniform float radius = 13.5;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float stone_avg_lum = 0.42;
uniform float stone_scale = 0.45;
uniform float bevel_width = 0.09;

varying vec3 v_world;
varying vec2 v_local;
varying float v_top;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX.xz;
	v_top = step(0.5, NORMAL.y);
}

void fragment() {
	float r = length(v_local);
	float a = atan(v_local.y, v_local.x);
	float ring_w = 1.6;
	float ring = floor(r / ring_w);
	float ring_f = fract(r / ring_w);
	float slabs = max(6.0, floor(ring * 6.0 + 6.0));
	float seg = (a / TAU + 0.5) * slabs + ring * 0.37;
	float seg_f = fract(seg);
	float seg_len = TAU * max(r, 0.5) / slabs;
	float d_ring = min(ring_f, 1.0 - ring_f) * ring_w;
	float d_seg = min(seg_f, 1.0 - seg_f) * seg_len;
	float joint = min(d_ring, d_seg);
	float id = fract(sin(floor(seg) * 12.9898 + ring * 78.233) * 43758.5453);
	float id2 = fract(id * 17.17 + 0.31);

	// Each slab: its own patch of the scan (offset + rotation).
	float ang = id * TAU;
	mat2 rotm = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang)));
	vec2 uv = rotm * (v_world.xz * stone_scale) + vec2(id, id2) * 7.0;
	vec3 t_col = texture(stone_albedo, uv).rgb;
	vec3 t_nrm = texture(stone_normal, uv).rgb * 2.0 - 1.0;
	vec3 t_arm = texture(stone_arm, uv).rgb;
	float lum = dot(t_col, vec3(0.299, 0.587, 0.114));
	float n = texture(noise_tex, v_world.xz * 0.35).r;
	vec3 col = mix(stone_a, stone_b, id) * clamp(lum / stone_avg_lum, 0.4, 1.6) * (0.9 + n * 0.2);

	// Chamfer: tilt the normal down toward the nearest joint, darken the edge.
	vec2 radial = r > 0.001 ? v_local / r : vec2(1.0, 0.0);
	vec2 tangent = vec2(-radial.y, radial.x);
	float tilt_r = (1.0 - smoothstep(0.0, bevel_width, d_ring)) * (ring_f < 0.5 ? -1.0 : 1.0);
	float tilt_s = (1.0 - smoothstep(0.0, bevel_width, d_seg)) * (seg_f < 0.5 ? -1.0 : 1.0);
	vec2 tilt = (radial * tilt_r + tangent * tilt_s) * 0.55;
	// Slabs have settled unevenly over the centuries.
	tilt += (vec2(id, id2) - 0.5) * 0.06;
	vec3 n_world = normalize(vec3(tilt.x + t_nrm.x * 0.8, 1.0, tilt.y - t_nrm.y * 0.8));
	float edge_ao = mix(0.6, 1.0, smoothstep(0.0, bevel_width * 1.6, joint));

	// Moss in the joints, spreading a little onto worn slabs.
	float restore = restore_at(v_world.xz);
	vec3 moss_tex = texture(moss_albedo, v_world.xz * 0.6).rgb;
	vec3 moss = mix(desaturate(moss_tex, 0.5), moss_tex * 1.2, restore);
	float spread = smoothstep(0.62, 0.9, n) * 0.08;
	float jmask = 1.0 - smoothstep(0.03, 0.07 + spread, joint);
	col = mix(col, moss, jmask * 0.9);

	// Carved rune ring.
	float rune_band = smoothstep(4.6, 4.75, r) * (1.0 - smoothstep(5.25, 5.4, r));
	float glyphs = step(0.5, fract(a * 6.0 / PI + sin(a * 11.0) * 0.2));
	float carve = rune_band * (0.5 + 0.5 * glyphs);
	col = mix(col, col * 0.55, carve);
	float edge = smoothstep(radius - 0.6, radius, r);

	ALBEDO = col * edge_ao;
	AO = t_arm.r;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = mix(clamp(t_arm.g, 0.5, 1.0), 0.95, jmask);
	SPECULAR = 0.4;
	if (v_top > 0.5) {
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	}
	EMISSION = rune_color * carve * restore * 2.0 + SCAN_COLOR * scan_ring(v_world) * 0.7;
	ALPHA = 1.0 - edge;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
