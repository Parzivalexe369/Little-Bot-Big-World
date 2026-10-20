shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Sci-fi architecture and machines (areas 5-7 only). World-space box projection of a panel
// grid whose seams are recessed with analytic parallax (real-looking depth without extra
// geometry), on top of a photoscanned PBR surface (albedo, normal, AO/roughness/metal).
// Layers: per-panel tone and scan offset, inset vents with slats, corner bolts, paint wear
// on chamfered block edges and panel corners, dust on upward faces and in seams, grime that
// gathers near the floor, rust-coloured streaks under seams, stencil markings, polished
// patches on floors, scorch damage, and glowing light strips that follow facility power.

#include "res://shaders/includes/world_common.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.74, 0.76, 0.79);
uniform vec3 alt_color : source_color = vec3(0.66, 0.68, 0.72);
uniform vec3 seam_color : source_color = vec3(0.06, 0.07, 0.08);
uniform float panel_size = 1.2;
uniform vec2 panel_aspect = vec2(1.0, 0.5);
uniform float seam_width = 0.012;
uniform float bevel = 0.03;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.42;
uniform float vent_chance : hint_range(0.0, 1.0) = 0.08;
uniform float rivets = 1.0;
uniform float grime : hint_range(0.0, 1.0) = 0.35;
uniform float floor_level = 0.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec3 strip_color : source_color = vec3(0.35, 0.85, 1.0);
uniform float strip_energy = 0.0;
uniform float strip_spacing = 0.0;
uniform float strip_width = 0.035;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 0.9;
uniform float detail_strength = 0.6;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

// Photoscanned surface.
uniform sampler2D scan_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_scan : hint_range(0.0, 1.0) = 0.0;
uniform float scan_scale = 0.45;          // repeats per metre
uniform float scan_lum = 0.3;             // average luminance of the scan albedo
uniform float scan_detail : hint_range(0.0, 1.5) = 0.8;   // light/dark variation from the scan
uniform float scan_color : hint_range(0.0, 1.0) = 0.15;   // 0 = tinted by base colour, 1 = raw scan colour
uniform float scan_rough : hint_range(0.0, 1.0) = 0.6;
uniform float scan_normal_strength = 0.8;
uniform float scan_metal : hint_range(0.0, 1.0) = 0.0;    // how much the scan's metal map is used

// Depth and wear.
uniform float groove_depth = 0.02;        // seam depth in metres (parallax)
uniform float recess_chance : hint_range(0.0, 1.0) = 0.1;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.0;
uniform vec3 wear_color : source_color = vec3(0.6, 0.61, 0.63);
uniform float vertex_edges = 0.0;         // 1: vertex colour red marks chamfered block edges
uniform float dust : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dust_color : source_color = vec3(0.52, 0.5, 0.47);
uniform float streaks : hint_range(0.0, 1.0) = 0.0;
uniform vec3 streak_color : source_color = vec3(0.3, 0.22, 0.16);
uniform float markings : hint_range(0.0, 1.0) = 0.0;
uniform vec3 marking_color : source_color = vec3(0.92, 0.72, 0.18);
uniform float gloss : hint_range(0.0, 1.0) = 0.0;

// 0..1: facility power for this object (strips and emissive accents follow it).
instance uniform float power_level = 1.0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying float v_edge;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_edge = COLOR.r * vertex_edges;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Panel surface height at a 2D coordinate: 1 on the panel face, 0 at the bottom of a seam.
// Some panels sit recessed and vents are deep insets.
float panel_height(vec2 uv, vec2 cell_size, float layer) {
	vec2 g = uv / cell_size;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float id = hash2(cell + layer);
	vec2 dist = min(f, 1.0 - f) * cell_size;
	float d = min(dist.x, dist.y);
	float h = smoothstep(seam_width * 0.5, seam_width + bevel, d);
	float vent = step(1.0 - vent_chance, fract(id * 7.31));
	float recess = step(1.0 - recess_chance, fract(id * 3.17)) * (1.0 - vent);
	float inner = smoothstep(0.07, 0.1, d);
	h = mix(h, h * 0.55, recess * inner);
	if (vent > 0.5) {
		float slat = smoothstep(0.3, 0.5, abs(fract(f.y * 7.0) - 0.5));
		h = mix(h, mix(0.15, 0.45, slat), smoothstep(0.08, 0.11, d));
	}
	return h;
}

