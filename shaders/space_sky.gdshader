shader_type sky;
// Deep space for the facility: layered star field with twinkle, soft nebula clouds, and an
// optional distant planet with an atmosphere rim (seen through the station's windows).

uniform vec3 nebula_a : source_color = vec3(0.22, 0.1, 0.38);
uniform vec3 nebula_b : source_color = vec3(0.05, 0.22, 0.35);
uniform float nebula_amount : hint_range(0.0, 1.0) = 0.6;
uniform float star_density = 1.0;
uniform vec3 planet_dir = vec3(0.4, 0.15, -0.9);
uniform float planet_size = 0.0;
uniform vec3 planet_color : source_color = vec3(0.35, 0.55, 0.85);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float stars(vec3 dir, float scale, float threshold) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash3(cell);
	float s = step(threshold, h);
	vec3 offset = vec3(hash3(cell + 1.7), hash3(cell + 3.1), hash3(cell + 5.3)) - 0.5;
	float d = length(f - offset * 0.6);
	float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
	return s * (1.0 - smoothstep(0.0, 0.08, d)) * twinkle * (0.4 + h);
}

void sky() {
	vec3 dir = EYEDIR;
	vec2 uv = vec2(atan(dir.x, dir.z) / 6.2832, dir.y * 0.5 + 0.5);
	float n1 = texture(noise_tex, uv * vec2(2.0, 1.0) + vec2(0.13, 0.0)).r;
	float n2 = texture(noise_tex, uv * vec2(4.0, 2.0) + vec2(0.5, 0.3)).r;
	float band = exp(-pow(dir.y * 2.2 - 0.3 * sin(uv.x * 12.0), 2.0));
	vec3 col = vec3(0.004, 0.005, 0.012);
	float neb = smoothstep(0.35, 0.85, n1 * 0.7 + n2 * 0.4) * band * nebula_amount;
	col += mix(nebula_a, nebula_b, n2) * neb * 0.5;
	col += vec3(1.0, 0.97, 0.92) * stars(dir, 120.0 * star_density, 0.985) * 1.4;
	col += vec3(0.8, 0.9, 1.0) * stars(dir, 260.0 * star_density, 0.992) * 0.9;
	if (planet_size > 0.0) {
		vec3 pd = normalize(planet_dir);
		float a = acos(clamp(dot(dir, pd), -1.0, 1.0));
		float disc = 1.0 - smoothstep(planet_size - 0.004, planet_size, a);
		float rim = smoothstep(planet_size - 0.03, planet_size, a) * (1.0 - smoothstep(planet_size, planet_size + 0.03, a));
		float lit = clamp(dot(normalize(dir - pd * cos(a)), normalize(vec3(-1.0, 0.4, 0.2))) * 0.8 + 0.3, 0.0, 1.0);
		float bands2 = texture(noise_tex, vec2(a * 4.0, dot(dir, vec3(0.0, 1.0, 0.0)) * 3.0)).r;
		col = mix(col, planet_color * lit * (0.6 + bands2 * 0.5), disc);
		col += planet_color * rim * 1.2;
	}
	COLOR = col;
}
