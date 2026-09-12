shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, cull_disabled;

// "Ligne claire" / Moebius-like full-screen ink: depth-only silhouette contours.
// Normal-based edge detection is deliberately gone -- it inked every blade of
// grass and every small surface detail. This now reacts only to a large jump in
// depth, i.e. the outer contour of buildings, vehicles, the dome, characters.
// Needs the Forward+ renderer.
//
// Known limitation: same as comic_outline.gdshader -- alpha-transparent
// geometry (rain, wheel tracks, greenhouse glass, the helmet visor) loses
// its colour under this outline; see that file's comment for what was tried.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 line_color : source_color = vec4(0.025, 0.02, 0.018, 1.0);
uniform float line_width_px : hint_range(0.5, 4.0) = 1.0;
// Raise this if fine detail (grass, gravel) still gets outlined: 0.05, then 0.08.
uniform float depth_sensitivity : hint_range(0.001, 0.2) = 0.08;
uniform float line_strength : hint_range(0.0, 1.0) = 0.90;
uniform float silhouette_strength : hint_range(0.0, 2.0) = 1.0;
// Metres past which lines fade out, so the far horizon stays clean.
uniform float far_fade_m : hint_range(50.0, 20000.0) = 3000.0;

varying mat4 inv_proj;

float get_depth(vec2 uv) {
	float depth = texture(depth_texture, uv).r;
	vec4 view = inv_proj * vec4(vec3(uv * 2.0 - 1.0, depth), 1.0);
	return -(view.xyz / view.w).z;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	inv_proj = inverse(PROJECTION_MATRIX);
}

void fragment() {
	vec2 pixel = 1.0 / vec2(textureSize(screen_texture, 0));
	vec2 o = pixel * line_width_px;
	vec2 uv = SCREEN_UV;

	vec3 original = texture(screen_texture, uv).rgb;
	float dc = get_depth(uv);

	float dl = get_depth(uv - vec2(o.x, 0.0));
	float dr = get_depth(uv + vec2(o.x, 0.0));
	float du = get_depth(uv - vec2(0.0, o.y));
	float dd = get_depth(uv + vec2(0.0, o.y));
	float dul = get_depth(uv - o);
	float dur = get_depth(uv + vec2(o.x, -o.y));
	float ddl = get_depth(uv + vec2(-o.x, o.y));
	float ddr = get_depth(uv + o);

	float depth_edge = 0.0;
	depth_edge = max(depth_edge, abs(dc - dl));
	depth_edge = max(depth_edge, abs(dc - dr));
	depth_edge = max(depth_edge, abs(dc - du));
	depth_edge = max(depth_edge, abs(dc - dd));
	depth_edge = max(depth_edge, abs(dc - dul));
	depth_edge = max(depth_edge, abs(dc - dur));
	depth_edge = max(depth_edge, abs(dc - ddl));
	depth_edge = max(depth_edge, abs(dc - ddr));
	depth_edge /= max(dc, 0.1);

	float silhouette = smoothstep(depth_sensitivity, depth_sensitivity * 2.5, depth_edge);

	float edge = silhouette * silhouette_strength;
	edge = clamp(edge * line_strength, 0.0, 1.0);
	edge *= 1.0 - smoothstep(far_fade_m * 0.6, far_fade_m, dc);

	ALBEDO = mix(original, line_color.rgb, edge * line_color.a);
}
