shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
// Faceted crystals: deep core color, bright fresnel edges, slow inner pulse, and fake
// internal depth (inclusion veils sampled at several depths along the view ray, so they
// parallax inside the gem as the camera moves).
// Dim while dormant, radiant once their area is restored (or when powered).

#include "res://shaders/includes/world_common.gdshaderinc"

uniform vec3 core_color : source_color = vec3(0.45, 0.3, 0.85);
uniform vec3 edge_color : source_color = vec3(0.85, 0.75, 1.0);
uniform float glow_energy = 1.6;
uniform float dormant_glow = 0.18;
// -1 = follow area restoration, otherwise explicit power 0..1 (set per device).
instance uniform float power = -1.0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_world;
varying float v_restore;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_restore = restore_at(root.xz);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 2.5);
	float level = power >= 0.0 ? power : v_restore;
	float pulse = 0.85 + 0.15 * sin(TIME * 1.3 + v_world.x * 0.3 + v_world.z * 0.2);
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float inner = 0.0;
	for (int i = 1; i <= 3; i++) {
		vec3 p = v_world - view_w * float(i) * 0.3;
		inner += texture(noise_tex, p.xz * 0.32 + vec2(p.y * 0.23, -p.y * 0.17)).r / float(i);
	}
	inner /= 1.833;
	float veils = smoothstep(0.42, 0.72, inner);
	vec3 base = mix(core_color * 0.4, edge_color, fres) + edge_color * veils * 0.22;
	ALBEDO = base * 0.45;
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.9;
	float glow = mix(dormant_glow, 1.0, level) * glow_energy * pulse;
	EMISSION = (core_color * (0.3 + facing * 0.35 + veils * 0.35) + edge_color * fres * 0.8) * glow + SCAN_COLOR * scan_ring(v_world) * 0.6;
}
