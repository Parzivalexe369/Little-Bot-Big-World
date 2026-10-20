// Shared world shader helpers: scan pulse ring, restoration lookup, wind.
// Global uniforms are declared in project.godot [shader_globals].

global uniform vec4 restore_levels;   // x meadow, y forest, z shrine, w garden (0 dormant .. 1 restored)
global uniform vec3 scan_origin;
global uniform float scan_time;       // seconds since the last scan pulse
global uniform float wind_strength;
global uniform vec3 player_position;
global uniform float world_awake;     // 0..1, set by the final restoration
global uniform float foliage_near_fade; // 1 = plants near the camera dissolve (gameplay), 0 = off (menu stills)

const float SCAN_SPEED = 22.0;
const float SCAN_RADIUS = 26.0;
const vec3 SCAN_COLOR = vec3(0.35, 0.95, 1.0);

// Bright ring sweeping outward from the robot, plus a faint afterglow inside it.
float scan_ring(vec3 world_pos) {
	float front = scan_time * SCAN_SPEED;
	if (front > SCAN_RADIUS + 4.0) {
		return 0.0;
	}
	float d = distance(world_pos, scan_origin);
	float fade = 1.0 - smoothstep(SCAN_RADIUS * 0.6, SCAN_RADIUS + 2.0, front);
	float ring = 1.0 - smoothstep(0.0, 1.6, abs(d - front));
	float inner = (1.0 - smoothstep(0.0, front, d)) * step(d, front) * 0.12;
	return (ring + inner) * fade * step(d, SCAN_RADIUS + 1.0);
}

// Area blobs (must match WorldLayout.AREAS): xy = center (world x, z), z = radius.
const vec3 AREA_MEADOW = vec3(0.0, 14.0, 64.0);
const vec3 AREA_FOREST = vec3(-30.0, -124.0, 62.0);
const vec3 AREA_SHRINE = vec3(30.0, -266.0, 38.0);
const vec3 AREA_GARDEN = vec3(-6.0, -398.0, 66.0);

float _area_w(vec2 p, vec3 a) {
	float d = distance(p, a.xy) / a.z;
	return exp(-d * d * 3.0);
}

// Soft weights of the four areas at a world position, summing to 1.
vec4 area_weights_at(vec2 p) {
	vec4 w = vec4(_area_w(p, AREA_MEADOW), _area_w(p, AREA_FOREST), _area_w(p, AREA_SHRINE), _area_w(p, AREA_GARDEN));
	return w / max(w.x + w.y + w.z + w.w, 0.00001);
}

float restore_at(vec2 p) {
	return clamp(dot(area_weights_at(p), restore_levels), 0.0, 1.0);
}

// Restoration level for a set of area weights (meadow, forest, shrine, garden).
float restore_for(vec4 area_weights) {
	return clamp(dot(area_weights, restore_levels), 0.0, 1.0);
}

vec3 desaturate(vec3 c, float amount) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, vec3(l), amount);
}

// Horizontal wind offset for a point at a given height above its root.
vec3 wind_offset(vec3 world_root, float height01, float stiffness, float time) {
	float phase = dot(world_root.xz, vec2(0.11, 0.07));
	float gust = sin(time * 0.6 + world_root.x * 0.02) * 0.5 + 0.5;
	float sway = sin(time * 1.7 + phase) * 0.6 + sin(time * 2.9 + phase * 1.7) * 0.25;
	float amount = (0.35 + gust * 0.65) * wind_strength / max(stiffness, 0.05);
	vec2 dir = normalize(vec2(1.0, 0.45));
	return vec3(dir.x, 0.0, dir.y) * sway * amount * height01 * height01;
}

float _hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(_hash12(i), _hash12(i + vec2(1.0, 0.0)), u.x), mix(_hash12(i + vec2(0.0, 1.0)), _hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Large soft cloud shadows drifting across the land (multiplied into albedo by terrain,
// plants and props so they stay consistent). Weaker under the forest canopy.
float cloud_shadow(vec3 wp) {
	vec2 p = wp.xz * 0.012 + vec2(TIME * 0.035, TIME * 0.012);
	float n = _vnoise(p) * 0.65 + _vnoise(p * 2.3 + vec2(7.1, 3.7)) * 0.35;
	float shade = smoothstep(0.5, 0.74, n);
	float forest = area_weights_at(wp.xz).y;
	return 1.0 - shade * 0.24 * (1.0 - forest * 0.75);
}
