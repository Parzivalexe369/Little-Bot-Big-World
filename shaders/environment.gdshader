shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Static props: stone, rock, bark, wood, metal, mushrooms. Optional photoscanned PBR set
// (Poly Haven CC0) projected triplanar in object space (so moving props don't swim),
// baked AO from vertex color, optional textured moss on upward faces that greens up with
// restoration, optional glow (mushroom caps) and the scanner ring.

#include "res://shaders/includes/world_common.gdshaderinc"

uniform vec3 albedo_color : source_color = vec3(0.6, 0.58, 0.54);
uniform vec3 albedo_color_2 : source_color = vec3(0.5, 0.48, 0.45);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moss_color : source_color = vec3(0.3, 0.48, 0.18);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float emission_dormant = 0.15;
uniform float noise_scale = 0.35;
uniform float desaturate_dormant : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

// Surface scan. tex_photo 1 = use the scan's own colors (times tex_tint); 0 = keep the flat
// palette and only borrow the scan's luminance detail (painted metal, mushroom caps).
uniform bool use_textures = false;
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.5;          // tiles per metre
uniform float tex_photo : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tex_tint : source_color = vec3(1.0);
uniform float tex_avg_lum = 0.35;       // mean luminance of the scan, for detail-only mode
uniform float tex_normal_strength = 1.0;
uniform float tex_rough_mix : hint_range(0.0, 1.0) = 1.0;
uniform float tex_metal_mix : hint_range(0.0, 1.0) = 0.0;
uniform float tex_sharpness = 4.0;

uniform bool use_moss_texture = false;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_scale = 0.6;

varying vec3 v_world;
varying vec3 v_world_normal;
varying vec3 v_obj;
varying vec3 v_obj_normal;
varying float v_restore;
// Instance basis (MultiMesh instance transforms only exist in vertex()).
varying vec3 v_basis_x;
varying vec3 v_basis_y;
varying vec3 v_basis_z;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	// Object-space position in metres, offset per instance so repeated props differ.
	v_obj = VERTEX * scale + vec3(fract(root.x * 0.137) * 7.0, fract(root.y * 0.071) * 5.0, fract(root.z * 0.113) * 7.0);
	v_obj_normal = NORMAL;
	v_basis_x = MODEL_MATRIX[0].xyz / max(scale.x, 0.0001);
	v_basis_y = MODEL_MATRIX[1].xyz / max(scale.y, 0.0001);
	v_basis_z = MODEL_MATRIX[2].xyz / max(scale.z, 0.0001);
	v_restore = restore_at(root.xz);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(tex_sharpness));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec3 unpack_n(vec3 c, float strength) {
	vec3 n = c * 2.0 - 1.0;
	n.xy *= strength;
	return n;
}

// Whiteout triplanar normal in the space of `n` (object space here).
vec3 tri_normal(sampler2D tex, vec3 p, vec3 n, vec3 w, float scale, float strength) {
	vec3 tx = unpack_n(texture(tex, p.zy * scale).rgb, strength);
	vec3 ty = unpack_n(texture(tex, p.xz * scale).rgb, strength);
	vec3 tz = unpack_n(texture(tex, p.xy * scale).rgb, strength);
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

vec3 tri_color(sampler2D tex, vec3 p, vec3 w, float scale) {
	return texture(tex, p.zy * scale).rgb * w.x + texture(tex, p.xz * scale).rgb * w.y + texture(tex, p.xy * scale).rgb * w.z;
}

void fragment() {
	vec3 n = abs(v_world_normal);
	float nx = texture(noise_tex, v_world.zy * noise_scale).r;
	float ny = texture(noise_tex, v_world.xz * noise_scale).r;
	float nz = texture(noise_tex, v_world.xy * noise_scale).r;
	float noise = (nx * n.x + ny * n.y + nz * n.z) / max(n.x + n.y + n.z, 0.001);
	vec3 col = mix(albedo_color_2, albedo_color, smoothstep(0.25, 0.75, noise));
	float rough = roughness_value;
	float metal = metallic_value;
	float ao = 1.0;
	vec3 n_obj = normalize(v_obj_normal);
	vec3 nrm_obj = n_obj;

	if (use_textures) {
		vec3 w = tri_weights(n_obj);
		vec3 t_col = tri_color(tex_albedo, v_obj, w, tex_scale);
		vec3 t_arm = tri_color(tex_arm, v_obj, w, tex_scale);
		nrm_obj = tri_normal(tex_normal, v_obj, n_obj, w, tex_scale, tex_normal_strength);
		float lum = dot(t_col, vec3(0.299, 0.587, 0.114));
		vec3 detail_col = col * clamp(lum / max(tex_avg_lum, 0.05), 0.3, 1.8);
		vec3 photo_col = t_col * tex_tint * mix(0.85, 1.1, noise);
		col = mix(detail_col, photo_col, tex_photo);
		rough = mix(rough, t_arm.g, tex_rough_mix);
		metal = mix(metal, t_arm.b, tex_metal_mix);
		ao = t_arm.r;
	}

	// Baked cavity AO from the Blender vertex colors.
	col *= mix(0.55, 1.0, COLOR.r);
	col = mix(col, desaturate(col, 0.6), desaturate_dormant * (1.0 - v_restore));

	if (moss_amount > 0.0) {
		// Moss gathers on world-up faces (rain and light come from above), broken up by noise.
		float up = smoothstep(0.35, 0.8, v_world_normal.y + (noise - 0.5) * 0.5) * moss_amount;
		if (up > 0.01) {
			vec3 moss = mix(desaturate(moss_color, 0.5) * 0.9, moss_color, 0.3 + 0.7 * v_restore);
			vec3 moss_col = moss * (0.8 + noise * 0.4);
			if (use_moss_texture) {
				vec3 w = tri_weights(n_obj);
				vec3 m_tex = tri_color(moss_albedo, v_obj, w, moss_scale);
				float m_lum = dot(m_tex, vec3(0.299, 0.587, 0.114));
				moss_col = mix(desaturate(m_tex, 0.55) * 0.95, m_tex, 0.3 + 0.7 * v_restore) * 1.15;
				vec3 m_nrm = tri_normal(moss_normal, v_obj, n_obj, w, moss_scale, 1.0);
				// Height-ish blend: moss fills crevices first.
				up = smoothstep(0.2, 0.8, up + (m_lum - 0.3) * 0.6);
				nrm_obj = normalize(mix(nrm_obj, m_nrm, up));
			}
			col = mix(col, moss_col, up);
			rough = mix(rough, 0.95, up);
			metal = mix(metal, 0.0, up);
		}
	}

	ALBEDO = col * cloud_shadow(v_world);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	if (use_textures || use_moss_texture) {
		vec3 nrm_world = normalize(mat3(v_basis_x, v_basis_y, v_basis_z) * nrm_obj);
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm_world, 0.0)).xyz);
	}
	EMISSION = emission_color * emission_energy * mix(emission_dormant, 1.0, v_restore) + SCAN_COLOR * scan_ring(v_world) * 0.7;
}
