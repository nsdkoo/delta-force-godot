shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 world_position;

float hash(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 value) {
	vec2 cell = floor(value);
	vec2 blend = fract(value);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), blend.x), mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), blend.x), blend.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pos = world_position.xz;
	float patch = noise(pos * 0.22) * 0.7 + noise(pos * 0.65) * 0.3;
	vec3 dust = mix(vec3(0.12, 0.29, 0.12), vec3(0.34, 0.51, 0.16), smoothstep(0.15, 0.85, patch));
	vec3 grass = vec3(0.08, 0.31, 0.16);
	float growth = smoothstep(0.25, 0.79, noise(pos * 0.29 + vec2(31, 4)));
	float grain = hash(floor(pos * 35.0));
	ALBEDO = mix(dust, grass, growth * 0.82) + (grain - 0.5) * 0.022;
	ROUGHNESS = 0.96;
	NORMAL_MAP = vec3(0.5 + (grain - 0.5) * 0.06, 0.5, 1.0);
}
