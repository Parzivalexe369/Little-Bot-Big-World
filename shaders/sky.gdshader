shader_type sky;
// Sky: vertical gradient with a brighter, hazier horizon band, warm forward-scattered sun
// glow, and three-octave cumulus clouds that are self-shadowed (density sampled toward the
// sun darkens undersides) with silver linings near the sun. Colors are driven per area by
// the AtmosphereController.

uniform vec3 top_color : source_color = vec3(0.32, 0.55, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.82, 0.86, 0.86);
uniform vec3 ground_color : source_color = vec3(0.42, 0.46, 0.4);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.85, 0.62);
uniform float sun_glow_size = 0.12;
uniform vec3 cloud_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow_color : source_color = vec3(0.6, 0.65, 0.74);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform sampler2D cloud_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;

float cloud_density(vec2 uv, vec2 wind) {
	float n1 = texture(cloud_noise, uv * 0.16 + wind).r;
	float n2 = texture(cloud_noise, uv * 0.42 - wind * 1.5).r;
	float n3 = texture(cloud_noise, uv * 1.15 + wind * 2.2).r;
	float n = n1 * 0.62 + n2 * 0.28 + n3 * 0.1;
	return smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.3, n);
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(clamp(h, 0.0, 1.0), 0.45);
		col = mix(horizon_color, top_color, t);
		// Haze band: the thickest air sits right on the horizon.
		col = mix(col, horizon_color * 1.06, (1.0 - smoothstep(0.0, 0.08, h)) * 0.5);
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 3.0, 0.0, 1.0));
	}

	vec3 sun_dir = vec3(0.0, 1.0, 0.0);
	float sun_energy = 1.0;
	if (LIGHT0_ENABLED) {
		sun_dir = LIGHT0_DIRECTION;
		sun_energy = LIGHT0_ENERGY;
	}
	float sd = dot(dir, sun_dir);

	if (!AT_CUBEMAP_PASS && h > 0.0) {
		// Clouds projected onto a dome.
		vec2 uv = dir.xz / (h + 0.14);
		vec2 wind = vec2(TIME * 0.004, TIME * 0.0015);
		float density = cloud_density(uv, wind);
		if (density > 0.001) {
			// March a short step toward the sun: denser there = this point is in the cloud's shade.
			vec2 toward_sun = normalize(sun_dir.xz + vec2(0.0001)) * 0.9;
			float occl = cloud_density(uv + toward_sun, wind) * 0.6 + cloud_density(uv + toward_sun * 2.2, wind) * 0.4;
			vec3 lit = mix(cloud_color, cloud_shadow_color, clamp(occl * 0.85, 0.0, 1.0));
			// Thin edges near the sun glow (silver lining).
			float silver = pow(max(sd, 0.0), 6.0) * (1.0 - density) * 1.6;
			lit += sun_glow_color * silver;
			lit *= mix(0.92, 1.05, smoothstep(0.0, 0.6, h));
			float fade = smoothstep(0.0, 0.16, h);
			col = mix(col, lit, density * fade * 0.9);
		}
	} else if (h > 0.0) {
		col = mix(col, cloud_color, cloud_coverage * 0.25 * smoothstep(0.0, 0.3, h));
	}

	// Sun disc + forward-scattered glow.
	if (LIGHT0_ENABLED) {
		float glow = pow(max(sd, 0.0), 1.0 / max(sun_glow_size, 0.001) * 4.0);
		float halo = pow(max(sd, 0.0), 24.0) * 0.18;
		col += sun_glow_color * (glow * 0.6 + halo) * sun_energy * 0.5;
		col += sun_glow_color * smoothstep(0.9994, 0.9998, sd) * 4.0;
	}
	COLOR = col;
}
