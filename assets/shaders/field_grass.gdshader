shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 player_position = vec3(-100.0);
varying float blade_height;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	blade_height = UV.y;
	float wind = sin(TIME * 1.65 + world_position.x * 0.9 + world_position.z * 0.55);
	VERTEX.x += wind * UV.y * UV.y * 0.14;
	VERTEX.z += cos(TIME * 1.1 + world_position.x * 0.6) * UV.y * 0.06;
	vec2 away = world_position.xz - player_position.xz;
	float influence = 1.0 - smoothstep(0.0, 1.0, length(away));
	VERTEX.xz += normalize(away + vec2(0.001)) * influence * UV.y * 0.4;
	VERTEX.y -= influence * UV.y * 0.12;
}

void fragment() {
	float patch = sin(world_position.x * 0.31 + world_position.z * 0.18) * 0.5 + 0.5;
	vec3 root_color = mix(vec3(0.10, 0.32, 0.18), vec3(0.29, 0.43, 0.12), patch);
	vec3 tip_color = mix(vec3(0.35, 0.63, 0.21), vec3(0.62, 0.75, 0.21), patch);
	ALBEDO = mix(root_color, tip_color, blade_height);
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.08, 0.13, 0.035);
}
