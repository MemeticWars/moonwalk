shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D metallic_texture;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float metallic = 0.0;
uniform float roughness = 0.65;

// Each fish shares the shader but receives its own timing and stroke size.
instance uniform float swim_phase = 0.0;
instance uniform float swim_rate = 5.0;
instance uniform float swim_strength = 1.0;

void vertex() {
	// The prepared fish is 30 cm long on local X, with its head at -X and
	// tail at +X. Keep the head almost still and send a travelling wave down
	// the body, increasing sharply across the caudal fin.
	float along_body = smoothstep(-0.12, 0.15, VERTEX.x);
	float tail = smoothstep(0.015, 0.15, VERTEX.x);
	float stroke = sin(TIME * swim_rate + swim_phase + VERTEX.x * 20.0);
	VERTEX.z += stroke * (0.0035 * along_body + 0.028 * tail * tail) * swim_strength;
	// A small vertical counter-wave prevents the motion from reading as a
	// flat cardboard hinge while retaining the source mesh and textures.
	VERTEX.y += cos(TIME * swim_rate + swim_phase + VERTEX.x * 15.0)
		* 0.0025 * tail * swim_strength;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_tint;
	ALBEDO = base.rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	METALLIC = metallic * texture(metallic_texture, UV).b;
	ROUGHNESS = roughness;
}