void fragment() {
	vec3 n = normalize(v_wnormal);
	vec3 an = abs(n);
	// Box projection: pick the dominant axis; build that plane's 2D coords and tangent basis.
	vec2 uv;
	vec3 t_axis;
	vec3 b_axis;
	if (an.y >= an.x && an.y >= an.z) {
		uv = v_world.xz; t_axis = vec3(1, 0, 0); b_axis = vec3(0, 0, 1);
	} else if (an.x >= an.z) {
		uv = vec2(v_world.z, v_world.y); t_axis = vec3(0, 0, 1); b_axis = vec3(0, 1, 0);
	} else {
		uv = vec2(v_world.x, v_world.y); t_axis = vec3(1, 0, 0); b_axis = vec3(0, 1, 0);
	}
	vec2 cell_size = vec2(panel_size) * panel_aspect;
	float layer = floor(v_world.y * 0.01);
	float view_dist = length(VERTEX);
	// Parallax: march the view ray into the seams (close range only).
	float depth = groove_depth * (1.0 - smoothstep(14.0, 24.0, view_dist));
	float h_here = 1.0;
	if (depth > 0.001 && seam_width > 0.0) {
		vec3 vdir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 vt = vec3(dot(vdir, t_axis), dot(vdir, b_axis), dot(vdir, n));
		vec2 step_uv = -vt.xy / max(vt.z, 0.25) * depth / 10.0;
		float ray_h = 1.0;
		vec2 p = uv;
		float h = panel_height(p, cell_size, layer);
		for (int i = 0; i < 10 && h < ray_h; i++) {
			p += step_uv;
			ray_h -= 0.1;
			h = panel_height(p, cell_size, layer);
		}
		uv = p;
		h_here = h;
	} else {
		h_here = panel_height(uv, cell_size, layer);
	}

	vec2 g = uv / cell_size;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float id = hash2(cell + layer);
	vec2 dist = min(f, 1.0 - f) * cell_size;
	float d = min(dist.x, dist.y);
	float seam = seam_width > 0.0 ? 1.0 - smoothstep(seam_width * 0.6, seam_width, d) : 0.0;
	// Bevel: tilt the normal toward the nearest seam.
	vec2 tilt = vec2(0.0);
	float bev = seam_width > 0.0 ? 1.0 - smoothstep(seam_width, seam_width + bevel, d) : 0.0;
	if (dist.x < dist.y) {
		tilt.x = (f.x < 0.5 ? -1.0 : 1.0) * bev;
	} else {
		tilt.y = (f.y < 0.5 ? -1.0 : 1.0) * bev;
	}
	vec3 col = mix(base_color, alt_color, step(0.55, id)) * (0.94 + id * 0.1);
	float vent = step(1.0 - vent_chance, fract(id * 7.31));
	if (vent > 0.5) {
		float slat_f = fract(f.y * 7.0);
		float slat = smoothstep(0.35, 0.5, abs(slat_f - 0.5));
		col = mix(col * 0.3, col * 0.55, slat);
		tilt.y += (slat_f - 0.5) * 0.6 * smoothstep(0.08, 0.11, d);
	}
	float recess = step(1.0 - recess_chance, fract(id * 3.17)) * (1.0 - vent);
	// Recessed panels: a sloped inner border.
	if (recess > 0.5) {
		float rb = 1.0 - smoothstep(0.07, 0.1, d);
		rb *= smoothstep(seam_width + bevel, seam_width + bevel + 0.01, d);
		if (dist.x < dist.y) {
			tilt.x -= (f.x < 0.5 ? -1.0 : 1.0) * rb * 0.7;
		} else {
			tilt.y -= (f.y < 0.5 ? -1.0 : 1.0) * rb * 0.7;
		}
		col *= 0.93;
	}
	// Corner bolts: small domes inset from each panel corner.
	float rivet = 0.0;
	if (rivets > 0.0) {
		vec2 cp = (f - 0.5) * cell_size;
		vec2 rel = abs(cp) - (cell_size * 0.5 - vec2(0.06));
		float rd = length(rel);
		rivet = (1.0 - smoothstep(0.012, 0.018, rd)) * rivets;
		col = mix(col, col * 0.72, rivet);
		tilt += sign(cp) * rel / max(rd, 0.001) * rivet * 0.5;
	}

	// Photoscanned surface (offset per panel so the scan never visibly repeats).
	vec2 suv = uv * scan_scale + vec2(id * 3.7, fract(id * 13.1) * 5.3);
	vec3 s_alb = vec3(scan_lum);
	vec3 s_nrm = vec3(0.0, 0.0, 1.0);
	vec3 s_arm = vec3(1.0, roughness_value, metallic_value);
	if (use_scan > 0.0) {
		s_alb = texture(scan_albedo, suv).rgb;
		s_nrm = texture(scan_normal, suv).rgb * 2.0 - 1.0;
		s_arm = texture(scan_arm, suv).rgb;
		float sl = luma(s_alb);
		vec3 tinted = col * mix(1.0, sl / max(scan_lum, 0.01), scan_detail);
		vec3 raw = s_alb * (luma(col) / max(scan_lum, 0.01));
		col = mix(col, mix(tinted, raw, scan_color), use_scan);
	}
	col = mix(col, seam_color, seam);

	// Micro detail from the painted-metal scan.
	vec2 duv = uv * detail_scale;
	vec3 dn = texture(detail_normal, duv).rgb * 2.0 - 1.0;
	vec3 darm = texture(detail_arm, duv).rgb;
	float nz = texture(noise_tex, uv * 0.11).r;
	float nz2 = texture(noise_tex, uv * 0.37 + vec2(0.3, 0.7)).r;
	float nz3 = texture(noise_tex, uv * 1.7 + vec2(0.61, 0.17)).r;

	// Grime: near the floor, in seams, and in broad noisy patches.
	float floor_grime = 1.0 - smoothstep(0.0, 0.9, v_world.y - floor_level);
	float g_amt = clamp((floor_grime * 0.8 + seam * 0.6 + (1.0 - h_here) * 0.4 + smoothstep(0.55, 0.85, nz) * 0.5) * grime, 0.0, 1.0);
	col = mix(col, col * vec3(0.45, 0.42, 0.38), g_amt * 0.8);

	// Streaks running down from seams and vents on walls.
	float streak = 0.0;
	if (streaks > 0.0 && an.y < 0.5) {
		float sx = texture(noise_tex, vec2(uv.x * 2.3, uv.y * 0.12 + id)).r;
		float lines = smoothstep(0.58, 0.8, sx) * pow(clamp(f.y, 0.0, 1.0), 2.2);
		streak = lines * streaks * (0.6 + 0.4 * nz2);
		col = mix(col, col * streak_color * 2.2, streak * 0.75);
	}

	// Dust on upward faces, heavier in seams and away from foot traffic.
	float dust_amt = 0.0;
	if (dust > 0.0) {
		float up = smoothstep(0.55, 0.95, n.y);
		dust_amt = clamp(up * (smoothstep(0.35, 0.75, nz2) * 0.7 + (1.0 - h_here) * 0.8 + nz3 * 0.25) * dust, 0.0, 1.0);
		col = mix(col, dust_color, dust_amt * 0.7);
	}

	// Paint wear: chamfered block edges and panel corners, broken up by noise.
	float wear = 0.0;
	if (edge_wear > 0.0) {
		float corner_d = length(max(cell_size * 0.5 - abs((f - 0.5) * cell_size), vec2(0.0)));
		float edge_zone = max(v_edge, (1.0 - smoothstep(0.0, 0.05, d - seam_width - bevel)) * 0.55);
		edge_zone = max(edge_zone, (1.0 - smoothstep(0.03, 0.12, corner_d)) * 0.5);
		float chips = smoothstep(0.45, 0.6, nz3 * 0.65 + nz2 * 0.35 + edge_zone * 0.55);
		wear = clamp(chips * edge_zone * 1.6, 0.0, 1.0) * edge_wear * (1.0 - vent);
		col = mix(col, wear_color * (0.85 + 0.3 * nz3), wear);
	}

	// Stencil markings: a label plate with hazard stripes near a corner of some panels.
	float mark = 0.0;
	if (markings > 0.0 && an.y < 0.5 && vent < 0.5) {
		float chance = step(1.0 - markings * 0.35, fract(id * 5.71));
		vec2 lp = (f - vec2(0.12, 0.72)) * cell_size;
		vec2 box = vec2(0.34, 0.08);
		vec2 q = abs(lp - box) - box;
		float inside = 1.0 - step(0.0, max(q.x, q.y));
		float stripes = step(0.5, fract((lp.x + lp.y) * 9.0));
		float worn = smoothstep(0.25, 0.55, nz3);
		mark = inside * chance * worn;
		col = mix(col, mix(marking_color, vec3(0.03), stripes * step(0.5, fract(id * 9.1))), mark);
	}

	// Scorch marks.
	float scorch = smoothstep(0.62, 0.8, nz2 * 0.7 + nz * 0.5) * damage;
	col = mix(col, vec3(0.05, 0.045, 0.04), scorch);

	// Roughness / metal.
	float rough = roughness_value;
	rough += (s_arm.g - 0.5) * scan_rough * use_scan;
	rough += (darm.g - 0.5) * 0.3 * detail_strength;
	rough += g_amt * 0.3 + scorch * 0.3 + dust_amt * 0.45 + streak * 0.2;
	rough = mix(rough, 0.32, wear);
	// Polished patches on floors (catch reflections).
	if (gloss > 0.0 && n.y > 0.6) {
		float pol = smoothstep(0.35, 0.7, nz) * (1.0 - dust_amt) * gloss;
		rough = mix(rough, 0.12, pol);
	}
	float metal = mix(metallic_value, s_arm.b, scan_metal * use_scan);
	metal *= (1.0 - g_amt * 0.5) * (1.0 - scorch) * (1.0 - dust_amt * 0.8) * (1.0 - mark * 0.7);
	metal = mix(metal, 1.0, wear);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	float ao = mix(1.0, darm.r, detail_strength * 0.6) * (1.0 - seam * 0.6);
	ao *= mix(1.0, s_arm.r, 0.8 * use_scan);
	ao *= mix(0.45, 1.0, h_here);
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	vec2 nxy = tilt * 0.9 + dn.xy * detail_strength * 0.35 + s_nrm.xy * scan_normal_strength * use_scan * (1.0 - wear * 0.5);
	vec3 nt = normalize(vec3(nxy, 1.0));
	vec3 n_world = normalize(t_axis * nt.x + b_axis * nt.y + n * nt.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Light strips along walls, with a soft spill onto the surrounding panels.
	vec3 emit = vec3(0.0);
	if (strip_energy > 0.0 && strip_spacing > 0.0 && an.y < 0.5) {
		float sy = abs(fract((v_world.y - floor_level) / strip_spacing) - 0.5) * strip_spacing;
		float off = abs(sy - strip_spacing * 0.5);
		float strip = 1.0 - smoothstep(strip_width * 0.5, strip_width, off);
		float spill = exp(-off / 0.12) * 0.06;
		float fl = 1.0;
		if (flicker > 0.0) {
			float tq = floor(TIME * 13.0 + id * 31.0);
			fl = mix(1.0, step(0.35, fract(sin(tq * 12.9898) * 43758.5453)), flicker);
		}
		emit = strip_color * (strip + spill) * strip_energy * fl * power_level;
	}
	EMISSION = emit + SCAN_COLOR * scan_ring(v_world) * 0.6;
}
