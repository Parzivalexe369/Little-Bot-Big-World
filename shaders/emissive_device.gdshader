shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Lights and energy lines on machines. Each device sets its own "power" (0 off .. 1 on)
// through an instance uniform, so one shared material serves every machine.

#include "res://shaders/includes/world_common.gdshaderinc"

uniform vec3 glow_color : source_color = vec3(0.35, 0.95, 1.0);
uniform vec3 off_color : source_color = vec3(0.12, 0.16, 0.18);
uniform float glow_energy = 3.0;
uniform float flow_speed = 0.0;
instance uniform float power = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float flow = flow_speed > 0.0 ? 0.75 + 0.25 * sin(TIME * flow_speed - (v_world.x + v_world.z) * 1.5) : 1.0;
	ALBEDO = mix(off_color, glow_color * 0.6, power);
	ROUGHNESS = 0.35;
	EMISSION = glow_color * glow_energy * power * flow + glow_color * 0.05 * (1.0 - power) + SCAN_COLOR * scan_ring(v_world) * 0.5;
}
