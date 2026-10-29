shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural tech-grid floor for the arena zone.
uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.24);
uniform vec3 line_color : source_color = vec3(0.35, 0.72, 0.95);
uniform float grid_scale = 1.0;
uniform float line_width = 0.015;
uniform float emission_strength = 0.35;

void fragment() {
	vec2 uv = UV * grid_scale;
	vec2 g = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	float line = 1.0 - min(min(g.x, g.y) / (line_width * 60.0), 1.0);

	ALBEDO = mix(base_color, line_color, line * 0.5);
	EMISSION = line_color * line * emission_strength;
	ROUGHNESS = 0.72;
	METALLIC = 0.15;
}
