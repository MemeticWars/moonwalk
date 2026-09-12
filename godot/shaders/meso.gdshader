shader_type spatial;
render_mode cull_disabled;
uniform sampler2D lunar_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float growth = 1.0;
uniform float detail_blend = 0.0;
uniform vec2 anchor = vec2(0.0);
uniform bool local_frame = false;
uniform vec4 local_hole = vec4(0.0);
varying vec2 local_metres;
varying vec3 radial_direction;
void vertex() {
    // Child vertices start on the parent surface, then rise into measured relief.
    VERTEX = normalize(VERTEX) * (mix(UV.x, UV.y, growth) + mix(UV2.y, UV2.x, growth) * detail_blend);
    NORMAL = normalize(mix(NORMAL,COLOR.rgb*2.0-1.0,detail_blend));
    vec3 n = normalize(VERTEX);
    radial_direction = n;
    float lat = asin(clamp(n.y, -1.0, 1.0));
    float lon = atan(n.x, n.z);
    float dl = mod(lon - anchor.y + PI, 2.0 * PI) - PI;
    local_metres = vec2(dl * 1737400.0 * cos(anchor.x), (anchor.x-lat)*1737400.0);
}
float dissolve_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
    vec3 n = normalize(radial_direction);
    vec2 map_uv = vec2(atan(n.x,n.z) / (2.0*PI) + 0.5, 0.5 - asin(clamp(n.y,-1.0,1.0))/PI);
    vec3 map = texture(lunar_albedo, map_uv).rgb;
    ALBEDO = map;
    ROUGHNESS = 1.0;
    if (local_frame && local_hole.z > local_hole.x) {
        // Signed inset from the hole's nearest edge: >0 once inside on both
        // axes (matches the old unconditional cut), <0 outside. Feathering
        // this instead of discarding on a single boundary line softens the
        // photographic mezo texture into the local terrain's procedural
        // regolith -- the two are different data (blurry LROC colour vs.
        // crisp synthetic grain), so a hard line reads as a style pop no
        // matter how well the geometry lines up.
        float inside_x = min(local_metres.x - local_hole.x, local_hole.z - local_metres.x);
        float inside_y = min(local_metres.y - local_hole.y, local_hole.w - local_metres.y);
        float inside_depth = min(inside_x, inside_y);
        const float FEATHER = 40.0;
        if (inside_depth > -FEATHER) {
            // 1 well outside the hole (unchanged), 0 once FEATHER metres
            // inside it (always cut, same as the old edge).
            float visibility = clamp(0.5 - inside_depth / (2.0 * FEATHER), 0.0, 1.0);
            if (visibility <= 0.0) {
                discard;
            } else {
                ALBEDO = mix(vec3(0.30, 0.29, 0.27), ALBEDO, visibility);
                if (dissolve_hash(floor(local_metres * 0.6)) > visibility) discard;
            }
        }
    }
}
