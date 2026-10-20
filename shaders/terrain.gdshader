shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Ground: photoscanned PBR layers (Poly Haven CC0) blended by per-vertex area/path/wet data.
//   0 grass soil   1 dirt path   2 forest floor   3 cliff rock
//   4 mossy cobble 5 gravel sand 6 wet mud     7 mossy rock
// Anti-tiling: each ground layer is sampled at two scales/rotations mixed by macro noise.
// Cliffs use triplanar projection. Normals use whiteout blending against the mesh normal.

#include "res://shaders/includes/world_common.gdshaderinc"

uniform sampler2DArray layer_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

// World units are "big world" scale (giant grass), so the scans are stretched accordingly.
uniform float ground_scale = 0.2;
uniform float path_scale = 0.25;
uniform float cliff_scale = 0.045;
uniform float normal_strength = 1.0;
// Living grass cover over the soil scan (keeps the scan's detail, shifts its hue).
uniform vec3 lush_tint : source_color = vec3(0.86, 1.24, 0.5);
uniform float lush_amount = 0.88;
uniform vec3 forest_moss_tint : source_color = vec3(0.66, 0.92, 0.42);
uniform vec3 path_tint : source_color = vec3(1.34, 1.24, 1.08);
uniform vec3 rock_tint : source_color = vec3(0.9, 0.92, 0.88);

// Per-area grading of the ground layer (scans are neutral; the art direction tints them).
uniform vec3 meadow_tint : source_color = vec3(1.0, 1.02, 0.86);
uniform vec3 forest_tint : source_color = vec3(0.86, 0.9, 0.78);
uniform vec3 shrine_tint : source_color = vec3(0.96, 1.0, 0.9);
uniform vec3 garden_tint : source_color = vec3(0.95, 0.9, 1.08);
uniform vec3 dormant_tint : source_color = vec3(1.02, 0.96, 0.82);

varying vec3 world_pos;
varying vec3 world_normal;

vec3 unpack_normal(vec4 c) {
	vec3 n = c.rgb * 2.0 - 1.0;
	n.xy *= normal_strength;
	return n;
}

