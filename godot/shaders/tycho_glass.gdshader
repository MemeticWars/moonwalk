shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

void fragment() {
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 4.0);
	ALBEDO = mix(vec3(0.48, 0.68, 0.75), vec3(0.72, 0.86, 0.94), fresnel);
	ROUGHNESS = 0.1;
	METALLIC = 0.05;
	SPECULAR = 0.8;
	ALPHA = 0.045 + 0.24 * fresnel;
}
