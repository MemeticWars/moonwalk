shader_type spatial;
render_mode cull_disabled;

// The beech source places orange leaf pixels and blue-grey trunk pixels in a
// shared atlas. Its orange chroma is a reliable leaf mask, so leaves and woody
// parts can receive distinct materials without splitting the source mesh.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool use_normal = true;
uniform vec3 bark_silver : source_color = vec3(0.82, 0.85, 0.92);
uniform vec3 leaf_green : source_color = vec3(0.31, 0.49, 0.20);
uniform float glow : hint_range(0.0, 1.0) = 0.08;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float l = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	// Leaves are the only strongly red/orange source pixels. The transition band
	// preserves anti-aliased edges where leaf cards meet branch geometry.
	float leaf_mask = smoothstep(0.13, 0.32, tex.r - max(tex.g, tex.b));
	vec3 bark = vec3(pow(l, 0.72)) * bark_silver;
	vec3 leaves = mix(vec3(pow(l, 0.68)), tex.rgb, 0.14) * leaf_green;
	vec3 base = mix(bark, leaves, leaf_mask);
	ALBEDO = base;
	METALLIC = mix(0.18, 0.0, leaf_mask);
	ROUGHNESS = mix(0.48, 0.72, leaf_mask);
	EMISSION = base * glow * leaf_mask;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
