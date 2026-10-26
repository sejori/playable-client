shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec4 albedo_color : source_color = vec4(0.85, 0.32, 0.12, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.68, 0.22, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float metallic_factor : hint_range(0.0, 1.0) = 0.65;
uniform float roughness_factor : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	ALBEDO = albedo_color.rgb;
	METALLIC = metallic_factor;
	ROUGHNESS = roughness_factor;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * fresnel * 0.45;
}
