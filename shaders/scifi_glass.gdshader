shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Lab glass: refracts what is behind it (screen texture offset by the normal), tinted by
// thickness at grazing angles, Fresnel reflection, faint smudges, and optional cracks.

uniform vec3 tint : source_color = vec3(0.75, 0.9, 0.95);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.25;
uniform float refraction = 0.025;
uniform float crack_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 inner_glow : source_color = vec3(0.0);
uniform float inner_glow_energy = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	float smudge = texture(noise_tex, v_world.xy * 0.7 + v_world.zz * 0.5).r;
	vec2 offset = NORMAL.xy * refraction * (0.6 + smudge * 0.8);
	// Cracks: thin bright lines from a ridged noise.
	float crack = 0.0;
	if (crack_amount > 0.0) {
		float r = abs(texture(noise_tex, v_world.xy * 0.9 + v_world.zx * 0.3).r - 0.5);
		crack = (1.0 - smoothstep(0.004, 0.02, r)) * crack_amount;
		offset += vec2(crack * 0.01);
	}
	vec3 behind = textureLod(screen_texture, SCREEN_UV + offset, 1.0).rgb;
	vec3 col = mix(behind, behind * tint, tint_strength + fres * 0.4);
	ALBEDO = vec3(0.0);
	EMISSION = col * (1.0 - fres * 0.35) + inner_glow * inner_glow_energy * (0.4 + fres) + vec3(crack * 0.6);
	ROUGHNESS = 0.04 + smudge * 0.05 + crack * 0.3;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = 1.0;
}