mat2 rot2(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

// Two-scale sample of a ground layer on the XZ plane. Returns albedo, normal (tangent space), arm.
void sample_ground(float layer, vec2 xz, float scale, float mix_t, out vec3 alb, out vec3 nrm, out vec3 arm) {
	vec3 uv_a = vec3(xz * scale, layer);
	vec3 uv_b = vec3(rot2(0.65) * xz * scale * 0.47 + vec2(0.37, 0.71), layer);
	vec4 a1 = texture(layer_albedo, uv_a);
	vec4 a2 = texture(layer_albedo, uv_b);
	vec4 n1 = texture(layer_normal, uv_a);
	vec4 n2 = texture(layer_normal, uv_b);
	vec4 r1 = texture(layer_arm, uv_a);
	vec4 r2 = texture(layer_arm, uv_b);
	alb = mix(a1.rgb, a2.rgb, mix_t);
	nrm = normalize(mix(unpack_normal(n1), unpack_normal(n2), mix_t));
	arm = mix(r1.rgb, r2.rgb, mix_t);
}

// Triplanar sample of one layer; returns albedo, world-space normal (whiteout per axis) and arm.
void triplanar(float layer, vec3 p, vec3 n, vec3 bw, float scale, out vec3 alb, out vec3 nrm, out vec3 arm) {
	vec3 uvx = vec3(p.zy * scale, layer);
	vec3 uvy = vec3(p.xz * scale, layer);
	vec3 uvz = vec3(p.xy * scale, layer);
	alb = texture(layer_albedo, uvx).rgb * bw.x + texture(layer_albedo, uvy).rgb * bw.y + texture(layer_albedo, uvz).rgb * bw.z;
	arm = texture(layer_arm, uvx).rgb * bw.x + texture(layer_arm, uvy).rgb * bw.y + texture(layer_arm, uvz).rgb * bw.z;
	vec3 tnx = unpack_normal(texture(layer_normal, uvx));
	vec3 tny = unpack_normal(texture(layer_normal, uvy));
	vec3 tnz = unpack_normal(texture(layer_normal, uvz));
	tnx = vec3(tnx.xy + n.zy, abs(tnx.z) * n.x);
	tny = vec3(tny.xy + n.xz, abs(tny.z) * n.y);
	tnz = vec3(tnz.xy + n.xy, abs(tnz.z) * n.z);
	nrm = normalize(tnx.zyx * bw.x + tny.xzy * bw.y + tnz.xyz * bw.z);
}

// World-space normal from a top-projected tangent normal (whiteout blend).
vec3 top_normal(vec3 tn, vec3 n) {
	vec3 t = vec3(tn.xy + n.xz, abs(tn.z) * n.y);
	return normalize(t.xzy);
}

// Height-aware blend: lets bumps of the incoming layer poke through for natural edges.
float height_blend(float mask, float h_base, float h_top, float softness) {
	float t = mask * 1.6 - 0.3 + (h_top - h_base) * 0.6;
	return smoothstep(0.5 - softness, 0.5 + softness, t);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 xz = world_pos.xz;
	float macro = texture(noise_tex, xz * 0.006).r;
	float macro2 = texture(noise_tex, xz * 0.021 + vec2(0.3, 0.6)).r;
	float tile_mix = smoothstep(0.35, 0.65, macro2);

	float path = COLOR.r;
	float wet = COLOR.g;
	float forest = COLOR.b;
	float garden = COLOR.a;
	float shrine = UV2.x;
	float hill = UV2.y;
	float meadow = clamp(1.0 - forest - garden - shrine, 0.0, 1.0);
	float restore = restore_for(vec4(meadow, forest, shrine, garden));
	vec3 n_geo = normalize(world_normal);

	// --- Ground: grass soil (meadow/shrine/garden) vs forest floor ---------------------
	vec3 g_alb; vec3 g_nrm; vec3 g_arm;
	sample_ground(0.0, xz, ground_scale, tile_mix, g_alb, g_nrm, g_arm);
	vec3 tint = meadow_tint * meadow + shrine_tint * shrine + garden_tint * garden + forest_tint * forest;
	g_alb *= tint;
	if (forest > 0.02) {
		vec3 f_alb; vec3 f_nrm; vec3 f_arm;
		sample_ground(2.0, xz, ground_scale * 0.9, tile_mix, f_alb, f_nrm, f_arm);
		float fb = height_blend(forest, g_arm.r, f_arm.r, 0.18);
		g_alb = mix(g_alb, f_alb * forest_tint, fb);
		g_nrm = normalize(mix(g_nrm, f_nrm, fb));
		g_arm = mix(g_arm, f_arm, fb);
	}
	// Living grass over the soil where it is not trampled (the scan alone reads as bare dirt),
	// and moss patches on the forest floor.
	float cover_n = macro * 0.55 + macro2 * 0.6 - path * 0.5;
	float cover = smoothstep(0.05, 0.55, cover_n) * (1.0 - forest) * lush_amount;
	g_alb = mix(g_alb, g_alb * lush_tint * mix(0.95, 1.15, macro2), cover);
	float forest_moss = smoothstep(0.3, 0.7, cover_n) * forest * 0.5;
	g_alb = mix(g_alb, desaturate(g_alb, 0.3) * forest_moss_tint * 1.15, forest_moss);
	// Macro color variation breaks up any remaining repetition.
	g_alb *= mix(0.82, 1.12, macro) * mix(vec3(1.0), vec3(1.06, 1.0, 0.9), smoothstep(0.55, 0.8, macro2));

	vec3 alb = g_alb;
	vec3 nrm_ts = g_nrm;
	vec3 arm = g_arm;

	// --- Worn path: dirt / cobblestone (shrine) / gravel (garden) ------------------------
	float path_mask = smoothstep(0.08, 0.95, path);
	if (path_mask > 0.01) {
		float cobble_w = clamp(shrine * 1.6, 0.0, 1.0);
		float gravel_w = clamp(garden * 1.6, 0.0, 1.0) * (1.0 - cobble_w);
		float layer = cobble_w > 0.5 ? 4.0 : (gravel_w > 0.5 ? 5.0 : 1.0);
		vec3 p_alb; vec3 p_nrm; vec3 p_arm;
		sample_ground(layer, xz, path_scale, tile_mix, p_alb, p_nrm, p_arm);
		float pb = height_blend(path_mask, arm.r, p_arm.r, 0.12);
		vec3 ptint = layer == 1.0 ? path_tint : vec3(1.08, 1.04, 0.98);
		alb = mix(alb, desaturate(p_alb, 0.25) * ptint, pb);
		nrm_ts = normalize(mix(nrm_ts, p_nrm, pb));
		arm = mix(arm, p_arm, pb);
	}

	// --- Damp shores ---------------------------------------------------------------------
	if (wet > 0.02) {
		vec3 m_alb; vec3 m_nrm; vec3 m_arm;
		sample_ground(6.0, xz, path_scale, tile_mix, m_alb, m_nrm, m_arm);
		float mb = height_blend(wet, arm.r, m_arm.r, 0.15);
		alb = mix(alb, m_alb * 0.9, mb);
		nrm_ts = normalize(mix(nrm_ts, m_nrm, mb));
		arm = mix(arm, vec3(m_arm.r, m_arm.g * 0.55, 0.0), mb);
	}

	vec3 n_world = top_normal(nrm_ts, n_geo);

	// --- Rock on steep slopes (triplanar) -----------------------------------------------------
	float slope = 1.0 - clamp(n_geo.y, 0.0, 1.0);
	float rock_mask = smoothstep(0.24, 0.46, slope + (macro - 0.5) * 0.2);
	if (rock_mask > 0.01) {
		vec3 bw = pow(abs(n_geo), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec3 c_alb; vec3 c_nrm; vec3 c_arm;
		triplanar(3.0, world_pos, n_geo, bw, cliff_scale, c_alb, c_nrm, c_arm);
		// The scan is a warm sandstone; grade it toward weathered grey stone with large-scale variation.
		float big = texture(noise_tex, world_pos.xz * 0.0025 + world_pos.y * 0.004).r;
		c_alb = mix(desaturate(c_alb, 0.85), c_alb, 0.18) * rock_tint * mix(0.78, 1.1, big);
		// Moss and grass take over ledges and gentler, upward-facing faces.
		float moss_mask = smoothstep(0.25, 0.85, n_geo.y * 0.9 + macro * 0.3 + big * 0.2 - 0.2);
		if (moss_mask > 0.01) {
			vec3 m_alb; vec3 m_nrm; vec3 m_arm;
			triplanar(7.0, world_pos, n_geo, bw, cliff_scale * 2.2, m_alb, m_nrm, m_arm);
			float mb = height_blend(moss_mask, c_arm.r, m_arm.r, 0.14);
			c_alb = mix(c_alb, m_alb * mix(vec3(1.0), vec3(0.9, 1.0, 0.8), forest), mb);
			c_nrm = normalize(mix(c_nrm, m_nrm, mb));
			c_arm = mix(c_arm, m_arm, mb);
		}
		float rb = height_blend(rock_mask, arm.r, c_arm.r, 0.1);
		alb = mix(alb, c_alb, rb);
		n_world = normalize(mix(n_world, c_nrm, rb));
		arm = mix(arm, c_arm, rb);
	}

	// Boundary hills get a cooler, slightly darker read to sit back in depth.
	alb *= mix(vec3(1.0), vec3(0.88, 0.92, 0.9), hill * 0.5);

	// Dormant areas are paler and drier; restoration brings the color back.
	vec3 dormant = desaturate(alb, 0.42) * dormant_tint;
	alb = mix(dormant, alb, 0.35 + restore * 0.65);

	ALBEDO = alb * cloud_shadow(world_pos);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = clamp(arm.g * mix(1.0, 0.75, wet), 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.42;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	EMISSION = SCAN_COLOR * scan_ring(world_pos) * 0.9;
}
