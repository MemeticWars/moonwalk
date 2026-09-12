shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
varying vec3 shell_position;
void vertex() { shell_position = VERTEX; }
void fragment() {
    // Agnes owns the neck ring and the volume occupied by her head.
    // Trim only the accessory; never erase the character or bypass depth testing.
    if (shell_position.y < -0.66) { discard; }
    // The smaller shell rides forward of the face; the head carve follows it back
    // and grows to keep the skull clear of the inner wall.
    vec3 inner = (shell_position - vec3(0.0, 0.08, -0.12)) / vec3(0.51, 0.73, 0.50);
    if (dot(inner, inner) < 1.0) { discard; }
    ALBEDO = texture(albedo_map, UV).rgb * 0.82;
    NORMAL_MAP = texture(normal_map, UV).rgb;
    NORMAL_MAP_DEPTH = 0.45;
    METALLIC = 0.08;
    ROUGHNESS = 0.68;
}
