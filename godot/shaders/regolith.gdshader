shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool coverage = false;
uniform sampler2D ortho : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_ortho = false;
uniform sampler2D regional_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 region_anchor;
uniform float detail_blend = 1.0;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    VERTEX.y = mix(UV2.x, VERTEX.y, detail_blend);
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
vec2 hash2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
// Centimetre-scale, world-anchored gravel. Fade subpixel stones before aliasing.
vec2 gravel(vec2 p, float footprint) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float mound = 0.0;
    float shade = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 random = hash2(cell + offset);
            vec2 delta = f - offset - random;
            float radius = mix(0.07, 0.24, random.x);
            float d = length(delta * vec2(1.0, 1.45));
            float visibility = 1.0 - smoothstep(radius * 0.35, radius * 1.8, footprint);
            float stone = (1.0 - smoothstep(radius * 0.45, radius, d)) * visibility;
            mound = max(mound, stone * radius);
            shade += stone * (random.y - 0.55);
        }
    }
    return vec2(mound, shade);
}
void fragment() {
    vec2 p = world_pos.xz;
    float pixel_m = max(length(dFdx(p)), length(dFdy(p)));
    float fine = texture(grain, p * 0.6).r;
    float grains = texture(grain, p * 0.17 + vec2(0.317, 0.129)).r;
    float broad = texture(grain, p * 0.004).r;
    vec2 stones = gravel(p * 7.0, pixel_m * 7.0);
    vec2 grit = gravel(p * 31.0 + vec2(17.7), pixel_m * 31.0);
    float slope = 1.0 - world_normal.y;
    vec2 ll = region_anchor + vec2(-p.y / 1737400.0, p.x / (1737400.0 * max(0.00001, cos(region_anchor.x))));
    vec2 region_uv = vec2(ll.y / (2.0 * PI) + 0.5, 0.5 - ll.x / PI);
    vec3 dust = texture(regional_albedo, region_uv).rgb * (0.94 + broad * 0.12);
    dust *= 0.78 + fine * 0.25 + grains * 0.16;
    dust += vec3(stones.y * 0.17 + grit.y * 0.11);
    ALBEDO = mix(dust, dust * 0.8, smoothstep(0.12, 0.4, slope));
    // Photographic tiles contain baked illumination. The region colour above
    // comes from robust bright samples; sunlight/shadows are rendered live.
    if (coverage) {
        ALBEDO = mix(vec3(0.2, 0.52, 0.53), vec3(0.93, 0.59, 0.19), smoothstep(0.045, 0.17, slope));
    }
    ROUGHNESS = 0.94 + grains * 0.05;
    SPECULAR = 0.18;
    float height = fine * 0.0008 + grains * 0.0015 + stones.x * 0.045 + grit.x * 0.009;
    // Surface-gradient bump mapping; relief is measured in metres, not screen pixels.
    vec3 sigma_x = dFdx(VERTEX);
    vec3 sigma_y = dFdy(VERTEX);
    vec3 r1 = cross(sigma_y, NORMAL);
    vec3 r2 = cross(NORMAL, sigma_x);
    float det = dot(sigma_x, r1);
    vec3 gradient = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
    NORMAL = normalize(max(abs(det), 0.00000001) * NORMAL - gradient);
}
