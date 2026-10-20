shader_type canvas_item;
// Soft frosted backdrop for menus over the live game view.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 2.6;

void fragment() {
	vec3 c = textureLod(screen_texture, SCREEN_UV, lod).rgb;
	COLOR = vec4(c * 0.85, 0.75);
}
