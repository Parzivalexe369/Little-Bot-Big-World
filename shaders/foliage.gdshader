shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
// Plants: wind sway (vertex color G), petals that fold shut while an area is dormant and
// open as it is restored (vertex color A + UV offsets), soft backlit translucency,
// gentle bending away from the robot and the scanner ring.

#include "res://shaders/includes/world_common.gdshaderinc"

uniform vec3 albedo_color : source_color = vec3(0.35, 0.6, 0.22);
uniform vec3 dormant_color : source_color = vec3(0.55, 0.55, 0.4);
uniform float dormant_mix : hint_range(0.0, 1.0) = 0.55;
uniform float wind_amplitude = 0.25;
uniform float wind_stiffness = 1.0;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.65;
uniform float bloom_fold = 1.0;
uniform float player_push = 0.0;
uniform float emission_amount = 0.0;
uniform float variation = 0.12;
// Sun-bleached tips on some blades (per-part random from vertex color B).
uniform float dry_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dry_color : source_color = vec3(0.66, 0.6, 0.36);
// Softer stylized shading: bend normals toward the sky and brighten toward the tips.
uniform float normal_up_bias : hint_range(0.0, 1.0) = 0.0;
uniform float tip_gradient : hint_range(0.0, 1.0) = 0.0;
// Plants right in front of the camera dissolve so they never hide the robot.
uniform float near_fade_start = 0.7;
uniform float near_fade_end = 2.6;
// Area tint: grass blends between per-area colors by world position (smooth transitions).
uniform bool use_area_tint = false;
uniform vec3 tint_meadow : source_color = vec3(0.34, 0.52, 0.17);
uniform vec3 tint_forest : source_color = vec3(0.2, 0.36, 0.14);
uniform vec3 tint_shrine : source_color = vec3(0.36, 0.5, 0.24);
uniform vec3 tint_garden : source_color = vec3(0.4, 0.66, 0.62);
uniform vec3 tint_garden_alt : source_color = vec3(0.64, 0.56, 0.86);

varying float v_restore;
varying float v_ao;
varying vec3 v_world;
varying float v_var;
varying vec3 v_tint;
varying float v_sway;
varying float v_part;

void vertex() {
	// VERTEX is already in world space (world_vertex_coords).
	vec3 root = MODEL_MATRIX[3].xyz;
	float obj_scale = length(MODEL_MATRIX[1].xyz);
	v_restore = restore_at(root.xz);
	v_tint = albedo_color;
	if (use_area_tint) {
		vec4 aw = area_weights_at(root.xz);
		float h = fract(sin(dot(floor(root.xz * 0.7), vec2(12.9898, 78.233))) * 43758.5453);
		vec3 garden = mix(tint_garden, tint_garden_alt, smoothstep(0.35, 0.65, h));
		v_tint = tint_meadow * aw.x + tint_forest * aw.y + tint_shrine * aw.z + garden * aw.w;
	}
	// Petals fold up toward the head while dormant.
	float bloom = 0.15 + 0.85 * v_restore;
	float fold = (1.0 - bloom) * COLOR.a * bloom_fold;
	if (fold > 0.0) {
		// UV holds the Blender-space XY offset from the flower head (V is flipped by glTF).
		vec2 off = vec2(UV.x, -(1.0 - UV.y));
		float r = length(off);
		vec3 local_shift = vec3(-off.x * fold * 0.6, r * fold * 0.75, -off.y * fold * 0.6);
		VERTEX += mat3(MODEL_MATRIX) * local_shift;
	}
	float sway = COLOR.g;
	v_sway = sway;
	VERTEX += wind_offset(root, sway, wind_stiffness, TIME) * wind_amplitude * obj_scale;
	if (player_push > 0.0) {
		vec3 away = VERTEX - player_position;
		float d = length(away.xz);
		float push = (1.0 - smoothstep(0.3, 1.4, d)) * sway * player_push * step(abs(away.y), 2.0);
		VERTEX.xz += normalize(away.xz + vec2(0.001)) * push * 0.6;
		VERTEX.y -= push * 0.25;
	}
	v_ao = COLOR.r;
	v_world = VERTEX;
	v_var = 1.0 + (COLOR.b - 0.5) * variation * 2.0;
	v_part = COLOR.b;
}

void fragment() {
	float cam_dist = length(VERTEX);
	float keep = foliage_near_fade > 0.0 ? smoothstep(near_fade_start * foliage_near_fade, near_fade_end * foliage_near_fade, cam_dist) : 1.0;
	// Keep the line of sight from the camera to the robot clear.
	vec3 target = player_position + vec3(0.0, 0.35, 0.0);
	vec3 seg = target - CAMERA_POSITION_WORLD;
	float seg_len2 = max(dot(seg, seg), 0.0001);
	float t = clamp(dot(v_world - CAMERA_POSITION_WORLD, seg) / seg_len2, 0.0, 1.0);
	float line_d = distance(v_world, CAMERA_POSITION_WORLD + seg * t);
	float occluding = (1.0 - smoothstep(0.45, 1.25, line_d)) * (1.0 - smoothstep(0.8, 0.97, t)) * step(seg_len2, 144.0);
	keep = min(keep, 1.0 - occluding * 0.92);
	if (keep < 0.999) {
		float dither = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (keep < dither) {
			discard;
		}
	}
	vec3 live = v_tint * v_var;
	vec3 dormant = mix(desaturate(live, 0.55), dormant_color, 0.35);
	vec3 col = mix(live, dormant, dormant_mix * (1.0 - v_restore));
	col *= mix(1.0, mix(0.72, 1.18, v_sway), tip_gradient);
	if (dry_amount > 0.0) {
		// Some blades yellow toward the tip; slight hue drift on the rest.
		float dry = smoothstep(0.45, 1.0, v_sway) * smoothstep(0.55, 0.95, fract(v_part * 7.31)) * dry_amount;
		col = mix(col, dry_color * mix(0.85, 1.1, v_part), dry);
		col *= mix(vec3(1.0), vec3(1.06, 1.0, 0.86), smoothstep(0.3, 0.7, fract(v_part * 3.7)) * 0.6);
	}
	if (normal_up_bias > 0.0) {
		vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		// NORMAL is already flipped for back faces on double-sided materials.
		NORMAL = normalize(mix(NORMAL, up_view, normal_up_bias));
	}
	ALBEDO = col * mix(0.45, 1.0, v_ao) * cloud_shadow(v_world);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
	BACKLIGHT = col * backlight_amount;
	EMISSION = SCAN_COLOR * scan_ring(v_world) * 0.8 + col * emission_amount * (0.2 + 0.8 * v_restore);
}
