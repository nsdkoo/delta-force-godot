shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float pixel_height = 720.0;

void fragment() {
	vec2 resolution = vec2(pixel_height * SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, pixel_height);
	vec2 coordinate = (floor(SCREEN_UV * resolution) + 0.5) / resolution;
	vec3 sampled = texture(screen_texture, coordinate).rgb;
	float pattern = mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) * 0.006;
	sampled = floor((sampled + pattern) * 40.0) / 40.0;
	COLOR = vec4(sampled, 1.0);
}
