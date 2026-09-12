shader_type sky;

uniform sampler2D earth_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.2, 0.15, -0.97);
uniform vec3 earth_direction = vec3(-0.1, 0.12, -0.98);
uniform float sun_radius = 0.00698;
uniform float earth_radius = 0.0349;
uniform float earth_rotation = 0.0;
uniform bool show_bodies = true;
uniform vec4 stars[32];
uniform vec3 star_colors[32];

float hash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float nebula_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
                   mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
                   mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

vec3 galaxy_background(vec3 ray) {
    // An illustrative galactic band, anchored to sky directions, never to the camera.
    vec3 pole = normalize(vec3(0.65, 0.45, 0.1));
    float latitude = dot(ray, pole);
    float broad = exp(-latitude * latitude / 0.026);
    float cloud = nebula_noise(ray * 12.0) * 0.55
                + nebula_noise(ray * 29.0 + 7.0) * 0.28
                + nebula_noise(ray * 71.0) * 0.12
                + nebula_noise(ray * 163.0) * 0.05;
    float center = pow(max(dot(ray, normalize(vec3(-0.38, 0.7, -0.6))), 0.0), 8.0);
    float lane = latitude + (nebula_noise(ray * 19.0) - 0.5) * 0.095;
    float absorption = smoothstep(0.24, 0.75, nebula_noise(ray * 37.0 + 22.0));
    float dust = 1.0 - exp(-lane * lane / 0.0007) * (0.35 + absorption * 0.4);
    vec3 haze = mix(vec3(0.11, 0.135, 0.19), vec3(0.28, 0.235, 0.18), center);
    vec3 result = haze * broad * (0.22 + cloud * cloud * 2.8) * dust;

    // Sparse jittered cells on six sky faces: thousands of points at constant cost.
    vec3 a = abs(ray);
    vec2 uv;
    float face;
    if (a.x >= a.y && a.x >= a.z) { uv = ray.yz / a.x; face = sign(ray.x); }
    else if (a.y >= a.z) { uv = ray.xz / a.y; face = 3.0 * sign(ray.y); }
    else { uv = ray.xy / a.z; face = 5.0 * sign(ray.z); }
    vec2 p = uv * 220.0;
    vec2 cell = floor(p);
    float pixel = min(max(length(dFdx(p)), length(dFdy(p))), 1.0);
    float radius = max(0.055, pixel * 0.55);
    float density = 0.009 + broad * 0.045 * dust;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 c = cell + vec2(float(x), float(y));
            vec3 seed = vec3(c, face * 73.0);
            float pick = hash3(seed);
            if (pick < density) {
                vec2 jitter = vec2(hash3(seed + 13.7), hash3(seed + 41.3));
                vec2 delta = p - c - jitter;
                float core = exp(-dot(delta, delta) / (2.0 * radius * radius));
                float power = 0.18 + pow(hash3(seed + 91.1), 6.0) * 1.4;
                vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.87, 0.69), jitter.x);
                result += tint * core * power;
            }
        }
    }
    return result;
}

void sky() {
    vec3 ray = normalize(EYEDIR);
    vec3 color = vec3(0.0008, 0.0011, 0.002);
    if (show_bodies && ray.y > 0.0) {
        color += galaxy_background(ray);
        float pixel_angle = max(length(dFdx(ray)), length(dFdy(ray)));
        for (int i = 0; i < 32; i++) {
            vec3 delta = ray - stars[i].xyz;
            float d2 = dot(delta, delta);
            float radius = max(pixel_angle * 0.7, 0.0006 + stars[i].w * 0.0005);
            if (d2 < radius * radius * 25.0) {
                float core = exp(-d2 / (radius * radius * 2.0));
                color += star_colors[i] * core * (1.4 + stars[i].w * 2.0);
            }
        }
        float sun_angle = acos(clamp(dot(ray, sun_direction), -1.0, 1.0));
        float edge = max(fwidth(sun_angle), 0.00005);
        float disk = 1.0 - smoothstep(sun_radius - edge, sun_radius + edge, sun_angle);
        // Small optical bloom around the disk, not atmospheric scattering over the Moon.
        float halo = exp(-max(sun_angle - sun_radius, 0.0) * 350.0) * 0.35;
        color = mix(color, vec3(1.0, 0.94, 0.8) * 12.0, disk);
        color += vec3(1.0, 0.94, 0.8) * halo;

        float earth_angle = acos(clamp(dot(ray, earth_direction), -1.0, 1.0));
        if (earth_angle < earth_radius * 1.08) {
            vec3 right = normalize(cross(earth_direction, vec3(0.0, 1.0, 0.0)));
            vec3 up = normalize(cross(right, earth_direction));
            vec2 xy = vec2(dot(ray, right), dot(ray, up)) / sin(earth_radius);
            float r2 = dot(xy, xy);
            float aa = max(fwidth(r2), 0.001);
            float mask = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r2);
            float z = sqrt(max(0.0, 1.0 - r2));
            vec3 n = vec3(xy, z);
            vec2 uv = vec2(fract(atan(n.x, n.z) / 6.2831853 + 0.5 + earth_rotation), acos(clamp(n.y, -1.0, 1.0)) / 3.14159265);
            vec3 albedo = texture(earth_map, uv).rgb;
            // Illustration lighting preserves the recognizable land/ocean/cloud map.
            float lighting = 0.24 + 0.95 * max(dot(normalize(n), normalize(vec3(-0.4, 0.35, 0.85))), 0.0);
            vec3 earth = albedo * lighting;
            earth += vec3(0.06, 0.21, 0.55) * pow(1.0 - z, 3.0) * 0.35;
            color = mix(color, earth, mask);
            float rim = exp(-abs(sqrt(r2) - 1.0) * 90.0) * 0.24;
            color += vec3(0.12, 0.38, 0.85) * rim;
        }
    }
    COLOR = color;
}
