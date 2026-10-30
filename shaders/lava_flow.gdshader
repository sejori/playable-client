shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 lava_color_hot : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 lava_color_crust : source_color = vec4(0.18, 0.06, 0.04, 1.0);
uniform float flow_speed : hint_range(0.01, 2.0) = 0.35;
uniform float wave_amplitude : hint_range(0.0, 1.0) = 0.15;
uniform float wave_frequency : hint_range(0.1, 5.0) = 1.2;

void vertex() {
	float wave = sin(VERTEX.x * wave_frequency + TIME * flow_speed) * cos(VERTEX.z * wave_frequency + TIME * flow_speed * 0.8);
	VERTEX.y += wave * wave_amplitude;
}

void fragment() {
	vec2 uv_flow = UV + vec2(TIME * flow_speed * 0.1, TIME * flow_speed * 0.05);
	float n = sin(uv_flow.x * 12.0) * cos(uv_flow.y * 12.0) * 0.5 + 0.5;
	vec3 col = mix(lava_color_crust.rgb, lava_color_hot.rgb, n);

	ALBEDO = col;
	ROUGHNESS = 0.35;
	EMISSION = lava_color_hot.rgb * (n * 1.8);
}
