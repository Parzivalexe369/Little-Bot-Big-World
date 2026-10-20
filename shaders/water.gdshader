shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Calm water, physically motivated: the refracted bed is attenuated per channel by depth
// (red dies first), in-scattered light tints deeper water, the sky/SSR reflection comes from
// the specular term with Fresnel. Three octaves of drifting ripples, a soft wet shoreline
// (alpha fades in the first few centimetres), a ripple ring around the hovering robot and
// the scanner ring.

#include "res://shaders/includes/world_common.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.36, 0.58, 0.52);   // in-scatter tint
uniform vec3 deep_color : source_color = vec3(0.05, 0.16, 0.19);
uniform vec3 absorption = vec3(0.55, 0.2, 0.14);                      // extinction per metre
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.9);
uniform vec2 flow = vec2(0.02, 0.01);
uniform float ripple_strength = 1.0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Ponds are discs: fade out before the disc's rim so it never shows as a polygon edge.
instance uniform float edge_radius = 0.0;

varying vec3 v_world;
varying vec2 v_center;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center = MODEL_MATRIX[3].xz;
}

// Gradient of the noise height field, in noise units per uv unit.
vec2 noise_grad(vec2 uv) {
	const float e = 1.0 / 512.0;
	float c = texture(noise_tex, uv).r;
	return vec2(texture(noise_tex, uv + vec2(e, 0.0)).r - c, texture(noise_tex, uv + vec2(0.0, e)).r - c) / e;
}

float view_depth(vec2 screen_uv, mat4 inv_proj) {
	float d = texture(depth_texture, screen_uv).r;
	vec4 p = inv_proj * vec4(screen_uv * 2.0 - 1.0, d, 1.0);
	return -p.z / p.w;
}

void fragment() {
	// Ripples: slope = d(height)/d(metre) for three octaves (scale, amplitude in metres).
	vec2 slope = noise_grad(v_world.xz * 0.11 + TIME * flow) * 0.11 * 0.06;
	slope += noise_grad(v_world.xz * 0.37 - TIME * flow * 2.3 + vec2(0.37, 0.71)) * 0.37 * 0.02;
	slope += noise_grad(v_world.xz * 1.1 + TIME * vec2(-flow.y, flow.x) * 3.1 + vec2(0.13, 0.5)) * 1.1 * 0.006;
	slope *= ripple_strength;

	// Robot ripples.
	vec2 to_player = v_world.xz - player_position.xz;
	float pd = length(to_player);
	float near_water = step(abs(player_position.y - v_world.y), 1.2);
	float rings = sin(pd * 9.0 - TIME * 7.0) * 0.5 + 0.5;
	float ring_mask = (1.0 - smoothstep(0.3, 2.2, pd)) * near_water;
	slope += to_player / max(pd, 0.001) * cos(pd * 9.0 - TIME * 7.0) * ring_mask * 0.12;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));

	// Water thickness along the view ray.
	float surface_depth = -VERTEX.z;
	float bed_depth = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = clamp(bed_depth - surface_depth, 0.0, 30.0);

	// Refraction: offset grows with thickness; reject samples of things in front of the water.
	vec2 refr_uv = SCREEN_UV + n_world.xz * 0.035 * clamp(thickness, 0.0, 1.0);
	float refr_bed = view_depth(refr_uv, INV_PROJECTION_MATRIX);
	if (refr_bed < surface_depth) {
		refr_uv = SCREEN_UV;
		refr_bed = bed_depth;
	}
	float refr_thickness = clamp(refr_bed - surface_depth, 0.0, 30.0);
	vec3 bed = texture(screen_texture, refr_uv).rgb;
	vec3 transmittance = exp(-absorption * refr_thickness);
	float scatter = 1.0 - exp(-refr_thickness * 0.45);
	vec3 scatter_col = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, scatter));

	vec3 view_dir = normalize(-VERTEX);
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(n_view, view_dir), 0.0, 1.0), 5.0);

	// Thin, broken wet line at the shore (still ponds have no surf).
	float n1 = texture(noise_tex, v_world.xz * 0.25 + TIME * flow).r;
	float foam = (1.0 - smoothstep(0.0, 0.06 + n1 * 0.08, thickness)) * smoothstep(0.4, 0.7, n1) * 0.3;
	foam += rings * ring_mask * 0.18;

	NORMAL = n_view;
	ALBEDO = mix(scatter_col * scatter, foam_color, clamp(foam, 0.0, 1.0));
	ROUGHNESS = mix(0.03, 0.4, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.4;
	EMISSION = bed * transmittance * (1.0 - fresnel) * (1.0 - clamp(foam, 0.0, 1.0)) + SCAN_COLOR * scan_ring(v_world) * 0.6;
	float edge = 1.0;
	if (edge_radius > 0.0) {
		edge = 1.0 - smoothstep(edge_radius - 1.4, edge_radius, length(v_world.xz - v_center));
	}
	ALPHA = smoothstep(0.0, 0.06, thickness) * edge;
}
