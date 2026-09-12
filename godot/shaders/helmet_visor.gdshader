shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
// Curved sun visor. `shade` fades in a gold darkening that hugs the top of the
// dome and both cheeks, thinning toward a clear window over the lower face, so H
// smoothly trades clarity for a gold sun shield.
uniform float shade : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glass_tint : source_color = vec3(0.65, 0.84, 0.92);
uniform vec3 gold_tint : source_color = vec3(0.30, 0.17, 0.03);
uniform float clear_alpha = 0.12;
uniform float shade_alpha = 0.78;
uniform float gradient_top = 0.34;
uniform float gradient_bottom = -0.10;
uniform float side_start = 0.40;
uniform float side_end = 0.60;
uniform float rim = 0.42;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
    local_position = VERTEX;
    local_normal = NORMAL;
}
void fragment() {
    // Top-down band plus a left/right cheek band; the clear window is what neither reaches.
    float top = smoothstep(gradient_bottom, gradient_top, local_position.y);
    float side = smoothstep(side_start, side_end, abs(local_position.x));
    float amount = max(top, side) * shade;
    float fresnel = pow(1.0 - clamp(dot(normalize(local_normal), normalize(VIEW)), 0.0, 1.0), 3.0);
    ALBEDO = mix(glass_tint, gold_tint, amount) + fresnel * rim * (1.0 - amount);
    ALPHA = clamp(mix(clear_alpha, shade_alpha, amount) + fresnel * rim * (1.0 - amount), 0.0, 1.0);
    EMISSION = gold_tint * amount * 0.18;
    ROUGHNESS = 0.06;
    METALLIC = 0.0;
    SPECULAR = 0.5;
}
