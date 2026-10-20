shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Sci-fi architecture and machines: box-projected (world space) panel grid with bevelled
// seams, per-panel tone variation and inset vents, corner rivets, grime that gathers near
// the floor and in seams, optional scorch damage, photoscanned metal micro-detail, and
// optional glowing light strips that can flicker or switch off with facility power.

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
// 0..1: facility power for this object (strips and emissive accents follow it).
instance uniform float power_level = 1.0;

varying vec3 v_world;
varying vec3 v_wnormal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
	vec2 g = uv / cell_size;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float id = hash2(cell + floor(v_world.y * 0.01));
	// Distance to the nearest seam in metres.
	vec2 dist = min(f, 1.0 - f) * cell_size;
	float d = min(dist.x, dist.y);
	float seam = 1.0 - smoothstep(seam_width * 0.6, seam_width, d);
	// Bevel: tilt the normal toward the nearest seam.
	vec2 tilt = vec2(0.0);
	float bev = 1.0 - smoothstep(seam_width, seam_width + bevel, d);
	if (dist.x < dist.y) {
		tilt.x = (f.x < 0.5 ? -1.0 : 1.0) * bev;
	} else {
		tilt.y = (f.y < 0.5 ? -1.0 : 1.0) * bev;
	}
	vec3 col = mix(base_color, alt_color, step(0.55, id)) * (0.94 + id * 0.1);
	// Inset vent panels: darker with horizontal slats.
	float vent = step(1.0 - vent_chance, fract(id * 7.31));
	if (vent > 0.5) {
		float slat = smoothstep(0.35, 0.5, abs(fract(f.y * 7.0) - 0.5));
		col = mix(col * 0.35, col * 0.55, slat);
		tilt.y += (fract(f.y * 7.0) - 0.5) * 0.6;
	}
	// Corner rivets: small domes inset from each panel corner.
	if (rivets > 0.0) {
		vec2 cp = (f - 0.5) * cell_size;
		vec2 rel = abs(cp) - (cell_size * 0.5 - vec2(0.06));
		float rd = length(rel);
		float rivet = (1.0 - smoothstep(0.012, 0.018, rd)) * rivets;
		col = mix(col, col * 0.72, rivet);
		tilt += sign(cp) * rel / max(rd, 0.001) * rivet * 0.5;
	}
	col = mix(col, seam_color, seam);
	// Micro detail from the painted-metal scan.
	vec2 duv = uv * detail_scale;
	vec3 dn = texture(detail_normal, duv).rgb * 2.0 - 1.0;
	vec3 darm = texture(detail_arm, duv).rgb;
	float nz = texture(noise_tex, uv * 0.11).r;
	float nz2 = texture(noise_tex, uv * 0.37 + vec2(0.3, 0.7)).r;
	// Grime: near the floor, in seams, and in broad noisy patches.
	float floor_grime = 1.0 - smoothstep(0.0, 0.9, v_world.y - floor_level);
	float g_amt = clamp((floor_grime * 0.8 + seam * 0.6 + smoothstep(0.55, 0.85, nz) * 0.5) * grime, 0.0, 1.0);
	col = mix(col, col * vec3(0.45, 0.42, 0.38), g_amt * 0.8);
	// Scorch marks.
	float scorch = smoothstep(0.62, 0.8, nz2 * 0.7 + nz * 0.5) * damage;
	col = mix(col, vec3(0.05, 0.045, 0.04), scorch);
	float rough = clamp(roughness_value + (darm.g - 0.5) * 0.3 * detail_strength + g_amt * 0.3 + scorch * 0.3 - seam * 0.0, 0.05, 1.0);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic_value * (1.0 - g_amt * 0.5) * (1.0 - scorch);
	AO = mix(1.0, darm.r, detail_strength * 0.6) * (1.0 - seam * 0.6);
	vec3 nt = normalize(vec3(tilt * 0.9 + dn.xy * detail_strength * 0.5, 1.0));
	vec3 n_world = normalize(t_axis * nt.x + b_axis * nt.y + n * nt.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// Light strips along walls.
	vec3 emit = vec3(0.0);
	if (strip_energy > 0.0 && strip_spacing > 0.0 && an.y < 0.5) {
		float sy = abs(fract((v_world.y - floor_level) / strip_spacing) - 0.5) * strip_spacing;
		float strip = 1.0 - smoothstep(strip_width * 0.5, strip_width, abs(sy - strip_spacing * 0.5));
		float fl = 1.0;
		if (flicker > 0.0) {
			float tq = floor(TIME * 13.0 + id * 31.0);
			fl = mix(1.0, step(0.35, fract(sin(tq * 12.9898) * 43758.5453)), flicker);
		}
		emit = strip_color * strip * strip_energy * fl * power_level;
	}
	EMISSION = emit + SCAN_COLOR * scan_ring(v_world) * 0.6;
}
